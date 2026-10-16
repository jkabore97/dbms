import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/accounting/models.dart';
import 'package:kaj_app/core/association/association_analytics.dart';
import 'package:kaj_app/core/association/members.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/export/file_out.dart';
import 'package:kaj_app/core/export/report_export.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/money/money_types.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/accounting/account_ledger_screen.dart';
import 'package:kaj_app/features/accounting/balance_sheet_screen.dart';
import 'package:kaj_app/features/accounting/chart_of_accounts_screen.dart';
import 'package:kaj_app/features/accounting/income_statement_screen.dart';
import 'package:kaj_app/features/accounting/journal_screen.dart';
import 'package:kaj_app/features/accounting/report_exports.dart';
import 'package:kaj_app/features/accounting/trial_balance_screen.dart';
import 'package:kaj_app/features/church/members/members_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/money/expense_flow.dart';
import 'package:kaj_app/features/money/income_flow.dart';
import 'package:kaj_app/features/money/money_types_ui.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Batch 153 (149): the recette and dépense types a business adds itself,
/// and « Télécharger » (PDF, CSV) on every accounting report.
/// Names: brand-like businesses, « Le trésorier », « Membre n° 01 »;
/// Ouagadougou the only town.

const _assoc = OrgSummary(id: 'a1', name: 'Cercle Horizon', profile: 'association', roles: ['owner']);
const _summaryObserver = OrgSummary(
    id: 'a1', name: 'Cercle Horizon', profile: 'association', roles: ['observer'], visibility: 'summary');
const _farm = OrgSummary(id: 'f1', name: 'Ferme Aurore', profile: 'farm', roles: ['owner']);
const _shop = OrgSummary(id: 's1', name: 'Kiosque Vega', profile: 'retail', roles: ['employee']);

MoneyType _type(String id, String name, String dir,
        {String? label, String? description, bool active = true, int? order, int entries = 0, String code = '4100'}) =>
    MoneyType(
        id: id,
        name: name,
        direction: dir,
        label: label,
        description: description,
        active: active,
        sortOrder: order,
        entryCount: entries,
        code: code);

/// An association's chart as the server holds it: the seeded headings, the
/// built-in cards' accounts, two « Autre » names already used, an expense.
List<MoneyType> _chart() => [
      _type('t-tithes', 'Tithes', 'in', code: '4000'),
      _type('t-don', 'Donations', 'in', code: '4030'),
      _type('t-cot', 'Cotisations', 'in', code: '4040'),
      _type('t-quete', 'Quête', 'in', description: 'Le dimanche, à la sortie', code: '4050', entries: 3),
      _type('t-loyer', 'Loyer de salle', 'in', code: '4060'),
      _type('t-kermesse', 'Kermesse', 'in', code: '4070', active: false, entries: 2),
      _type('e-rent', 'Rent', 'out', code: '5010'),
      _type('e-forage', 'Réparation du forage', 'out', description: 'Pompe et tuyaux', code: '5100'),
    ];

/// The server, in memory.
class _Types implements MoneyTypesApi {
  _Types(this.types);
  List<MoneyType> types;
  bool offline = false;
  bool before149 = false;
  final added = <Map<String, Object?>>[];
  final updated = <Map<String, Object?>>[];
  List<String>? ordered;

  @override
  bool get isConfigured => true;

  void _guard() {
    if (offline) throw const SocketException('Failed host lookup');
    if (before149) throw const TypesNotOnServer();
  }

  @override
  Future<List<MoneyType>> moneyTypes(String orgId) async {
    _guard();
    return types;
  }

  @override
  Future<String> addMoneyType(String orgId,
      {required String direction, required String name, String? description, bool adopt = false}) async {
    _guard();
    if (types.any((t) => t.direction == direction && typeKey(t.name) == typeKey(name))) {
      throw DuplicateTypeException(name);
    }
    added.add({'direction': direction, 'name': name, 'description': description});
    final id = 'new${added.length}';
    types = [...types, _type(id, name, direction, description: description, code: '4999')];
    return id;
  }

  @override
  Future<void> updateMoneyType(String orgId,
      {required String direction, required String id, String? name, String? description, bool? active}) async {
    _guard();
    updated.add({'id': id, 'name': name, 'description': description, 'active': active});
    types = [
      for (final t in types)
        if (t.id != id)
          t
        else
          MoneyType(
            id: t.id,
            name: t.entryCount == 0 && name != null ? name : t.name,
            direction: t.direction,
            code: t.code,
            label: t.entryCount > 0 && name != null ? name : t.label,
            description: description ?? t.description,
            active: active ?? t.active,
            sortOrder: t.sortOrder,
            entryCount: t.entryCount,
          ),
    ];
  }

  @override
  Future<void> reorderMoneyTypes(String orgId, {required String direction, required List<String> ids}) async {
    _guard();
    ordered = ids;
  }
}

/// The books' reports, in memory.
class _Books extends AccountingRepository {
  _Books() : super(null);
  List<StatementLine> income = const [];
  List<StatementLine> balance = const [];
  List<TrialBalanceRow> trial = const [];
  List<JournalRow> journalRows = const [];
  List<LedgerMovement> moves = const [];
  List<LedgerAccount> chart = const [];
  final journalCalls = <int>[];

  @override
  Future<List<StatementLine>> incomeStatement(String orgId, {DateTime? from, DateTime? to}) async => income;
  @override
  Future<List<StatementLine>> balanceSheet(String orgId, {DateTime? asOf}) async => balance;
  @override
  Future<List<TrialBalanceRow>> trialBalance(String orgId, {DateTime? from, DateTime? to}) async => trial;
  @override
  Future<List<JournalRow>> journal(String orgId, {DateTime? from, DateTime? to, int limit = 100, int offset = 0}) async {
    journalCalls.add(offset);
    return journalRows.skip(offset).take(limit).toList();
  }

  @override
  Future<List<LedgerMovement>> accountLedger(String orgId, String accountId,
          {DateTime? from, DateTime? to, int limit = 200}) async =>
      moves.take(limit).toList();
  @override
  Future<List<LedgerAccount>> chartOfAccounts(String orgId) async => chart;
}


List<StatementLine> _statement() => const [
      StatementLine(section: 'income', code: '4040', name: 'Cotisations', amount: 12000),
      StatementLine(section: 'income', code: '4050', name: 'Quête', amount: 7500),
      StatementLine(section: 'expense', code: '5010', name: 'Rent', amount: 15000),
      StatementLine(section: 'total', code: '1', name: 'Produits', amount: 19500),
      StatementLine(section: 'total', code: '2', name: 'Charges', amount: 15000),
      StatementLine(section: 'total', code: '3', name: 'Résultat', amount: 4500),
    ];

JournalRow _entry(int i, {String direction = 'in', double amount = 1000}) => JournalRow(
      entryId: 'j$i',
      occurredAt: DateTime(2026, 10, 1 + (i % 15), 9),
      label: 'Quête — n° $i',
      amount: amount,
      direction: direction,
      reversed: false,
      isReversal: false,
      recordedBy: 'Le trésorier',
      debitNames: 'Cash on Hand',
      creditNames: 'Quête',
    );

Widget _app(Widget home, {String lang = 'fr', ThemeData? theme}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      theme: theme,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );


void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });
  tearDown(() {
    debugFileOut = null;
    trCurrent = 'fr';
  });

  Future<void> size(WidgetTester tester, {double w = 390, double h = 1400, double scale = 1}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<LocalDb> openDb(WidgetTester tester) async {
    final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
    addTearDown(() => tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await db!.close();
        }));
    return db!;
  }

  // Every await on the phone's database is a real one: a few rounds, each
  // letting it answer and the widget's zone carry on.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('the types: what is a duplicate, what is a card', () {
    test('a name is taken accents, case and spaces aside; a built-in card word too', () {
      final list = MoneyTypesList(types: _chart());
      expect(list.taken('in', 'quete'), isTrue);
      expect(list.taken('in', '  QUÊTE '), isTrue);
      expect(list.taken('in', 'Don'), isTrue, reason: '« Don » is a card');
      expect(list.taken('in', 'dons'), isTrue, reason: "'Donations' reads « Dons »");
      expect(list.taken('in', 'Kermesse'), isTrue, reason: 'a hidden type still holds its name');
      expect(list.taken('in', 'Dîme'), isFalse, reason: "'Tithes' reads « Dîmes », not « Dîme »");
      expect(list.taken('out', 'loyer'), isTrue, reason: "'Rent' reads « Loyer »");
      expect(list.taken('out', 'Quête'), isFalse, reason: 'an expense may share an income name');
      expect(list.taken('in', 'Quête', except: 't-quete'), isFalse, reason: 'renaming itself');
    });

    test('step 1 cards: the added ones in order, not the built-ins, the church headings or the hidden', () {
      final list = MoneyTypesList(types: [
        ..._chart(),
        _type('t-dime', 'Dîme', 'in', order: 1, code: '4080'),
      ]);
      expect(list.cards('in').map((t) => t.display), ['Dîme', 'Quête', 'Loyer de salle']);
      expect(list.manageable('in').map((t) => t.name), ['Dîme', 'Quête', 'Loyer de salle', 'Kermesse']);
      expect(list.cards('out').map((t) => t.display), ['Loyer', 'Réparation du forage']);
      final labelled = _type('x', 'Quête', 'in', label: 'Quête du dimanche', entries: 4);
      expect(labelled.display, 'Quête du dimanche');
      expect(labelled.name, 'Quête', reason: 'what entries are filed under');
    });

    test('who may add and hide: the people who record, never an observer or an approver', () {
      expect(canWriteTypes(_assoc), isTrue);
      expect(canWriteTypes(_shop), isTrue, reason: 'an employee');
      expect(canWriteTypes(_summaryObserver), isFalse);
      expect(canWriteTypes(const OrgSummary(id: 'a', name: 'X', profile: 'association', roles: ['approver'])), isFalse);
      expect(canWriteTypes(const OrgSummary(id: 'a', name: 'X', profile: 'farm', roles: ['owner'], suspended: true)),
          isFalse);
      expect(typeKey('  Œuvres   SOCIALES '), 'oeuvres sociales');
    });
  });

  group('the phone keeps the types', () {
    late LocalDb db;
    setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
    tearDown(() => db.close());

    test('online kept; offline read back (step 1 shows them with no signal)', () async {
      final api = _Types(_chart());
      final book = MoneyTypesBook(api: api, db: db);
      final online = await book.load('a1');
      expect(online.fromPhone, isFalse);
      api.offline = true;
      final offline = await book.load('a1');
      expect(offline.fromPhone, isTrue);
      expect(offline.cards('in').map((t) => t.display), ['Quête', 'Loyer de salle']);
      expect(offline.cards('in').first.description, 'Le dimanche, à la sortie');
      // Cleared at sign-out with the person's own prefs.
      await db.clearIdentity();
      expect((await book.cached('a1')).types, isEmpty);
    });

    test('a duplicate is refused before the server is asked, and when the server says so (MA149)', () async {
      final api = _Types(_chart());
      final book = MoneyTypesBook(api: api, db: db);
      final list = await book.load('a1');
      await expectLater(book.add('a1', list, direction: 'in', name: 'QUETE'), throwsA(isA<DuplicateTypeException>()));
      expect(api.added, isEmpty);
      // The server knows one the phone does not.
      api.types = [...api.types, _type('t-other', 'Collecte du mois', 'in')];
      await expectLater(book.add('a1', list, direction: 'in', name: 'collecte du mois'),
          throwsA(isA<DuplicateTypeException>()));
    });

    test('added online: the server account; with no signal: on the phone and in the outbox, adopt', () async {
      final api = _Types(_chart());
      final book = MoneyTypesBook(api: api, db: db);
      var list = await book.load('a1');
      final dime = await book.add('a1', list, direction: 'in', name: ' Dîme ', description: 'Le dixième');
      expect(dime.id, 'new1');
      expect(api.added.single, {'direction': 'in', 'name': 'Dîme', 'description': 'Le dixième'});
      expect(await db.pendingActions(), isEmpty);

      api.offline = true;
      list = await book.load('a1');
      final hall = await book.add('a1', list, direction: 'in', name: 'Location de chaises');
      expect(hall.pending, isTrue);
      final queued = await db.pendingActions();
      expect(queued.single['action'], 'save_money_type');
      expect(jsonDecode(queued.single['payload'] as String),
          {'p_org_id': 'a1', 'p_direction': 'in', 'p_name': 'Location de chaises', 'p_description': null, 'p_adopt': true});
      final offline = await book.load('a1');
      expect(offline.cards('in').map((t) => t.display), contains('Location de chaises'));
      // Back online, the outbox sent it: the server's row, the phone's dropped.
      api.offline = false;
      api.types = [...api.types, _type('srv', 'Location de chaises', 'in', code: '4990')];
      final back = await book.load('a1');
      expect(back.types.where((t) => t.name == 'Location de chaises').map((t) => t.id), ['srv']);
    });

    test('before 149: added on the phone only (no outbox row), renaming said to come later', () async {
      final api = _Types(_chart())..before149 = true;
      final book = MoneyTypesBook(api: api, db: db);
      await db.recordEntry(orgId: 'a1', amount: 500, direction: 'in', label: 'Location', category: 'Location de la salle');
      final list = await book.load('a1');
      expect(list.serverReady, isFalse);
      expect(list.cards('in').map((t) => t.name), ['Location de la salle'],
          reason: 'the names « Autre » was given are cards');
      final added = await book.add('a1', list, direction: 'in', name: 'Dîme');
      expect(added.pending, isTrue);
      expect((await db.pendingActions()).where((r) => r['action'] == 'save_money_type'), isEmpty);
      await expectLater(book.update('a1', list, list.cards('in').first, active: false),
          throwsA(isA<TypesNotOnServer>()));
    });

    test('the outbox: a queued type on a server before 149 is done, not retried for ever', () async {
      await db.queueMoneyType(orgId: 'a1', params: {'p_org_id': 'a1', 'p_direction': 'in', 'p_name': 'Dîme', 'p_adopt': true});
      final calls = <String>[];
      final sync = SyncService(db, SupabaseClient('https://example.supabase.co', 'anon-key'),
          currentUserId: () => 'u1', post: (action, params) async {
        calls.add(action);
        throw const PostgrestException(message: 'Could not find the function public.save_money_type', code: 'PGRST202');
      });
      await sync.syncNow();
      expect(calls, ['save_money_type']);
      expect(await db.pendingCount(), 0);
    });

    test('renaming, hiding and ordering need the network', () async {
      final api = _Types(_chart());
      final book = MoneyTypesBook(api: api, db: db);
      final list = await book.load('a1');
      api.offline = true;
      final quete = list.cards('in').first;
      await expectLater(book.update('a1', list, quete, active: false), throwsA(isA<TypesNeedNetwork>()));
      await expectLater(book.reorder('a1', 'in', list.cards('in')), throwsA(isA<TypesNeedNetwork>()));
    });
  });

  group('Recette step 1', () {
    testWidgets('the four cards, then the association\'s types, then « Ajouter »; a type\'s entry lands in its account',
        (tester) async {
      await size(tester);
      final db = await openDb(tester);
      final api = _Types(_chart());
      await tester.pumpWidget(_app(IncomeFlow(
          db: db, orgId: 'a1', types: api, canEditTypes: true, store: MemoryFlowStore())));
      await settle(tester);
      for (final k in ['cotisation', 'don', 'vente', 'autre', 'type:t-quete', 'type:t-loyer', '__add_type__']) {
        expect(find.byKey(Key('flow-option-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('flow-option-type:t-kermesse')), findsNothing, reason: 'hidden');
      expect(find.byKey(const Key('flow-option-type:t-tithes')), findsNothing, reason: 'church heading');
      expect(find.text('Le dimanche, à la sortie'), findsOneWidget);
      expect(find.byKey(const Key('income-manage-types')), findsOneWidget);

      await tester.tap(find.byKey(const Key('flow-option-type:t-quete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      // No « Quel nom ? »: straight to « De qui ? ».
      expect(find.byKey(const Key('flow-step-other')), findsNothing);
      expect(find.byKey(const Key('flow-step-who')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('income-amount')), '7500');
      await tester.pump();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      expect(find.text('Quête'), findsWidgets);
      await tester.tap(find.byKey(const Key('flow-save')));
      await settle(tester);
      final rows = await tester.runAsync(() => db.pendingActions());
      final p = jsonDecode(rows!.single['payload'] as String) as Map;
      expect(p['p_category'], 'Quête', reason: 'filed under the type\'s account (record_entry → ensure_account)');
      expect(p['p_label'], 'Quête');
      expect(p['p_direction'], 'in');
    });

    testWidgets('« Ajouter un type de recette »: a duplicate refused, a new one added, chosen, its card there',
        (tester) async {
      await size(tester);
      final db = await openDb(tester);
      final api = _Types(_chart());
      await tester.pumpWidget(_app(IncomeFlow(
          db: db, orgId: 'a1', types: api, canEditTypes: true, store: MemoryFlowStore())));
      await settle(tester);
      await tester.tap(find.byKey(const Key('flow-option-__add_type__')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('type-name')), 'quete');
      await tester.pump();
      expect(find.text('Ce nom est déjà pris.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('type-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('type-error')), findsOneWidget);
      expect(api.added, isEmpty);
      await tester.enterText(find.byKey(const Key('type-name')), 'Dîme');
      await tester.enterText(find.byKey(const Key('type-description')), 'Le dixième des revenus');
      await tester.pump();
      await tester.tap(find.byKey(const Key('type-save')));
      await settle(tester);
      expect(api.added.single['name'], 'Dîme');
      expect(find.byKey(const Key('flow-option-type:new1')), findsOneWidget);
      expect(find.text('Le dixième des revenus'), findsOneWidget);
      final chosen = tester.widget<Material>(find
          .ancestor(of: find.byKey(const Key('flow-option-type:new1')), matching: find.byType(Material))
          .first);
      expect(chosen.color, Theme.of(tester.element(find.byType(IncomeFlow))).colorScheme.primaryContainer);
    });

    testWidgets('« Gérer »: hiding keeps the type in the list (and its entries), off step 1', (tester) async {
      await size(tester);
      final db = await openDb(tester);
      final api = _Types(_chart());
      await tester.pumpWidget(_app(IncomeFlow(
          db: db, orgId: 'a1', types: api, canEditTypes: true, store: MemoryFlowStore())));
      await settle(tester);
      await tester.tap(find.byKey(const Key('income-manage-types')));
      await settle(tester);
      expect(find.byType(ManageTypesScreen), findsOneWidget);
      expect(find.byKey(const Key('type-row-Kermesse')), findsOneWidget, reason: 'a hidden one, listed');
      expect(find.textContaining('masqué'), findsOneWidget);
      await tester.tap(find.byKey(const Key('type-shown-Quête')));
      await settle(tester);
      expect(api.updated.single, {'id': 't-quete', 'name': null, 'description': null, 'active': false});
      expect(find.byKey(const Key('type-row-Quête')), findsOneWidget, reason: 'still listed, hidden');
      expect(find.textContaining('3 écriture(s)'), findsOneWidget, reason: 'its entries are still there');
      Navigator.of(tester.element(find.byType(ManageTypesScreen))).pop();
      await settle(tester);
      expect(find.byKey(const Key('flow-option-type:t-quete')), findsNothing);
      expect(find.byKey(const Key('flow-option-type:t-loyer')), findsOneWidget);
    });

    testWidgets('« Gérer »: renaming a used type changes its card only; order sent', (tester) async {
      await size(tester);
      final db = await openDb(tester);
      final api = _Types(_chart());
      final book = MoneyTypesBook(api: api, db: db);
      await tester.pumpWidget(_app(ManageTypesScreen(book: book, orgId: 'a1', direction: 'in')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('type-edit-Quête')));
      await tester.pumpAndSettle();
      expect(find.textContaining('elles le gardent, seule la carte change'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('type-name')), 'Quête du dimanche');
      await tester.tap(find.byKey(const Key('type-save')));
      await settle(tester);
      expect(api.updated.single['name'], 'Quête du dimanche');
      expect(api.types.firstWhere((t) => t.id == 't-quete').name, 'Quête');
      expect(find.text('Quête du dimanche'), findsOneWidget);
      // Drag « Loyer de salle » above.
      final handle = find.descendant(
          of: find.byKey(const Key('type-row-Loyer de salle')), matching: find.byIcon(Icons.drag_indicator));
      await tester.drag(handle, const Offset(0, -80));
      await settle(tester);
      expect(api.ordered?.first, 't-loyer');
    });

    testWidgets('no signal: step 1 shows the types the phone kept; a new one waits in the outbox', (tester) async {
      await size(tester);
      final db = await openDb(tester);
      final api = _Types(_chart());
      await tester.runAsync(() => MoneyTypesBook(api: api, db: db).load('a1'));
      api.offline = true;
      await tester.pumpWidget(_app(IncomeFlow(
          db: db, orgId: 'a1', types: api, canEditTypes: true, store: MemoryFlowStore())));
      await settle(tester);
      expect(find.byKey(const Key('flow-option-type:t-quete')), findsOneWidget);
      expect(find.byKey(const Key('flow-option-type:t-loyer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-option-__add_type__')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('type-name')), 'Kermesse de Noël');
      await tester.pump();
      await tester.tap(find.byKey(const Key('type-save')));
      await settle(tester);
      expect(find.text('Kermesse de Noël'), findsWidgets);
      final rows = await tester.runAsync(() => db.pendingActions());
      expect(rows!.map((r) => r['action']), ['save_money_type']);
    });

    testWidgets('an observer: the cards, no « Ajouter », no « Gérer »', (tester) async {
      await size(tester);
      final db = await openDb(tester);
      await tester.pumpWidget(_app(IncomeFlow(db: db, orgId: 'a1', types: _Types(_chart()), store: MemoryFlowStore())));
      await settle(tester);
      expect(find.byKey(const Key('flow-option-type:t-quete')), findsOneWidget);
      expect(find.byKey(const Key('flow-option-__add_type__')), findsNothing);
      expect(find.byKey(const Key('income-manage-types')), findsNothing);
    });

    testWidgets('320 × 1.3: step 1 with types, the form and the list fit', (tester) async {
      await size(tester, w: 320, h: 640, scale: 1.3);
      final db = await openDb(tester);
      final api = _Types(_chart());
      await tester.pumpWidget(_app(IncomeFlow(
          db: db, orgId: 'a1', types: api, canEditTypes: true, store: MemoryFlowStore())));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const Key('flow-option-__add_type__')), 200,
          scrollable: find.byType(Scrollable).first);
      // Clear of the flow's bottom bar.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-__add_type__')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('type-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byKey(const Key('type-name')))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(ManageTypesScreen(book: MoneyTypesBook(api: api, db: db), orgId: 'a1', direction: 'in')));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Dépense step 1 — a shop, a farm, an association', () {
    for (final org in [_farm, _shop, _assoc]) {
      testWidgets('${org.profile}: the expense types as tiles, « Ajouter un type de dépense », filed under the type',
          (tester) async {
        await size(tester);
        final db = await openDb(tester);
        final api = _Types(_chart());
        await tester.pumpWidget(_app(ExpenseFlow(
            db: db, orgId: org.id, profile: org.profile, types: api, canEditTypes: canWriteTypes(org),
            store: MemoryFlowStore())));
        await settle(tester);
        expect(find.byKey(const Key('heading-Rent')), findsOneWidget);
        expect(find.text('Loyer'), findsOneWidget);
        expect(find.byKey(const Key('heading-Réparation du forage')), findsOneWidget);
        expect(find.text('Pompe et tuyaux'), findsOneWidget);
        expect(find.byKey(const Key('heading-__add__')), findsOneWidget);
        expect(find.byKey(const Key('expense-manage-types')), findsOneWidget);
        await tester.tap(find.byKey(const Key('heading-__add__')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('type-name')), 'LOYER');
        await tester.pump();
        expect(find.text('Ce nom est déjà pris.'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('type-name')), 'Carburant');
        await tester.pump();
        await tester.tap(find.byKey(const Key('type-save')));
        await settle(tester);
        expect(api.added.single, {'direction': 'out', 'name': 'Carburant', 'description': null});
        expect(find.byKey(const Key('heading-Carburant')), findsOneWidget);
        await tester.tap(find.byKey(const Key('flow-next')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('expense-amount')), '3000');
        await tester.pump();
        for (var i = 0; i < 4; i++) {
          if (find.byKey(const Key('flow-summary')).evaluate().isNotEmpty) break;
          await tester.tap(find.byKey(const Key('flow-next')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('flow-save')));
        await settle(tester);
        final rows = await tester.runAsync(() => db.pendingActions());
        final p = jsonDecode(rows!.single['payload'] as String) as Map;
        expect(p['p_category'], 'Carburant');
        expect(p['p_direction'], 'out');
      });
    }

    testWidgets('320 × 1.3: the tiles with descriptions fit', (tester) async {
      await size(tester, w: 320, h: 900, scale: 1.3);
      final db = await openDb(tester);
      await tester.pumpWidget(_app(ExpenseFlow(
          db: db, orgId: 'f1', profile: 'farm', types: _Types(_chart()), canEditTypes: true, store: MemoryFlowStore())));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('« Télécharger »: the CSV', () {
    final now = DateTime(2026, 10, 16, 14, 5);

    test('exact for a sample: BOM, « ; », header, rows, totals, plain numbers, ISO dates', () {
      final e = incomeStatementExport(_assoc, _statement(), from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), now: now);
      const expected = '﻿'
          'Compte de résultat;Cercle Horizon\r\n'
          'Période;2026-10-01;2026-10-16\r\n'
          'Généré le;2026-10-16\r\n'
          'Monnaie;FCFA\r\n'
          '\r\n'
          'Recettes\r\n'
          'Code;Compte;Montant (FCFA)\r\n'
          '4040;Cotisations;12000\r\n'
          '4050;Quête;7500\r\n'
          ';Total des recettes;19500\r\n'
          '\r\n'
          'Dépenses\r\n'
          'Code;Compte;Montant (FCFA)\r\n'
          '5010;Loyer;15000\r\n'
          ';Total des dépenses;15000\r\n'
          '\r\n'
          'Résultat\r\n'
          'Ligne;Montant (FCFA)\r\n'
          'Reçu;19500\r\n'
          'Dépensé;15000\r\n'
          'Bénéfice;4500\r\n';
      expect(e.toCsv(), expected);
      final bytes = e.csvBytes();
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: 'UTF-8 BOM');
      expect(utf8.decode(bytes.sublist(3)), contains('Quête'));
      expect(e.baseName, 'compte-de-resultat_cercle-horizon_2026-10-01_2026-10-16');
    });

    test('decimals in a money with cents (comma, no grouping), quoting, a formula never run', () {
      final e = ReportExport(
        title: 'Test',
        fileStem: 't',
        orgName: 'Kiosque Vega',
        currency: 'EUR',
        generatedAt: now,
        sections: [
          ExportSection(columns: const [ExportColumn('Libellé'), ExportColumn('Montant', money: true), ExportColumn('Date', date: true)], rows: [
            ['Achat; "spécial"', 1234567.5, DateTime(2026, 9, 3)],
            ['=SOMME(A1)', -12.25, null],
          ]),
        ],
      );
      final csv = e.toCsv();
      expect(csv, contains('"Achat; ""spécial""";1234567,50;2026-09-03\r\n'));
      expect(csv, contains("'=SOMME(A1);-12,25;\r\n"));
      expect(csv, contains('Libellé;Montant (EUR);Date\r\n'));
      expect(csv, contains('Période;;2026-10-16'), reason: 'since the beginning');
    });

    test('a summary observer: totals only, and said', () {
      final totals = _statement().where((l) => l.isTotal).toList();
      final e = incomeStatementExport(_summaryObserver, totals, now: now);
      final csv = e.toCsv();
      expect(csv, isNot(contains('Cotisations')));
      expect(csv, isNot(contains('Quête')));
      expect(csv, contains('Votre accès porte sur les totaux'));
      expect(csv, contains('Bénéfice;4500'));
      final j = journalExport(_summaryObserver, const [], now: now);
      expect(j.sections.single.rows, isEmpty);
      expect(j.toCsv(), contains('Le détail des écritures ne vous est pas communiqué'));
      final members = membersExport(_summaryObserver,
          const MembersList(members: [AssociationMember(id: 'm1', fullName: 'Membre n° 01', givenYear: null)]), now: now);
      expect(members.toCsv(), isNot(contains('Donné en')));
      expect(members.toCsv(), contains('Les montants ne vous sont pas communiqués.'));
    });

    test('every report builds: balance sheet, trial balance, journal, ledger, chart, analyses, members', () {
      final b = balanceSheetExport(_farm, const [
        StatementLine(section: 'asset', code: '1000', name: 'Cash on Hand', amount: 40000),
        StatementLine(section: 'total', code: '1', name: 'Total actif', amount: 40000),
        StatementLine(section: 'total', code: '2', name: 'Total passif', amount: 40000),
      ], now: now);
      expect(b.toCsv(), contains('1000;Espèces en caisse;40000'));
      expect(b.toCsv(), contains('Période;2026-10-16'));
      final t = trialBalanceExport(_shop, const [
        TrialBalanceRow(code: '1000', name: 'Cash on Hand', type: 'asset', debit: 5000, credit: 0),
        TrialBalanceRow(code: '4000', name: 'Ventes', type: 'income', debit: 0, credit: 5000),
      ], now: now);
      expect(t.toCsv(), contains(';Total;;5000;5000'));
      final j = journalExport(_assoc, [_entry(1), _entry(2, direction: 'out', amount: 300)], now: now, expensesOnly: true);
      expect(j.sections.single.rows, hasLength(1));
      expect(j.toCsv(), contains('2026-10-03;Quête — n° 2;Sortie;Espèces en caisse;Quête;300;;Le trésorier;'));
      final account = const LedgerAccount(
          id: 'q', code: '4050', name: 'Quête', type: 'income', isActive: true, balance: 7500, entryCount: 3);
      final l = ledgerExport(_assoc, account, [
        LedgerMovement(entryId: 'e', occurredAt: DateTime(2026, 10, 4), label: 'Quête', debit: 0, credit: 7500,
            balance: 7500, reversed: false, recordedBy: 'Le trésorier'),
      ], now: now);
      expect(l.toCsv(), contains(';Total de la période;;0;7500;7500;;'));
      final c = chartExport(_assoc, [account], now: now);
      expect(c.toCsv(), contains('4050;Quête;;;3;7500'));
      final a = analyticsExport(_assoc, AssociationAnalytics(
        full: true,
        admin: false,
        months: [MonthMoney(month: DateTime(2026, 10), income: 19500, expenses: 15000, balance: 4500)],
        income: const [CategoryAmount(accountId: 'q', code: '4050', name: 'Quête', amount: 7500, entries: 3)],
        expenses: const [],
        registered: 12,
        gave: 5,
      ), now: now);
      expect(a.toCsv(), contains('2026-10-01;19500;15000;4500'));
      expect(a.toCsv(), contains('4050;Quête;7500;3'));
      expect(a.toCsv(), isNot(contains('Plus gros donateurs')), reason: 'not an administrator\'s');
    });

    test('English headings when the app is in English', () {
      trCurrent = 'en';
      final e = incomeStatementExport(_assoc, _statement(), from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), now: now);
      final csv = e.toCsv();
      expect(csv, contains('Period;2026-10-01;2026-10-16'));
      expect(csv, contains('Code;Account;Amount (FCFA)'));
      expect(e.periodLabel, 'From 1 October 2026 to 16 October 2026');
    });
  });

  group('« Télécharger »: the PDF', () {
    final now = DateTime(2026, 10, 16, 14, 5);

    test('a PDF with the business, the title, the period, the day made and « Marakaj »', () async {
      final e = incomeStatementExport(_assoc, _statement(), from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), now: now);
      final bytes = await e.toPdf(embedFonts: false, compress: false);
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text, startsWith('%PDF-'));
      // The words as the page draws them, one string each.
      final words = RegExp(r'\[\((.*?)\)\]TJ').allMatches(text).map((m) => m.group(1)).join(' ');
      expect(words, contains('Cercle Horizon'));
      expect(words, contains('Compte de r\u00e9sultat'));
      expect(words, contains('Du 1 octobre 2026 au 16 octobre 2026'));
      expect(words, contains('Marakaj'));
      expect(words, contains('Page 1 sur 1'));
      expect(words, contains('Qu\u00eate'));
      expect(words, contains('Total des recettes'));
      expect(e.periodLabel, 'Du 1 octobre 2026 au 16 octobre 2026');
    });

    testWidgets('with Roboto embedded (every accent, « œ », « — »)', (tester) async {
      final e = journalExport(_assoc, [
        for (var i = 0; i < 80; i++) _entry(i),
      ], from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), now: now);
      final bytes = await tester.runAsync(() => e.toPdf());
      expect(latin1.decode(bytes!.sublist(0, 5)), '%PDF-');
      expect(latin1.decode(bytes, allowInvalid: true), contains('FontFile2'), reason: 'the TrueType font is embedded');
    });
  });

  group('« Télécharger » on each screen', () {
    Future<(Uint8List, String, String)?> pick(WidgetTester tester, String format) async {
      (Uint8List, String, String)? got;
      debugFileOut = (b, n, m) async => got = (b, n, m);
      await tester.tap(find.byKey(const Key('report-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('download-csv')), findsOneWidget);
      await tester.tap(find.byKey(Key('download-$format')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pumpAndSettle();
      return got;
    }

    testWidgets('the income statement: PDF and CSV, for the period on screen', (tester) async {
      await size(tester);
      final books = _Books()..income = _statement();
      await tester.pumpWidget(_app(IncomeStatementScreen(accounting: books, org: _assoc)));
      await tester.pumpAndSettle();
      final csv = await pick(tester, 'csv');
      expect(csv!.$2, endsWith('.csv'));
      expect(csv.$2, startsWith('compte-de-resultat_cercle-horizon_'));
      expect(csv.$3, 'text/csv');
      expect(utf8.decode(csv.$1), contains('4050;Quête;7500'));
      final pdf = await pick(tester, 'pdf');
      expect(pdf!.$3, 'application/pdf');
      expect(latin1.decode(pdf.$1.sublist(0, 5)), '%PDF-');
      expect(find.textContaining('Fichier prêt'), findsOneWidget);
    });

    testWidgets('a summary observer\'s download holds the totals only', (tester) async {
      await size(tester);
      final books = _Books()..income = _statement().where((l) => l.isTotal).toList();
      await tester.pumpWidget(_app(IncomeStatementScreen(accounting: books, org: _summaryObserver)));
      await tester.pumpAndSettle();
      final csv = utf8.decode((await pick(tester, 'csv'))!.$1);
      expect(csv, isNot(contains('Cotisations')));
      expect(csv, contains('Votre accès porte sur les totaux'));
    });

    testWidgets('the journal reads every page of the period first', (tester) async {
      await size(tester);
      final books = _Books()..journalRows = [for (var i = 0; i < 620; i++) _entry(i)];
      await tester.pumpWidget(_app(JournalScreen(accounting: books, org: _assoc)));
      await tester.pumpAndSettle();
      final csv = utf8.decode((await pick(tester, 'csv'))!.$1);
      expect(books.journalCalls, [0, 50, 550]);
      expect('Quête — n° '.allMatches(csv).length, 620);
    });

    testWidgets('balance sheet, trial balance, a ledger, the chart: the menu on each', (tester) async {
      await size(tester);
      final account = const LedgerAccount(
          id: 'q', code: '4050', name: 'Quête', type: 'income', isActive: true, balance: 7500, entryCount: 3);
      final books = _Books()
        ..balance = const [StatementLine(section: 'total', code: '1', name: 'Total actif', amount: 0)]
        ..trial = const [TrialBalanceRow(code: '1000', name: 'Cash on Hand', type: 'asset', debit: 5, credit: 0)]
        ..moves = [
          LedgerMovement(entryId: 'e', occurredAt: DateTime(2026, 10, 4), label: 'Quête', debit: 0, credit: 7500,
              balance: 7500, reversed: false, recordedBy: 'Le trésorier'),
        ]
        ..chart = [account];
      for (final (screen, stem) in [
        (BalanceSheetScreen(accounting: books, org: _farm), 'bilan_ferme-aurore_'),
        (TrialBalanceScreen(accounting: books, org: _shop), 'balance-generale_kiosque-vega_'),
        (AccountLedgerScreen(accounting: books, org: _assoc, account: account), 'grand-livre-4050_cercle-horizon_'),
        (ChartOfAccountsScreen(accounting: books, org: _assoc), 'plan-comptable_cercle-horizon_'),
      ]) {
        await tester.pumpWidget(_app(screen));
        await tester.pumpAndSettle();
        final got = await pick(tester, 'csv');
        expect(got!.$2, startsWith(stem));
      }
    });

    testWidgets('the members: CSV only', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(MembersScreen(api: _MembersApi(), org: _assoc)));
      await tester.pumpAndSettle();
      (Uint8List, String, String)? got;
      debugFileOut = (b, n, m) async => got = (b, n, m);
      await tester.tap(find.byKey(const Key('report-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('download-pdf')), findsNothing);
      await tester.tap(find.byKey(const Key('download-csv')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(utf8.decode(got!.$1), contains('Membre n° 01;+22670000001;Trésorier'));
    });

    testWidgets('320 × 1.3: the menu fits', (tester) async {
      await size(tester, w: 320, h: 640, scale: 1.3);
      await tester.pumpWidget(_app(IncomeStatementScreen(accounting: _Books()..income = _statement(), org: _assoc)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-download')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  screenshots();
}

class _MembersApi implements MembersApi {
  @override
  bool get isConfigured => true;
  @override
  Future<MembersList> listMembers(String orgId, {int? year}) async => MembersList(members: [
        AssociationMember(id: 'm1', fullName: 'Membre n° 01', phone: '+22670000001', note: 'Trésorier',
            joinedOn: DateTime(2024, 3, 10), givenYear: 12000),
        AssociationMember(id: 'm2', fullName: 'Membre n° 02', joinedOn: DateTime(2025, 1, 5), givenYear: 0),
      ], withAmounts: true);
  @override
  Future<String> saveMember(String orgId,
          {String? id, required String name, String? phone, String? note, DateTime? joinedOn, bool allowSamePhone = false}) async =>
      'x';
  @override
  Future<void> removeMember(String orgId, String memberId) async {}
  @override
  Future<List<MemberGift>> memberHistory(String memberId) async => const [];
}

Future<void> realFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6 && !Directory('${dir.path}/material_fonts').existsSync(); i++) {
    dir = dir.parent;
  }
  final fonts = Directory('${dir.path}/material_fonts');
  if (!fonts.existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final f in const ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    final file = File('${fonts.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
  final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
}

/// `B153_SHOTS=<dir>`: Recette's step 1 with types, the add form, the
/// manage list, Dépense's tiles, each report's « Télécharger » menu — FR
/// and EN, 390 × 844 and 320 × 640 at 1.3 — and a PDF and a CSV written
/// to the directory for rendering.
void screenshots() {
  final shots = Platform.environment['B153_SHOTS'];
  group('screenshots', () {
    setUpAll(realFonts);

    Future<void> capture(WidgetTester tester, String name) async {
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
        final img = await ro.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> ps(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 20));
    }

    Widget framed(Widget app) => RepaintBoundary(key: const Key('shot'), child: KeyedSubtree(key: UniqueKey(), child: app));

    testWidgets('all of them', (tester) async {
      Directory(shots!).createSync(recursive: true);
      debugPrint('shots: start');
      final now = DateTime(2026, 10, 16, 14, 5);
      for (final (size, scale, tag) in const [(Size(390, 844), 1.0, '390'), (Size(320, 640), 1.3, '320x1.3')]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final lang in const ['fr', 'en']) {
          trCurrent = lang;
          final light = kajTheme(kajPalette);
          Widget app(Widget home) => framed(_app(home, lang: lang, theme: light));
          final types = [
            ..._chart(),
            _type('t-dime', 'Dîme', 'in', description: 'Le dixième des revenus', code: '4080'),
          ];
          // 1. Recette step 1 with the association's types.
          final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
          final api = _Types(types);
          await tester.pumpWidget(app(IncomeFlow(db: db!, orgId: 'a1', types: api, canEditTypes: true, store: MemoryFlowStore())));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await ps(tester);
          debugPrint('shots: step1 $tag $lang');
          await capture(tester, 'recette_step1_${tag}_$lang');
          await tester.scrollUntilVisible(find.byKey(const Key('income-manage-types')), 200,
              scrollable: find.byType(Scrollable).first);
          await ps(tester);
          await capture(tester, 'recette_step1_end_${tag}_$lang');
          // 2. The add form, a duplicate said.
          await tester.tap(find.byKey(const Key('flow-option-__add_type__')));
          await ps(tester);
          await tester.enterText(find.byKey(const Key('type-name')), 'quête');
          await tester.enterText(find.byKey(const Key('type-description')), 'Le dimanche');
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await ps(tester);
          await capture(tester, 'type_add_duplicate_${tag}_$lang');
          await tester.enterText(find.byKey(const Key('type-name')), 'Loyer de la cour');
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await ps(tester);
          await capture(tester, 'type_add_${tag}_$lang');
          // 3. The manage list.
          await tester.pumpWidget(app(ManageTypesScreen(book: MoneyTypesBook(api: api, db: db), orgId: 'a1', direction: 'in')));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await ps(tester);
          await capture(tester, 'types_manage_${tag}_$lang');
          // 4. Dépense's tiles (a farm).
          await tester.pumpWidget(app(ExpenseFlow(db: db, orgId: 'f1', profile: 'farm', types: api, canEditTypes: true,
              store: MemoryFlowStore())));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await ps(tester);
          await capture(tester, 'depense_step1_${tag}_$lang');
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await db.close();
          });
          // 5. Each report's « Télécharger » menu.
          final account = const LedgerAccount(
              id: 'q', code: '4050', name: 'Quête', type: 'income', isActive: true, balance: 7500, entryCount: 3);
          final books = _Books()
            ..income = _statement()
            ..balance = const [
              StatementLine(section: 'asset', code: '1000', name: 'Cash on Hand', amount: 4500),
              StatementLine(section: 'total', code: '1', name: 'Total actif', amount: 4500),
              StatementLine(section: 'equity', code: '', name: 'Résultat accumulé', amount: 4500),
              StatementLine(section: 'total', code: '2', name: 'Total passif', amount: 4500),
            ]
            ..trial = const [
              TrialBalanceRow(code: '1000', name: 'Cash on Hand', type: 'asset', debit: 19500, credit: 15000),
              TrialBalanceRow(code: '4050', name: 'Quête', type: 'income', debit: 0, credit: 7500),
            ]
            ..journalRows = [for (var i = 0; i < 6; i++) _entry(i)]
            ..moves = [
              LedgerMovement(entryId: 'e', occurredAt: DateTime(2026, 10, 4), label: 'Quête', debit: 0, credit: 7500,
                  balance: 7500, reversed: false, recordedBy: 'Le trésorier'),
            ]
            ..chart = [account];
          for (final (screen, name) in [
            (IncomeStatementScreen(accounting: books, org: _assoc), 'income_statement'),
            (BalanceSheetScreen(accounting: books, org: _assoc), 'balance_sheet'),
            (TrialBalanceScreen(accounting: books, org: _assoc), 'trial_balance'),
            (JournalScreen(accounting: books, org: _assoc), 'journal'),
            (AccountLedgerScreen(accounting: books, org: _assoc, account: account), 'ledger'),
            (ChartOfAccountsScreen(accounting: books, org: _assoc), 'chart'),
            (MembersScreen(api: _MembersApi(), org: _assoc), 'members'),
          ]) {
            await tester.pumpWidget(app(screen));
            await ps(tester);
            await tester.tap(find.byKey(const Key('report-download')));
            await ps(tester);
            await capture(tester, 'download_${name}_${tag}_$lang');
          }
          expect(tester.takeException(), isNull);
          // 6. The files themselves, once per language.
          if (tag == '390') {
            final e = incomeStatementExport(_assoc, _statement(),
                from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), now: now);
            final pdf = await tester.runAsync(() => e.toPdf());
            File('$shots/income_statement_$lang.pdf').writeAsBytesSync(pdf!);
            File('$shots/income_statement_$lang.csv').writeAsBytesSync(e.csvBytes());
            final j = journalExport(_assoc, [for (var i = 0; i < 70; i++) _entry(i, direction: i.isEven ? 'in' : 'out')],
                from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 16), now: now);
            File('$shots/journal_$lang.pdf').writeAsBytesSync((await tester.runAsync(() => j.toPdf()))!);
            File('$shots/journal_$lang.csv').writeAsBytesSync(j.csvBytes());
          }
        }
      }
      trCurrent = 'fr';
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }, skip: shots == null);
}

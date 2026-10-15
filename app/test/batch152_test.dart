import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/association/association_analytics.dart';
import 'package:kaj_app/core/association/books_start.dart';
import 'package:kaj_app/core/association/members.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/reports/models.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/account/compte_screen.dart';
import 'package:kaj_app/features/church/association_analytics_screen.dart';
import 'package:kaj_app/features/church/members/member_form_screen.dart';
import 'package:kaj_app/features/church/members/member_screen.dart';
import 'package:kaj_app/features/church/members/member_words.dart';
import 'package:kaj_app/features/church/members/members_screen.dart';
import 'package:kaj_app/features/church/reports/giving_statement_screen.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/money/income_flow.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Batch 152 (148): an association's « Membres » and « Analyses ».
/// Names: « Membre n° 01 », « Le trésorier », brand-like associations.

const _owner = OrgSummary(
    id: 'a1', name: 'Fondation Espoir', profile: 'association', roles: ['owner']);
const _employee = OrgSummary(
    id: 'a1', name: 'Fondation Espoir', profile: 'association', roles: ['employee']);
const _observer = OrgSummary(
    id: 'a1', name: 'Fondation Espoir', profile: 'association', roles: ['observer'], visibility: 'summary');

final _now = DateTime.now();

AssociationMember _m(String id, String name,
        {String? phone, double? given, MemberDues? dues, String? note, DateTime? joined}) =>
    AssociationMember(
      id: id,
      fullName: name,
      phone: phone,
      note: note,
      joinedOn: joined ?? DateTime(2024, 3, 10),
      createdAt: DateTime(2024, 3, 10),
      givenYear: given,
      dues: dues,
    );

final _late = MemberDues(status: DuesStatus.late, lateSince: DateTime(2026, 8, 1));

List<AssociationMember> _three() => [
      _m('m1', 'Membre n° 01', phone: '+22670000001', given: 12000, note: 'Trésorier',
          dues: const MemberDues(status: DuesStatus.upToDate)),
      _m('m2', 'Membre n° 02', phone: '+22670000002', given: 0, dues: _late),
      _m('m3', 'Membre n° 03', given: 3000, dues: const MemberDues(status: DuesStatus.due)),
    ];

/// The server, in memory.
class _Api implements MembersApi {
  _Api(this.members, {this.offline = false, this.amounts = true, this.ready = true});

  List<AssociationMember> members;
  bool offline;
  bool amounts;
  bool ready;
  final saved = <Map<String, Object?>>[];
  final removed = <String>[];
  List<MemberGift> gifts = const [];
  bool refuseSamePhone = false;

  @override
  bool get isConfigured => true;

  @override
  Future<MembersList> listMembers(String orgId, {int? year}) async {
    if (offline) throw const SocketException('Failed host lookup');
    return MembersList(members: members, withAmounts: amounts, serverReady: ready, readAt: _now);
  }

  @override
  Future<String> saveMember(String orgId,
      {String? id, required String name, String? phone, String? note, DateTime? joinedOn, bool allowSamePhone = false}) async {
    if (offline) throw const SocketException('Network is unreachable');
    if (refuseSamePhone && !allowSamePhone) {
      throw const SamePhoneException('Ce numéro est déjà celui de Membre n° 09.');
    }
    saved.add({'id': id, 'name': name, 'phone': phone, 'note': note, 'allow': allowSamePhone});
    final newId = id ?? 'n${saved.length}';
    members = [...members.where((m) => m.id != newId), _m(newId, name, phone: phone, note: note)];
    return newId;
  }

  @override
  Future<void> removeMember(String orgId, String memberId) async {
    removed.add(memberId);
    members = members.where((m) => m.id != memberId).toList();
  }

  @override
  Future<List<MemberGift>> memberHistory(String memberId) async => gifts;
}

/// The app's repository with its server replaced (IncomeFlow and the
/// giving statement take the concrete one).
class _Reports extends ReportsRepository {
  _Reports(this.api) : super(null);
  final _Api api;
  @override
  bool get isConfigured => true;
  @override
  Future<MembersList> listMembers(String orgId, {int? year}) => api.listMembers(orgId, year: year);
  @override
  Future<String> saveMember(String orgId,
          {String? id, required String name, String? phone, String? note, DateTime? joinedOn, bool allowSamePhone = false}) =>
      api.saveMember(orgId, id: id, name: name, phone: phone, note: note, joinedOn: joinedOn, allowSamePhone: allowSamePhone);
  @override
  Future<List<ChurchMember>> members(String orgId) async =>
      [for (final m in api.members) m.asChurchMember];
  @override
  Future<BooksStart?> booksStart(String orgId) async => null;
}

Widget _app(Widget home, {String lang = 'fr', ThemeData? theme}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      theme: theme,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

AssociationAnalytics _analytics({bool full = true, bool admin = true}) {
  final m0 = DateTime(_now.year, _now.month - 11, 1);
  return AssociationAnalytics(
    full: full,
    admin: admin,
    months: [
      for (var i = 0; i < 12; i++)
        MonthMoney(
          month: DateTime(m0.year, m0.month + i, 1),
          income: 20000.0 + i * 5000,
          expenses: 12000.0 + (i % 3) * 4000,
          balance: 50000.0 + i * 8000,
        ),
    ],
    income: full
        ? const [
            CategoryAmount(accountId: 'c1', code: '4040', name: 'Cotisations', amount: 90000, entries: 30),
            CategoryAmount(accountId: 'c2', code: '4030', name: 'Donations', amount: 45000, entries: 12),
            CategoryAmount(accountId: 'c3', code: '4050', name: 'Dîme', amount: 15000, entries: 5),
          ]
        : null,
    expenses: full
        ? const [
            CategoryAmount(accountId: 'e1', code: '5010', name: 'Rent', amount: 60000, entries: 6),
            CategoryAmount(accountId: 'e2', code: '5070', name: 'Fournitures de bureau', amount: 20000, entries: 4),
          ]
        : null,
    registered: 24,
    gave: full ? 18 : null,
    hasDues: true,
    upToDate: full ? 15 : null,
    due: full ? 5 : null,
    late: full ? 4 : null,
    newByMonth: [
      for (var i = 0; i < 12; i++) MonthCount(month: DateTime(m0.year, m0.month + i, 1), count: i % 4),
    ],
    topGivers: full && admin
        ? const [
            Giver(memberId: 'm1', name: 'Membre n° 01', amount: 36000),
            Giver(memberId: 'm4', name: 'Membre n° 04', amount: 24000),
          ]
        : null,
  );
}

/// Amounts are written with narrow no-break spaces (« 12 000 FCFA »).
String _plain(String? s) => (s ?? '').replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
Finder _text(String t) =>
    find.byWidgetPredicate((w) => w is Text && _plain(w.data ?? w.textSpan?.toPlainText()) == t);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  Future<void> size(WidgetTester tester, {double w = 390, double h = 1400, double scale = 1}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  group('who writes the list, and the words', () {
    test('owner and employee write; observer, approver, Mara and a frozen business do not', () {
      expect(canWriteMembers(_owner), isTrue);
      expect(canWriteMembers(_employee), isTrue);
      expect(canWriteMembers(_observer), isFalse);
      expect(canWriteMembers(const OrgSummary(id: 'a', name: 'X', profile: 'association', roles: ['approver'])), isFalse);
      expect(canWriteMembers(const OrgSummary(id: 'a', name: 'X', profile: 'association', roles: ['platform_admin'])), isFalse);
      expect(canWriteMembers(const OrgSummary(id: 'a', name: 'X', profile: 'association', roles: ['owner'], suspended: true)), isFalse);
    });

    test('statuses said in French and English, by the period', () {
      expect(duesLabel('fr', const MemberDues(status: DuesStatus.upToDate), ContributionPeriod.month), 'À jour');
      expect(duesLabel('fr', const MemberDues(status: DuesStatus.due), ContributionPeriod.month), 'À payer ce mois-ci');
      expect(duesLabel('fr', _late, ContributionPeriod.month), 'En retard depuis août 2026');
      expect(duesLabel('en', _late, ContributionPeriod.month), 'Late since August 2026');
      expect(duesLabel('fr', MemberDues(status: DuesStatus.late, lateSince: DateTime(2025, 1, 1)), ContributionPeriod.year),
          'En retard depuis 2025');
      expect(duesLabel('en', const MemberDues(status: DuesStatus.due), ContributionPeriod.week), 'Due this week');
    });

    test('the WhatsApp reminder: polite when late, a greeting otherwise, digits only in wa.me', () {
      const usual = ContributionDefault(amount: 1000, period: ContributionPeriod.month);
      final late = _three()[1];
      final fr = whatsappMessage('fr', member: late, orgName: 'Fondation Espoir', usual: usual);
      expect(fr, startsWith('Bonjour Membre n° 02, ici Fondation Espoir.'));
      expect(fr, contains('Petit rappel amical'));
      expect(_plain(fr), contains('1 000 FCFA par mois'));
      expect(fr, contains('août 2026'));
      final en = whatsappMessage('en', member: late, orgName: 'Fondation Espoir', usual: usual);
      expect(en, contains('A friendly reminder'));
      expect(_plain(en), contains('1 000 FCFA a month'));
      expect(whatsappMessage('fr', member: _three()[0], orgName: 'Fondation Espoir', usual: usual),
          'Bonjour Membre n° 01, ici Fondation Espoir.');
      final uri = whatsappLink('+226 70 00 00 02', fr);
      expect(uri.toString(), startsWith('https://wa.me/22670000002?text='));
      expect(Uri.decodeComponent(uri.query.substring(5)), fr);
    });

    test('search by name (accents and case aside) or by phone digits', () {
      final m = _three()[0];
      expect(m.matches('membre 01'), isTrue);
      expect(m.matches('TRÉSORIER'), isTrue);
      expect(m.matches('tresorier'), isTrue);
      expect(m.matches('70000001'), isTrue);
      expect(m.matches('02'), isFalse);
      expect(initialsOf('Membre n° 01'), 'MN');
    });

    test('Compte offers the analyses to an association; the cauris screens too', () {
      expect(CompteScreen.toolsFor(_owner, OrgAccess.allEdit, admin: true), contains('analytics'));
      expect(CompteScreen.toolsFor(const OrgSummary(id: 'f', name: 'Ferme Horizon', profile: 'farm', roles: ['owner']),
          OrgAccess.allEdit, admin: true), contains('analytics'));
      expect(CompteScreen.toolsFor(_owner, const OrgAccess.admin(hidden: {'analytics'}), admin: true),
          isNot(contains('analytics')));
      expect(PlanTerms.fits('analytics', 'association'), isTrue);
      expect(PlanTerms.fits('delivery', 'association'), isFalse);
    });
  });

  group('the phone keeps the last list', () {
    test('online it is kept; offline it is read back, said as such; nothing kept: the error', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final api = _Api(_three());
      final book = MembersBook(api, db);
      final online = await book.load('a1');
      expect(online.fromPhone, isFalse);
      api.offline = true;
      final offline = await book.load('a1');
      expect(offline.fromPhone, isTrue);
      expect(offline.members.map((m) => m.fullName), ['Membre n° 01', 'Membre n° 02', 'Membre n° 03']);
      expect(offline.members[1].dues?.status, DuesStatus.late);
      expect(offline.members[0].note, 'Trésorier');
      expect(offline.withAmounts, isTrue);
      await expectLater(book.load('other'), throwsA(isA<SocketException>()));
      // Cleared at sign-out with the person's own prefs.
      await db.clearIdentity();
      expect(await book.cached('a1'), isNull);
    });
  });

  group('« Membres »', () {
    testWidgets('the list: count, search, amounts, statuses; tap opens the member', (tester) async {
      await size(tester);
      final opened = <String>[];
      await tester.pumpWidget(_app(MembersScreen(
        api: _Api(_three()),
        org: _owner,
        openMember: (m, _) async => opened.add(m.id),
      )));
      await tester.pumpAndSettle();
      expect(find.text('3 membres'), findsOneWidget);
      expect(find.text('Membre n° 01'), findsOneWidget);
      expect(_text('12 000 FCFA'), findsOneWidget);
      expect(find.text('À jour'), findsOneWidget);
      expect(find.text('En retard depuis août 2026'), findsOneWidget);
      expect(find.text('À payer ce mois-ci'), findsOneWidget);
      expect(find.text('Membre depuis mars 2024'), findsNWidgets(3));
      expect(find.text('1 à jour · 1 en retard'), findsOneWidget);
      expect(find.byKey(const Key('members-add')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('members-search')), '7000 0002');
      await tester.pump();
      expect(find.text('1 sur 3'), findsOneWidget);
      expect(find.text('Membre n° 01'), findsNothing);
      await tester.tap(find.byKey(const Key('member-row-m2')));
      await tester.pumpAndSettle();
      expect(opened, ['m2']);
    });

    testWidgets('an observer reads, adds nothing; no amounts without them', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(MembersScreen(
        api: _Api([_m('m1', 'Membre n° 01')], amounts: false),
        org: _observer,
      )));
      await tester.pumpAndSettle();
      expect(find.text('1 membre'), findsOneWidget);
      expect(find.byKey(const Key('members-add')), findsNothing);
      expect(find.text('cette année'), findsNothing);
    });

    testWidgets('empty: « Ajouter des membres »; offline: the copy and its date', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(MembersScreen(api: _Api(const []), org: _owner)));
      await tester.pumpAndSettle();
      expect(find.text('Aucun membre pour l\'instant'), findsOneWidget);
      expect(find.byKey(const Key('members-add-first')), findsOneWidget);
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(() => db!.close()));
      final api = _Api(_three());
      await tester.runAsync(() => MembersBook(api, db).load('a1'));
      api.offline = true;
      await tester.pumpWidget(_app(MembersScreen(api: api, org: _owner, db: db, key: UniqueKey())));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('members-offline')), findsOneWidget);
      expect(find.textContaining('Hors connexion : la liste du'), findsOneWidget);
      expect(find.text('3 membres'), findsOneWidget);
    });

    testWidgets('before 148: names and dates, and the words for what comes next', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(MembersScreen(
          api: _Api([_m('m1', 'Membre n° 01')], amounts: false, ready: false), org: _owner)));
      await tester.pumpAndSettle();
      expect(find.textContaining('arrivent avec la prochaine mise à jour'), findsOneWidget);
    });
  });

  group('« Ajouter un membre »', () {
    testWidgets('name required, phone length checked, several in a row', (tester) async {
      await size(tester);
      final api = _Api(_three());
      await tester.pumpWidget(_app(MemberFormScreen(api: api, orgId: 'a1', others: api.members)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-save-another')));
      await tester.pumpAndSettle();
      expect(find.text('Le nom du membre, s\'il vous plaît.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 04');
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('member-phone')), matching: find.byType(TextField)), '7000');
      await tester.tap(find.byKey(const Key('member-save-another')));
      await tester.pumpAndSettle();
      expect(find.textContaining('8 chiffres'), findsOneWidget);
      expect(api.saved, isEmpty);
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('member-phone')), matching: find.byType(TextField)), '70000004');
      await tester.enterText(find.byKey(const Key('member-note')), 'Section jeunes');
      await tester.tap(find.byKey(const Key('member-save-another')));
      await tester.pumpAndSettle();
      expect(api.saved.single, {'id': null, 'name': 'Membre n° 04', 'phone': '+22670000004', 'note': 'Section jeunes', 'allow': false});
      expect(find.text('Membre n° 04 ajouté. Le suivant ?'), findsOneWidget);
      // The form is empty again for the next one.
      expect(tester.widget<TextField>(find.byKey(const Key('member-name'))).controller!.text, '');
      await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 05');
      await tester.tap(find.byKey(const Key('member-save-another')));
      await tester.pumpAndSettle();
      expect(find.text('2 membres ajoutés. Le suivant ?'), findsOneWidget);
    });

    testWidgets('a phone already on the list: said, asked in the app, then allowed', (tester) async {
      await size(tester);
      final api = _Api(_three());
      await tester.pumpWidget(_app(MemberFormScreen(api: api, orgId: 'a1', others: api.members)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 06');
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('member-phone')), matching: find.byType(TextField)), '70000001');
      await tester.pump();
      expect(find.text('Ce numéro est déjà celui de Membre n° 01.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('member-same-cancel')));
      await tester.pumpAndSettle();
      expect(api.saved, isEmpty);
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-same-anyway')));
      await tester.pumpAndSettle();
      expect(api.saved.single['allow'], isTrue);
    });

    testWidgets('the server knows a number the phone did not (MA148): asked too', (tester) async {
      await size(tester);
      final api = _Api(const [])..refuseSamePhone = true;
      await tester.pumpWidget(_app(MemberFormScreen(api: api, orgId: 'a1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 07');
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('member-phone')), matching: find.byType(TextField)), '70000009');
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pumpAndSettle();
      expect(find.text('Ce numéro est déjà celui de Membre n° 09.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('member-same-anyway')));
      await tester.pumpAndSettle();
      expect(api.saved.single['allow'], isTrue);
    });

    testWidgets('no signal: said plainly, what was typed kept', (tester) async {
      await size(tester);
      final api = _Api(const [], offline: true);
      await tester.pumpWidget(_app(MemberFormScreen(api: api, orgId: 'a1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 08');
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Il faut du réseau pour enregistrer un membre'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('member-name'))).controller!.text, 'Membre n° 08');
    });

    testWidgets('before 148 the note is not offered (it would be dropped)', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(MemberFormScreen(api: _Api(const []), orgId: 'a1', notesKept: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member-note')), findsNothing);
    });
  });

  group('one member', () {
    final gifts = [
      MemberGift(entryId: 'e1', date: DateTime(2026, 9, 2), accountName: 'Cotisations', kind: 'cotisation', amount: 1000),
      MemberGift(entryId: 'e2', date: DateTime(2026, 8, 15), accountName: 'Donations', kind: 'don', amount: 5000),
      MemberGift(entryId: 'e3', date: DateTime(2026, 8, 1), accountName: 'Donations', kind: 'don', amount: 9000, reversed: true),
      MemberGift(entryId: 'e4', date: DateTime(2025, 12, 20), accountName: 'Dîme', kind: 'autre', amount: 2500),
    ];

    testWidgets('history, totals by year without the undone, WhatsApp reminder, statement', (tester) async {
      await size(tester);
      final api = _Api(_three())..gifts = gifts;
      final launched = <Uri>[];
      final statements = <String>[];
      await tester.pumpWidget(_app(MemberScreen(
        api: api,
        org: _owner,
        member: _three()[1],
        usual: const ContributionDefault(amount: 1000, period: ContributionPeriod.month),
        launch: (u) async {
          launched.add(u);
          return true;
        },
        openStatement: (m) => statements.add(m.id),
      )));
      await tester.pumpAndSettle();
      expect(find.text('En retard depuis août 2026'), findsOneWidget);
      expect(_plain(tester.widget<Text>(find.byKey(const Key('member-year-2026'))).data), '6 000 FCFA');
      expect(_plain(tester.widget<Text>(find.byKey(const Key('member-year-2025'))).data), '2 500 FCFA');
      expect(find.textContaining('annulé'), findsOneWidget);
      expect(find.text('Dîme'), findsOneWidget);
      expect(find.text('Rappeler sur WhatsApp'), findsOneWidget);
      await tester.tap(find.byKey(const Key('member-whatsapp')));
      await tester.pumpAndSettle();
      expect(launched.single.host, 'wa.me');
      expect(launched.single.path, '/22670000002');
      expect(launched.single.queryParameters['text'], contains('Petit rappel amical'));
      await tester.tap(find.byKey(const Key('member-statement')));
      expect(statements, ['m2']);
    });

    testWidgets('remove: asked in the app, soft, then back', (tester) async {
      await size(tester);
      final api = _Api(_three());
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MemberScreen(api: api, org: _owner, member: _three()[0]))),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-remove')));
      await tester.pumpAndSettle();
      expect(find.textContaining('restent enregistrés à son nom'), findsOneWidget);
      await tester.tap(find.byKey(const Key('member-remove-cancel')));
      await tester.pumpAndSettle();
      expect(api.removed, isEmpty);
      await tester.tap(find.byKey(const Key('member-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-remove-confirm')));
      await tester.pumpAndSettle();
      expect(api.removed, ['m1']);
      expect(find.text('open'), findsOneWidget);
      expect(find.text('Membre n° 01 a été retiré de la liste.'), findsOneWidget);
    });

    testWidgets('an observer: no edit, no remove, no detail of gifts', (tester) async {
      await size(tester);
      await tester.pumpWidget(_app(MemberScreen(api: _Api(_three())..gifts = gifts, org: _observer, member: _three()[0])));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member-edit')), findsNothing);
      expect(find.byKey(const Key('member-remove')), findsNothing);
      expect(find.textContaining('réservé aux responsables'), findsOneWidget);
      expect(find.byKey(const Key('member-year-2026')), findsNothing);
    });
  });

  group('Recette « De qui ? » and the statement', () {
    testWidgets('« Ajouter un membre » inline, then picked', (tester) async {
      await size(tester, h: 1400);
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await db!.close();
          }));
      final api = _Api([_m('m1', 'Membre n° 01')]);
      await tester.pumpWidget(_app(IncomeFlow(
          db: db!, orgId: 'a1', reports: _Reports(api), store: MemoryFlowStore(), canAddMembers: true)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-cotisation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('income-member-m1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('income-add-member')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 02');
      await tester.tap(find.byKey(const Key('member-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('income-member-n1')), findsOneWidget);
      final card = tester.widget<Card>(
          find.ancestor(of: find.byKey(const Key('income-member-n1')), matching: find.byType(Card)));
      expect(card.color, isNotNull, reason: 'the new member is picked');
    });

    testWidgets('no « Ajouter un membre » for an observer', (tester) async {
      await size(tester, h: 1400);
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await db!.close();
          }));
      await tester.pumpWidget(_app(IncomeFlow(
          db: db!, orgId: 'a1', reports: _Reports(_Api(const [])), store: MemoryFlowStore())));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-option-don')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('income-add-member')), findsNothing);
    });

    testWidgets('« Relevé de dons » with nobody: « Ajouter des membres »; one member preselected', (tester) async {
      await size(tester);
      var opened = 0;
      final api = _Api(const []);
      await tester.pumpWidget(_app(GivingStatementScreen(
        reports: _Reports(api),
        orgId: 'a1',
        orgName: 'Fondation Espoir',
        onAddMembers: () async {
          opened++;
          api.members = [_m('m1', 'Membre n° 01')];
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('statement-add-members')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });
  });

  group('« Analyses »', () {
    testWidgets('every section, to scale, a category opens its entries; no overflow at 320 × 1.3', (tester) async {
      for (final (w, scale) in const [(390.0, 1.0), (320.0, 1.3)]) {
        await size(tester, w: w, h: 900, scale: scale);
        final opened = <String>[];
        await tester.pumpWidget(_app(AssociationAnalyticsScreen(
          key: UniqueKey(),
          org: _owner,
          load: (from, to) async => _analytics(),
          openCategory: (c, type, period) => opened.add('${c.name}:$type:${period.name}'),
        )));
        await tester.pumpAndSettle();
        final list = find.byType(Scrollable).first;
        for (final k in const ['aa-months', 'aa-balance', 'aa-income', 'aa-expenses', 'aa-members', 'aa-top']) {
          await tester.scrollUntilVisible(find.byKey(Key(k)), 300, scrollable: list);
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
          expect(tester.takeException(), isNull, reason: '$k at $w × $scale');
        }
        expect(find.text('Membre n° 01'), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const Key('aa-cat-c3')), -300, scrollable: list);
        expect(find.text('Dîme'), findsOneWidget);
        expect(find.text('60 %'), findsOneWidget, reason: '90 000 of 150 000');
        await tester.scrollUntilVisible(find.text('Loyer'), 300, scrollable: list);
        expect(find.text('Loyer'), findsOneWidget, reason: 'the seeded Rent, read in French');
        await tester.scrollUntilVisible(find.byKey(const Key('aa-cat-c3')), -300, scrollable: list);
        await tester.ensureVisible(find.byKey(const Key('aa-cat-c3')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('aa-cat-c3')));
        expect(opened, ['Dîme:income:thisYear']);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the bars are drawn to scale: the axis top is a round number above the largest', (tester) async {
      expect(niceCeiling(75000), 100000);
      expect(niceCeiling(21000), 25000);
      expect(niceCeiling(9), 10);
      expect(niceCeiling(0), 1);
    });

    testWidgets('a summary observer: the totals only, and why', (tester) async {
      await size(tester, h: 3000);
      await tester.pumpWidget(_app(AssociationAnalyticsScreen(
          org: _observer, load: (from, to) async => _analytics(full: false, admin: false))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aa-summary-note')), findsOneWidget);
      expect(find.byKey(const Key('aa-months')), findsOneWidget);
      expect(find.byKey(const Key('aa-income')), findsNothing);
      expect(find.byKey(const Key('aa-top')), findsNothing);
      expect(find.text('Ont donné sur la période'), findsNothing);
    });

    testWidgets('an employee: no top givers; a database before 148: said; the period reloads', (tester) async {
      await size(tester, h: 3000);
      await tester.pumpWidget(_app(AssociationAnalyticsScreen(
          org: _employee, load: (from, to) async => _analytics(admin: false))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aa-top')), findsNothing);
      final asked = <DateTime?>[];
      await tester.pumpWidget(_app(AssociationAnalyticsScreen(key: UniqueKey(), org: _owner, load: (from, to) async {
        asked.add(from);
        return null;
      })));
      await tester.pumpAndSettle();
      expect(find.textContaining('prochaine mise à jour du serveur'), findsOneWidget);
      expect(asked.single, DateTime(_now.year, 1, 1));
    });

    testWidgets('English', (tester) async {
      await size(tester, h: 4200);
      await tester.pumpWidget(_app(AssociationAnalyticsScreen(org: _owner, load: (from, to) async => _analytics()),
          lang: 'en'));
      await tester.pumpAndSettle();
      expect(find.text('Money in and out'), findsOneWidget);
      expect(find.text('Income by category'), findsOneWidget);
      expect(find.text('Top givers'), findsOneWidget);
    });
  });

  screenshots();
}

/// The real Roboto and icons, for screenshots a person can read.
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

/// `B152_SHOTS=<dir>`: the list, a member, a late member and their
/// reminder, the add form, every section of the analyses, Recette's « De
/// qui ? » — FR and EN, 390 × 844 and 320 × 640 at 1.3, light (and the
/// analyses in dark).
void screenshots() {
  final shots = Platform.environment['B152_SHOTS'];
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

    Widget framed(Widget app) => RepaintBoundary(key: const Key('shot'), child: KeyedSubtree(key: UniqueKey(), child: app));

    testWidgets('all of them', (tester) async {
      Directory(shots!).createSync(recursive: true);
      const usual = ContributionDefault(amount: 1000, period: ContributionPeriod.month);
      for (final (size, scale, tag) in const [(Size(390, 844), 1.0, '390'), (Size(320, 640), 1.3, '320x1.3')]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final lang in const ['fr', 'en']) {
          final light = kajTheme(kajPalette);
          Widget app(Widget home, {ThemeData? theme}) => framed(_app(home, lang: lang, theme: theme ?? light));
          final members = [
            ..._three(),
            _m('m4', 'Membre n° 04', phone: '+22670000004', given: 24000,
                dues: const MemberDues(status: DuesStatus.upToDate)),
            _m('m5', 'Le trésorier', phone: '+22670000005', given: 36000, note: 'Trésorier',
                dues: const MemberDues(status: DuesStatus.upToDate)),
          ];
          // 1. The list.
          await tester.pumpWidget(app(MembersScreen(api: _Api(members), org: _owner)));
          await tester.pumpAndSettle();
          await capture(tester, 'members_list_${tag}_$lang');
          // 2. A member.
          final gifts = [
            MemberGift(entryId: 'e1', date: DateTime(2026, 10, 2), accountName: 'Cotisations', kind: 'cotisation', amount: 1000),
            MemberGift(entryId: 'e2', date: DateTime(2026, 9, 3), accountName: 'Cotisations', kind: 'cotisation', amount: 1000),
            MemberGift(entryId: 'e3', date: DateTime(2026, 8, 15), accountName: 'Donations', kind: 'don', amount: 10000),
            MemberGift(entryId: 'e4', date: DateTime(2026, 6, 1), accountName: 'Donations', kind: 'don', amount: 5000, reversed: true),
            MemberGift(entryId: 'e5', date: DateTime(2025, 12, 20), accountName: 'Dîme', kind: 'autre', amount: 2500),
          ];
          await tester.pumpWidget(app(MemberScreen(
              api: _Api(members)..gifts = gifts,
              org: _owner,
              member: _m('m1', 'Membre n° 01',
                  phone: '+22670000001', given: 12000, note: 'Trésorier',
                  dues: MemberDues(status: DuesStatus.upToDate, paidThrough: DateTime(2026, 10, 31))),
              usual: usual,
              openStatement: (_) {})));
          await tester.pumpAndSettle();
          await capture(tester, 'member_page_${tag}_$lang');
          // 3. A late member and their reminder.
          await tester.pumpWidget(app(MemberScreen(
              api: _Api(members)..gifts = [gifts[2]],
              org: _owner,
              member: members[1],
              usual: usual,
              openStatement: (_) {})));
          await tester.pumpAndSettle();
          await capture(tester, 'member_late_${tag}_$lang');
          final message = whatsappMessage(lang, member: members[1], orgName: 'Fondation Espoir', usual: usual);
          await tester.pumpWidget(app(Scaffold(
            appBar: AppBar(title: const Text('WhatsApp')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
                  child: Text(message, style: const TextStyle(color: Colors.black87, fontSize: 15)),
                ),
              ),
            ),
          )));
          await tester.pumpAndSettle();
          await capture(tester, 'member_reminder_${tag}_$lang');
          // 4. The add form, a same phone said, one already added.
          await tester.pumpWidget(app(MemberFormScreen(api: _Api(members), orgId: 'a1', others: members)));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 06');
          await tester.enterText(
              find.descendant(of: find.byKey(const Key('member-phone')), matching: find.byType(TextField)), '70000006');
          await tester.tap(find.byKey(const Key('member-save-another')));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const Key('member-name')), 'Membre n° 07');
          await tester.enterText(
              find.descendant(of: find.byKey(const Key('member-phone')), matching: find.byType(TextField)), '70000002');
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await capture(tester, 'member_add_${tag}_$lang');
          // 5. The analyses, section by section, light; the first in dark.
          for (final dark in const [false, true]) {
            await tester.pumpWidget(app(
                AssociationAnalyticsScreen(org: _owner, load: (f, t) async => _analytics(), openCategory: (_, _, _) {}),
                theme: dark
                    // The app ships light only; its charts follow the scheme
                    // they are given, so a dark one is drawn too.
                    ? ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F7A52), brightness: Brightness.dark))
                    : null));
            await tester.pumpAndSettle();
            final keys = dark ? const ['aa-months'] : const ['aa-months', 'aa-balance', 'aa-income', 'aa-expenses', 'aa-members', 'aa-top'];
            for (final k in keys) {
              if (k == 'aa-months') {
                await capture(tester, 'analyses_months${dark ? '_dark' : ''}_${tag}_$lang');
                continue;
              }
              await tester.scrollUntilVisible(find.byKey(Key(k)), 200, scrollable: find.byType(Scrollable).first);
              await tester.pumpAndSettle();
              await tester.ensureVisible(find.byKey(Key(k)));
              await tester.pumpAndSettle();
              await capture(tester, 'analyses_${k.substring(3)}${dark ? '_dark' : ''}_${tag}_$lang');
            }
          }
          // 6. Recette « De qui ? » with « Ajouter un membre ».
          final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
          await tester.pumpWidget(app(IncomeFlow(
              db: db!, orgId: 'a1', reports: _Reports(_Api(members)), store: MemoryFlowStore(), canAddMembers: true)));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('flow-option-cotisation')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('flow-next')));
          await tester.pumpAndSettle();
          await capture(tester, 'recette_de_qui_${tag}_$lang');
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await db.close();
          });
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }, skip: shots == null);
}

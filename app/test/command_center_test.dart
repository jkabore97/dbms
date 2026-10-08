import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/features/admin/admin_pill.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';
import 'package:kaj_app/features/admin/center/journal_section.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/center/todo_section.dart';
import 'package:kaj_app/features/admin/platform_console_screen.dart';
import 'package:kaj_app/features/auth/org_picker_screen.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mara's command center (104, 105), in the app: the « Admin » pill only
/// for a platform admin, the rail on a computer and the bar on a phone, «
/// À faire » counts that open what acts on them, the one search, several
/// businesses at once, the journal's « Annuler » and Réglages — whose keys
/// are the ones the server test proves are read (no dead switch).
class _Center extends CommandCenterRepository {
  _Center() : super(null);

  PlatformTodo todoAnswer = const PlatformTodo({
    'applications': 2,
    'pro_paid': 1,
    'spots_paid': 0,
    'spots_asked': 0,
    'couriers': 0,
    'orders_stuck': 0,
    'silent_30': 4,
    'plans_ending': 0,
    'unlocks_ending': 1,
    'promos_ending': 0,
    'spots_ending': 0,
    'rules_ending': 0,
    'payouts_failed': 0,
  });
  final calls = <String>[];
  List<JournalEntry> entries = const [];
  Map<String, SettingValue> values = const {};

  @override
  bool get isConfigured => true;

  @override
  Future<PlatformTodo> todo() async => todoAnswer;

  @override
  Future<List<TodoRow>> todoList(String key) async {
    calls.add('list:$key');
    return [
      TodoRow(orgId: 'f1', orgName: 'Ferme du Nord', profile: 'farm', feature: 'analytics',
          gift: true, at: DateTime(2026, 10, 10)),
    ];
  }

  @override
  Future<SearchResults> search(String query) async {
    calls.add('search:$query');
    return const SearchResults(
      businesses: [
        BusinessHit(id: 'b1', name: 'Boutique Awa', profile: 'retail', owner: 'Awa Sanou',
            ownerPhone: '+22670105002'),
      ],
      people: [PersonHit(id: 'p1', name: 'Awa Sanou', email: 'awa@example.com', businesses: 1)],
      orders: [
        OrderHit(id: '1a2b3c4d-0000-0000-0000-000000000000', orgId: 'b1', orgName: 'Boutique Awa',
            customer: 'Cliente', total: 1500),
      ],
    );
  }

  @override
  Future<BulkResult> bulk(String action, List<String> orgIds, Map<String, Object?> args) async {
    calls.add('bulk:$action:${orgIds.join(',')}:$args');
    return const BulkResult(done: 1, actions: ['a1'], failed: [
      (orgId: 's1', name: 'Exemple', error: 'Une vitrine d\'exemple ne reçoit pas de cauris'),
    ]);
  }

  @override
  Future<List<JournalEntry>> journal(
      {String? orgId, int limit = 50, DateTime? before, String? beforeId}) async =>
      before == null ? entries : const [];

  @override
  Future<void> undo(String actionId) async => calls.add('undo:$actionId');

  @override
  Future<Map<String, SettingValue>> settings() async => values;

  @override
  Future<String?> setSetting(String key, Object? value) async {
    calls.add('set:$key=$value');
    return 'act-$key';
  }
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
}

class _Console extends ConsoleRepository {
  _Console() : super(null);

  @override
  bool get isConfigured => true;

  @override
  Future<PlatformOverview> overview() async => const PlatformOverview(total: 3, active: 3);

  @override
  Future<OrgPage> searchOrgs({
    String? query,
    String? profile,
    String status = 'active',
    String? activity,
    String sort = 'activity',
    int limit = 50,
    int offset = 0,
  }) async =>
      const OrgPage(rows: [
        OrgRow(id: 'r1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail',
            currency: 'XOF', memberCount: 2),
        OrgRow(id: 'f1', name: 'Ferme du Nord', slug: 'ferme-du-nord', profile: 'farm',
            currency: 'XOF', memberCount: 2),
        OrgRow(id: 'a1', name: 'Entraide', slug: 'entraide', profile: 'association',
            currency: 'XOF', memberCount: 1),
      ], total: 3);
}

/// The center's shell around [page] at [at], every section a stub page
/// that says its address.
GoRouter _router(_Center center, {required String at, Widget? page, List<String>? opened}) {
  Widget stub(String path) => Scaffold(body: Text('page $path'));
  final paths = <String>{
    Routes.console, Routes.consoleBusinesses, Routes.consoleKinds, Routes.applications,
    Routes.consoleRequestForm, Routes.consoleFeatured, Routes.consoleShowcase,
    Routes.consoleCouriers, Routes.consolePro, Routes.consoleCaurisGifts, Routes.consoleWave,
    Routes.consoleSettlement, Routes.consolePeople, Routes.trainers, Routes.consoleSettings,
    Routes.consoleJournal, Routes.consoleAudit, Routes.platformAnalytics,
  };
  return GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, _, child) =>
            CommandCenterShell(center: center, platformAdmin: true, child: child),
        routes: [
          for (final p in paths)
            GoRoute(
              path: p,
              builder: (_, state) {
                opened?.add(state.uri.toString());
                return p == at && page != null ? page : stub(p);
              },
            ),
          GoRoute(
            path: '${Routes.consoleBusinesses}/:id',
            builder: (_, state) {
              opened?.add(state.uri.toString());
              return stub(state.uri.path);
            },
          ),
        ],
      ),
      GoRoute(path: Routes.directory, builder: (_, _) => stub(Routes.directory)),
    ],
  );
}

Future<void> _size(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('the « Admin » pill', () {
    testWidgets('is drawn for a platform admin and opens the center', (tester) async {
      await _size(tester, 390);
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(appBar: AppBar(actions: const [AdminPill(platformAdmin: true)])),
        ),
        GoRoute(path: Routes.console, builder: (_, _) => const Text('le centre')),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('Admin'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-pill')));
      await tester.pumpAndSettle();
      expect(find.text('le centre'), findsOneWidget);
    });

    testWidgets('is never drawn for anybody else — P1: the homes, the picker, Compte and the street look as before',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: Row(children: [AdminPill(platformAdmin: false), AdminPill()]))));
      expect(find.byKey(const Key('admin-pill')), findsNothing,
          reason: 'no session says platform admin: no pill, no room taken');
      // The picker for an ordinary owner: no pill in its bar.
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: OrgPickerScreen(
          orgs: const [OrgSummary(id: 'o1', name: 'Boutique', profile: 'retail', roles: ['owner'])],
          onSelected: (_) {},
        ),
      ));
      expect(find.byKey(const Key('admin-pill')), findsNothing);
    });

    testWidgets('a business opened from the center offers « Retour au centre admin »', (tester) async {
      final router = GoRouter(initialLocation: Routes.console, routes: [
        GoRoute(
          path: Routes.console,
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => AdminTrail.openBusiness(context, 'o1'),
              child: const Text('ouvrir'),
            ),
          ),
        ),
        GoRoute(
          path: '/o/:id',
          builder: (_, state) => AdminReturnBanner(
              orgId: state.pathParameters['id']!, child: const Scaffold(body: Text('accueil'))),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('accueil'), findsOneWidget);
      expect(find.text('Retour au centre admin'), findsOneWidget);
      await tester.tap(find.text('Retour au centre admin'));
      await tester.pumpAndSettle();
      expect(find.text('ouvrir'), findsOneWidget);
      expect(AdminTrail.opened.value, isNull);
    });
  });

  group('the shell', () {
    testWidgets('a computer: the rail with the ten sections, the search, a section by tap',
        (tester) async {
      await _size(tester, 1280);
      final center = _Center();
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _router(center, at: Routes.console, opened: opened)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('center-rail')), findsOneWidget);
      expect(find.byKey(const Key('center-bar')), findsNothing);
      for (final key in ['todo', 'businesses', 'kinds', 'requests', 'street', 'pro', 'payments',
          'people', 'settings', 'journal']) {
        expect(find.byKey(Key('center-section-$key')), findsOneWidget, reason: key);
      }
      // The badge says what waits: two requests.
      expect(find.descendant(of: find.byKey(const Key('center-section-requests')),
          matching: find.text('2')), findsOneWidget);
      await tester.tap(find.byKey(const Key('center-section-settings')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consoleSettings}'), findsOneWidget);
      // A section of several pages has them as tabs.
      await tester.tap(find.byKey(const Key('center-section-street')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consoleFeatured}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('center-tab-${Routes.consoleShowcase}')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consoleShowcase}'), findsOneWidget);
    });

    testWidgets('a phone: the four most used and « Plus »', (tester) async {
      await _size(tester, 390);
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _router(_Center(), at: Routes.consoleBusinesses)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('center-rail')), findsNothing);
      final bar = tester.widget<NavigationBar>(find.byKey(const Key('center-bar')));
      expect(bar.destinations, hasLength(5));
      expect(bar.selectedIndex, 1, reason: 'Entreprises is the open section');
      await tester.tap(find.text('Plus'));
      await tester.pumpAndSettle();
      for (final key in ['kinds', 'street', 'payments', 'people', 'settings', 'journal']) {
        expect(find.byKey(Key('center-more-$key')), findsOneWidget, reason: key);
      }
      await tester.tap(find.byKey(const Key('center-more-journal')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consoleJournal}'), findsOneWidget);
      expect(tester.widget<NavigationBar>(find.byKey(const Key('center-bar'))).selectedIndex, 4,
          reason: 'a section under Plus lights Plus');
    });

    testWidgets('anybody else at a center address is told so', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: CommandCenterShell(center: _Center(), platformAdmin: false, child: const Text('x'))));
      expect(find.byKey(const Key('center-not-for-you')), findsOneWidget);
      expect(find.text('x'), findsNothing);
    });

    testWidgets('each address lights its own section', (tester) async {
      late List<CenterSection> sections;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        sections = centerSections(context);
        return const SizedBox();
      })));
      String of(String path) => sectionFor(sections, path).key;
      expect(of(Routes.console), 'todo');
      expect(of(Routes.platformAnalytics), 'todo');
      expect(of(Routes.consoleOrg('o1')), 'businesses');
      expect(of(Routes.consoleKinds), 'kinds');
      expect(of(Routes.applications), 'requests');
      expect(of(Routes.consoleRequestForm), 'requests');
      expect(of(Routes.consoleCouriers), 'street');
      expect(of(Routes.consoleSettlement), 'payments',
          reason: 'under /console/livreurs, yet the money is Paiements');
      expect(of(Routes.consoleCaurisGifts), 'pro');
      expect(of(Routes.trainers), 'people');
      expect(of(Routes.consoleAudit), 'journal');
    });
  });

  group('« À faire »', () {
    Future<_Center> pump(WidgetTester tester, List<String> opened) async {
      await _size(tester, 1280);
      final center = _Center();
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _router(center,
              at: Routes.console,
              page: TodoSection(center: center, admin: _Admin()),
              opened: opened)));
      await tester.pumpAndSettle();
      return center;
    }

    testWidgets('counts open what acts on them; nothing waiting is not a button', (tester) async {
      final opened = <String>[];
      await pump(tester, opened);
      expect(find.descendant(of: find.byKey(const Key('todo-applications')), matching: find.text('2')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('todo-applications')));
      await tester.pumpAndSettle();
      expect(opened.last, Routes.applications);
    });

    testWidgets('silent businesses open the list filtered', (tester) async {
      final opened = <String>[];
      await pump(tester, opened);
      await tester.tap(find.byKey(const Key('todo-silent_30')));
      await tester.pumpAndSettle();
      expect(opened.last, '${Routes.consoleBusinesses}?activite=silent30');
    });

    testWidgets('what ends in 7 days lists its businesses, each opening its fiche', (tester) async {
      final opened = <String>[];
      final center = await pump(tester, opened);
      // Zero couriers: drawn, not tappable.
      await tester.tap(find.byKey(const Key('todo-couriers')));
      await tester.pumpAndSettle();
      expect(opened.last, Routes.console);
      await tester.ensureVisible(find.byKey(const Key('todo-unlocks_ending')));
      await tester.tap(find.byKey(const Key('todo-unlocks_ending')));
      await tester.pumpAndSettle();
      expect(center.calls, contains('list:unlocks_ending'));
      expect(find.text('Ferme du Nord'), findsOneWidget);
      expect(find.text('Analyses jusqu\'au 10/10 · offert par Mara'), findsOneWidget);
      await tester.tap(find.text('Ferme du Nord'));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consoleOrg('f1')}'), findsOneWidget);
    });
  });

  group('the one search', () {
    testWidgets('Ctrl+K opens it; a business opens its fiche', (tester) async {
      await _size(tester, 1280);
      final center = _Center();
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _router(center, at: Routes.console, opened: opened)));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('center-search-field')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('center-search-field')), '70 10');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(center.calls, contains('search:70 10'));
      expect(find.text('Boutique Awa'), findsWidgets);
      expect(find.text('Commande 1a2b3c4d · Cliente'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hit-org-b1')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consoleOrg('b1')}'), findsOneWidget);
    });

    testWidgets('a person opens the directory on them; an order opens its sheet', (tester) async {
      await _size(tester, 390);
      final center = _Center();
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _router(center, at: Routes.console, opened: opened)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('center-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('center-search-field')), 'Awa');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hit-order-1a2b3c4d-0000-0000-0000-000000000000')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-sheet')), findsOneWidget);
      expect(find.text('Commande 1a2b3c4d'), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('order-sheet')))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('center-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('center-search-field')), 'Awa');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hit-person-p1')));
      await tester.pumpAndSettle();
      expect(opened.last, '${Routes.consolePeople}?q=awa%40example.com&personne=p1');
    });
  });

  group('several businesses at once', () {
    testWidgets('ticked rows, one act, what was refused said by name', (tester) async {
      await _size(tester, 1280);
      final center = _Center();
      await tester.pumpWidget(MaterialApp(
        home: PlatformConsoleScreen(console: _Console(), admin: _Admin(), center: center),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-bar')), findsNothing);
      await tester.tap(find.byKey(const Key('tick-r1')));
      await tester.tap(find.byKey(const Key('tick-a1')));
      await tester.pumpAndSettle();
      expect(find.text('2 cochée(s)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bulk-cauris')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bulk-points')), '40');
      await tester.tap(find.byKey(const Key('bulk-send')));
      await tester.pumpAndSettle();
      expect(center.calls, ['bulk:cauris:r1,a1:{points: 40}']);
      expect(find.byKey(const Key('bulk-result')), findsOneWidget);
      expect(find.textContaining('Exemple — Une vitrine d\'exemple ne reçoit pas de cauris'),
          findsOneWidget);
      await tester.tap(find.text('Compris'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bulk-bar')), findsNothing, reason: 'the ticks are cleared');
    });

    testWidgets('a message and an archive go the same way', (tester) async {
      await _size(tester, 390);
      final center = _Center();
      await tester.pumpWidget(MaterialApp(
        home: PlatformConsoleScreen(console: _Console(), admin: _Admin(), center: center),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tick-f1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('bulk-message')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-message')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('bulk-message-text')), 'Pensez à vos photos');
      await tester.tap(find.byKey(const Key('bulk-send')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compris'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tick-f1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('bulk-archive')));
      await tester.tap(find.byKey(const Key('bulk-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bulk-send')));
      await tester.pumpAndSettle();
      expect(center.calls, [
        'bulk:message:f1:{message: Pensez à vos photos}',
        'bulk:archive:f1:{}',
      ]);
    });
  });

  group('the journal', () {
    testWidgets('« Annuler » on what can be undone, asked once more; nothing else', (tester) async {
      await _size(tester, 1280);
      final center = _Center()
        ..entries = [
          JournalEntry(id: 'a1', at: DateTime(2026, 10, 7, 14, 30), kind: 'setting',
              summary: 'Réglage pro_price_month : 2500 → 3000', actor: 'Mara',
              before: const {'key': 'pro_price_month', 'value': 2500},
              after: const {'key': 'pro_price_month', 'value': 3000}, undoable: true),
          JournalEntry(id: 'a2', at: DateTime(2026, 10, 7, 14), kind: 'message',
              summary: 'Message à Ferme du Nord : « Bonjour »', actor: 'Mara',
              orgId: 'f1', orgName: 'Ferme du Nord'),
          JournalEntry(id: 'a3', at: DateTime(2026, 10, 6), kind: 'archive',
              summary: 'Entreprise archivée : Entraide', actor: 'Mara',
              undoneAt: DateTime(2026, 10, 6, 9), undoneBy: 'Mara'),
        ];
      await tester.pumpWidget(MaterialApp(home: JournalSection(center: center)));
      await tester.pumpAndSettle();
      final n = NumberFormat.decimalPattern('fr_FR');
      expect(find.text('Prix de Mara Pro, par mois : ${n.format(2500)} → ${n.format(3000)}'),
          findsOneWidget,
          reason: 'a setting is named, its values written as numbers');
      expect(find.byKey(const Key('journal-undo-a1')), findsOneWidget);
      expect(find.byKey(const Key('journal-undo-a2')), findsNothing, reason: 'a message is not unsent');
      expect(find.byKey(const Key('journal-undo-a3')), findsNothing, reason: 'undone already');
      expect(find.textContaining('Annulée par Mara'), findsOneWidget);
      await tester.tap(find.byKey(const Key('journal-undo-a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('journal-undo-confirm')));
      await tester.pumpAndSettle();
      expect(center.calls, ['undo:a1']);
    });
  });

  group('Réglages', () {
    testWidgets('each setting by its name, typed its own way, with « Annuler »', (tester) async {
      await _size(tester, 1280);
      final center = _Center()
        ..values = {
          'pro_price_month': SettingValue(value: 2500, updatedAt: DateTime(2026, 10, 1), changedBy: 'Mara'),
          'wave_checkout': const SettingValue(value: false),
          'path_gates_open': const SettingValue(value: 0),
          'admin_two_step': const SettingValue(value: false),
        };
      await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
      await tester.pumpAndSettle();
      expect(find.text('Prix de Mara Pro, par mois'), findsOneWidget);
      expect(find.text('Changé par Mara le 01/10/2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('setting-pro_price_month')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('setting-field')), '-5');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pumpAndSettle();
      expect(find.text('Un nombre entier, zéro ou plus.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('setting-field')), '3000');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pumpAndSettle();
      // « Annuler » on the line that says it was saved.
      await tester.tap(find.descendant(of: find.byType(SnackBar), matching: find.text('Annuler')));
      await tester.pumpAndSettle();
      expect(center.calls.last, 'undo:act-pro_price_month');
      ScaffoldMessenger.of(tester.element(find.byType(SettingsSection))).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setting-wave_checkout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('setting-path_gates_open')));
      await tester.pumpAndSettle();
      expect(center.calls, [
        'set:pro_price_month=3000',
        'undo:act-pro_price_month',
        'set:wave_checkout=true',
        'set:path_gates_open=1',
      ]);
      // The two-step switch is shown here, changed in Sécurité.
      expect(find.descendant(of: find.byKey(const Key('setting-admin_two_step')),
          matching: find.byType(Switch)), findsNothing);
      expect(find.text('Désactivée — changée dans Compte › Sécurité.'), findsOneWidget);
    });

    test('no dead switch: the app lists exactly the keys the server test proves are read', () {
      final sql = File('../database/tests/test_batch105.sql').readAsStringSync();
      final from = sql.indexOf('v_keys text[] := array[');
      expect(from, isNot(-1));
      final block = sql.substring(from, sql.indexOf('];', from));
      final serverKeys = RegExp(r"'([a-z0-9_]+)'").allMatches(block).map((m) => m.group(1)!).toList();
      final appKeys = [for (final d in platformSettingDefs) d.key];
      expect(appKeys, serverKeys);
      expect(appKeys.toSet(), hasLength(appKeys.length), reason: 'each key once');
    });
  });

  test('the center\'s addresses are pages of the real router, inside its shell', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final router = buildRouter(SessionController(
      db: db,
      auth: AuthRepository(null),
      admin: AdminRepository(null),
      accounting: AccountingRepository(null),
    ));
    for (final path in [
      Routes.console, Routes.consoleBusinesses, Routes.consoleOrg('o1'), Routes.consoleKinds,
      Routes.applications, Routes.consoleRequestForm, Routes.consoleSettings,
      Routes.consoleJournal, Routes.consolePro, Routes.consoleCaurisGifts, Routes.consoleWave,
      Routes.consoleSettlement, Routes.consolePeople, Routes.trainers, Routes.consoleAudit,
      Routes.consoleFeatured, Routes.consoleShowcase, Routes.consoleCouriers,
      Routes.platformAnalytics,
    ]) {
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(match.isEmpty, isFalse, reason: path);
      expect(match.matches.first.route, isA<ShellRoute>(), reason: '$path is in the shell');
    }
  });

  test('every key has a French name of its own', () {
    // A key shown as its database name would be a setting nobody can read.
    final source = File('lib/features/admin/center/settings_section.dart').readAsStringSync();
    for (final d in platformSettingDefs) {
      expect(RegExp("'${d.key}' =>\\s*context\\.tr\\(").hasMatch(source), isTrue, reason: d.key);
    }
  });
}

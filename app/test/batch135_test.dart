import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/admin/center/todo_section.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 135: the platform admin center folded — five places, each one
/// question (Aujourd'hui, Clients, Argent, La rue, Réglages), on the bar
/// and on the rail alike; « VOUS ATTEND » only what is not zero, the most
/// urgent first, the zeros in one green line; Réglages in eight cards
/// with a search in French and English; every old address in its place.
class _Center extends CommandCenterRepository {
  _Center() : super(null);

  PlatformTodo todoAnswer = const PlatformTodo({});
  Map<String, SettingValue> values = const {};
  final calls = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<PlatformTodo> todo() async => todoAnswer;

  @override
  Future<List<TodoRow>> todoList(String key) async {
    calls.add('list:$key');
    return const [];
  }

  @override
  Future<PlatformToday?> today() async => const PlatformToday(
        money: {'pro': 10000, 'spots': 2500, 'delivery_cut': 500},
        growth: {'orders_week': 12, 'orders_last_week': 10, 'businesses': 212, 'new_month': 9},
      );

  @override
  Future<PlatformOverview?> overview() async =>
      const PlatformOverview(active: 212, newThisWeek: 5, pro: 38);

  @override
  Future<Map<String, SettingValue>> settings() async => values;

  @override
  Future<String?> setSetting(String key, Object? value) async {
    calls.add('set:$key=$value');
    return null;
  }
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
}

/// Every address the center has had: the pages of before 135, and its own.
const _oldRoutes = <String>[
  Routes.console, Routes.platformAnalytics, Routes.consoleNotifications,
  Routes.consoleBusinesses, Routes.consoleKinds, Routes.applications, Routes.consoleRequestForm,
  Routes.consoleFeatured, Routes.consoleShowcase, Routes.consoleCouriers, Routes.consolePro,
  Routes.consoleCaurisGifts, Routes.consoleWave, Routes.consoleSettlement, Routes.consolePeople,
  Routes.trainers, Routes.consoleSettings, Routes.consoleJournal, Routes.consoleAudit,
  Routes.consoleReports,
];

GoRouter _router(_Center center, {required String at, Widget? page, List<String>? opened}) {
  Widget stub(String path) => Scaffold(body: Text('page $path'));
  return GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, _, child) =>
            CommandCenterShell(center: center, platformAdmin: true, child: child),
        routes: [
          for (final p in _oldRoutes)
            GoRoute(
              path: p,
              builder: (_, state) {
                opened?.add(state.uri.toString());
                return p == at && page != null ? page : stub(p);
              },
            ),
          GoRoute(
            path: '${Routes.consoleSettings}/:card',
            builder: (_, state) {
              opened?.add(state.uri.toString());
              return SettingsSection(
                  key: ValueKey(state.pathParameters['card']),
                  center: center,
                  card: state.pathParameters['card']);
            },
          ),
          GoRoute(
            path: '${Routes.consoleBusinesses}/:id',
            builder: (_, state) => stub(state.uri.path),
          ),
          GoRoute(
            path: '${Routes.consoleCouriers}/dossier/:id',
            builder: (_, state) => stub(state.uri.path),
          ),
        ],
      ),
      GoRoute(path: Routes.directory, builder: (_, _) => stub(Routes.directory)),
    ],
  );
}

Future<void> _size(WidgetTester tester, double width, [double height = 900]) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _en(Widget home) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('the five places', () {
    testWidgets('a phone: five places on the bar, each a word, no « Plus »', (tester) async {
      await _size(tester, 390, 844);
      final center = _Center()..todoAnswer = const PlatformTodo({'orders_stuck': 2, 'new_7': 5});
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router(center, at: Routes.console)));
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.byKey(const Key('center-bar')));
      expect(bar.destinations, hasLength(5));
      for (final (key, word) in [
        ('today', 'Aujourd\'hui'), ('clients', 'Clients'), ('money', 'Argent'),
        ('street', 'La rue'), ('settings', 'Réglages'),
      ]) {
        expect(find.descendant(of: find.byKey(Key('center-bar-$key')), matching: find.text(word)),
            findsOneWidget, reason: key);
      }
      expect(find.text('Plus'), findsNothing);
      // The badge: the urgent counters only — two stuck orders, not the
      // five new businesses.
      expect(find.descendant(of: find.byKey(const Key('center-bar-today')), matching: find.text('2')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('center-bar-today')), matching: find.text('7')),
          findsNothing);
    });

    testWidgets('the wide rail: the five places with their questions; a place by a tap', (tester) async {
      await _size(tester, 1280, 800);
      final center = _Center()..todoAnswer = const PlatformTodo({'payouts_failed': 1, 'pro_paid': 2});
      await tester.pumpWidget(MaterialApp.router(routerConfig: _router(center, at: Routes.console)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('center-rail')), findsOneWidget);
      expect(find.byKey(const Key('center-bar')), findsNothing);
      for (final (key, question) in [
        ('today', 'Qu\'est-ce qui m\'attend ?'), ('clients', 'Qui sont mes clients ?'),
        ('money', 'Combien ça rapporte ?'), ('street', 'Que voient les clients ?'),
        ('settings', 'Quelles sont les règles ?'),
      ]) {
        expect(find.descendant(of: find.byKey(Key('center-section-$key')), matching: find.text(question)),
            findsOneWidget, reason: key);
      }
      expect(find.descendant(of: find.byKey(const Key('center-section-today')), matching: find.text('3')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('center-section-money')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consolePro}'), findsOneWidget);
      // Argent's dark card: what platform_today counts, never invented.
      expect(find.byKey(const Key('center-money-card')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('center-money-total'))).data,
          contains('13'));
      expect(find.textContaining('38 abonnés Pro'), findsOneWidget);
      for (final route in [Routes.consolePro, Routes.consoleWave, Routes.consoleSettlement,
          Routes.consoleCaurisGifts]) {
        expect(find.byKey(Key('center-tab-$route')), findsOneWidget, reason: route);
      }
    });

    testWidgets('Clients: one field (the one search), the switcher, a tap opens a page', (tester) async {
      await _size(tester, 390, 844);
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: _router(_Center(), at: Routes.consoleBusinesses)));
      await tester.pumpAndSettle();
      for (final route in [Routes.consoleBusinesses, Routes.applications, Routes.consolePeople,
          Routes.consoleCouriers, Routes.trainers]) {
        expect(find.byKey(Key('center-tab-$route')), findsOneWidget, reason: route);
      }
      await tester.tap(find.byKey(const Key('center-tab-${Routes.consolePeople}')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consolePeople}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('center-clients-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('center-search-field')), findsOneWidget);
    });

    testWidgets('La rue: À la une, Exemples, Signalements, and « Voir la rue » leaves', (tester) async {
      await _size(tester, 390, 844);
      await tester.pumpWidget(
          MaterialApp.router(routerConfig: _router(_Center(), at: Routes.consoleFeatured)));
      await tester.pumpAndSettle();
      for (final route in [Routes.consoleFeatured, Routes.consoleShowcase, Routes.consoleReports]) {
        expect(find.byKey(Key('center-tab-$route')), findsOneWidget, reason: route);
      }
      await tester.tap(find.byKey(const Key('center-tab-${Routes.consoleReports}')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consoleReports}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('center-see-street')));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.directory}'), findsOneWidget);
    });
  });

  group('every old address lands in its place and its section', () {
    final expected = <String, (String, String?)>{
      Routes.console: ('today', null),
      Routes.platformAnalytics: ('today', null),
      Routes.consoleNotifications: ('today', null),
      Routes.consoleBusinesses: ('clients', Routes.consoleBusinesses),
      Routes.consoleOrg('o1'): ('clients', Routes.consoleBusinesses),
      Routes.applications: ('clients', Routes.applications),
      Routes.consolePeople: ('clients', Routes.consolePeople),
      Routes.consoleCouriers: ('clients', Routes.consoleCouriers),
      Routes.consoleCourierFile('u1'): ('clients', Routes.consoleCouriers),
      Routes.trainers: ('clients', Routes.trainers),
      Routes.consolePro: ('money', Routes.consolePro),
      Routes.consoleWave: ('money', Routes.consoleWave),
      Routes.consoleSettlement: ('money', Routes.consoleSettlement),
      Routes.consoleCaurisGifts: ('money', Routes.consoleCaurisGifts),
      Routes.consoleFeatured: ('street', Routes.consoleFeatured),
      Routes.consoleShowcase: ('street', Routes.consoleShowcase),
      Routes.consoleReports: ('street', Routes.consoleReports),
      Routes.consoleSettings: ('settings', null),
      Routes.consoleSettingsCard('livraison'): ('settings', null),
      Routes.consoleKinds: ('settings', null),
      Routes.consoleRequestForm: ('settings', null),
      Routes.consoleJournal: ('settings', null),
      Routes.consoleAudit: ('settings', null),
    };

    testWidgets('by the table: place, and the switcher\'s page lit', (tester) async {
      late List<CenterSection> sections;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        sections = centerSections(context);
        return const SizedBox();
      })));
      for (final e in expected.entries) {
        final place = sectionFor(sections, e.key);
        expect(place.key, e.value.$1, reason: e.key);
        if (e.value.$2 != null) {
          expect(pageFor(place, e.key)?.route, e.value.$2, reason: e.key);
          expect(place.tabs, isTrue, reason: e.key);
        }
      }
      // Every page of before is somewhere: a page of a place, or owned.
      for (final r in _oldRoutes) {
        expect(expected.containsKey(r), isTrue, reason: '$r is in the table');
      }
    });

    testWidgets('a page beneath a place says the way back, and back goes there', (tester) async {
      await _size(tester, 390, 844);
      for (final (at, crumb, to) in [
        (Routes.consoleKinds, 'Réglages › Création', Routes.consoleSettingsCard('creation')),
        (Routes.consoleRequestForm, 'Réglages › Création', Routes.consoleSettingsCard('creation')),
        (Routes.consoleJournal, 'Réglages › Sécurité, journal', Routes.consoleSettingsCard('securite')),
        (Routes.consoleAudit, 'Réglages › Sécurité, journal', Routes.consoleSettingsCard('securite')),
        (Routes.platformAnalytics, 'Aujourd\'hui', Routes.console),
      ]) {
        final router = _router(_Center(), at: at);
        await tester.pumpWidget(MaterialApp.router(key: ValueKey(at), routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.descendant(of: find.byKey(const Key('center-crumb')), matching: find.text(crumb)),
            findsOneWidget, reason: at);
        expect(centerParent(at), to, reason: at);
        await tester.tap(find.byKey(const Key('center-crumb')));
        await tester.pumpAndSettle();
        expect(router.state.uri.path, to, reason: at);
      }
    });

    test('the bell still lands: a new account on its fiche in Clients › Personnes (129)', () {
      final n = NotificationRow(
        id: 'n1',
        kind: 'new_user',
        message: '',
        createdAt: DateTime.utc(2026, 10, 13),
        params: const {'user_id': 'u1', 'contact': 'awa@example.com'},
      );
      final to = Uri.parse(notificationTarget(n)!);
      expect(to.path, Routes.consolePeople);
      expect(to.queryParameters['personne'], 'u1');
      for (final kind in ['courier_application', 'org_application', 'spot_paid']) {
        final t = notificationTarget(NotificationRow(
            id: 'n', kind: kind, message: '', createdAt: DateTime.utc(2026, 10, 13)))!;
        expect(_oldRoutes.contains(Uri.parse(t).path), isTrue, reason: kind);
      }
    });
  });

  group('Aujourd\'hui', () {
    test('the urgency order: stuck, reports, Wave, « J\'ai payé », then couriers, new, then the ends', () {
      const t = PlatformTodo({
        'rules_ending': 1, 'new_7': 3, 'couriers': 2, 'pro_paid': 1, 'spots_paid': 1,
        'payouts_failed': 4, 'reports_open': 1, 'orders_stuck': 2, 'silent_30': 6,
        'plans_ending': 0,
      });
      expect(t.waitingOrder, [
        'orders_stuck', 'reports_open', 'payouts_failed', 'pro_paid', 'spots',
        'couriers', 'new_7', 'silent_30', 'rules_ending',
      ]);
      expect(t.urgent, 2 + 1 + 4 + 1 + 1);
      expect(t.zeroKeys, [
        'features_lapsed', 'plans_ending', 'unlocks_ending', 'promos_ending', 'spots_ending',
      ]);
      expect([...t.waitingOrder, ...t.zeroKeys], hasLength(14), reason: 'the fourteen counters');
    });

    testWidgets('only what is not zero, in order; the zeros fold into one green line', (tester) async {
      await _size(tester, 390, 844);
      final center = _Center()
        ..todoAnswer = const PlatformTodo({'new_7': 5, 'orders_stuck': 2, 'couriers': 3, 'pro_paid': 1});
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _router(center,
              at: Routes.console,
              page: TodoSection(center: center, admin: _Admin(), name: 'Jairus Kaboré'))));
      await tester.pumpAndSettle();
      expect(find.text('Bonjour Jairus'), findsOneWidget);
      expect(find.text('VOUS ATTEND · 4'), findsOneWidget);
      final ys = [
        for (final k in ['orders_stuck', 'pro_paid', 'couriers', 'new_7'])
          tester.getTopLeft(find.byKey(Key('todo-$k'))).dy,
      ];
      expect([...ys]..sort(), ys, reason: 'urgent first');
      expect(find.byKey(const Key('todo-reports_open')), findsNothing, reason: 'zero: folded');
      await tester.scrollUntilVisible(find.byKey(const Key('todo-all-good')), 200,
          scrollable: find.descendant(of: find.byType(TodoSection), matching: find.byType(Scrollable)).first);
      expect(find.text('Tout le reste va bien · 10 contrôles à zéro'), findsOneWidget);
      await tester.tap(find.byKey(const Key('todo-all-good')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('todo-reports_open')), findsOneWidget);
      // A line opens the same list sheet as before.
      await tester.ensureVisible(find.byKey(const Key('todo-new_7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('todo-new_7')));
      await tester.pumpAndSettle();
      expect(center.calls, contains('list:new_7'));
    });

    testWidgets('the four numbers say what they count; a tap opens the analyses', (tester) async {
      await _size(tester, 390, 844);
      final center = _Center();
      final opened = <String>[];
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: _router(center,
              at: Routes.console, opened: opened, page: TodoSection(center: center, admin: _Admin()))));
      await tester.pumpAndSettle();
      expect(find.text('Bonjour'), findsOneWidget, reason: 'no name: a plain hello');
      expect(find.descendant(of: find.byKey(const Key('today-new')), matching: find.text('5')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('today-orders')), matching: find.text('12')),
          findsOneWidget);
      expect(find.text('+20 %'), findsOneWidget, reason: 'against the 7 days before');
      expect(find.descendant(of: find.byKey(const Key('today-businesses')), matching: find.text('212')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('today-pro')), matching: find.text('38')),
          findsOneWidget);
      expect(find.text('Rien ne vous attend.'), findsOneWidget);
      expect(find.text('Tout le reste va bien · 14 contrôles à zéro'), findsOneWidget);
      await tester.tap(find.byKey(const Key('today-orders')));
      await tester.pumpAndSettle();
      expect(opened.last, Routes.platformAnalytics);
    });
  });

  group('Réglages', () {
    test('every key Réglages knows is on exactly one card', () {
      final onCards = [
        for (final c in settingCards)
          for (final p in c.parts) ...p.$2,
      ];
      final known = [for (final d in platformSettingDefs) d.key];
      expect(onCards.toSet(), known.toSet(), reason: 'no setting lost, none invented');
      expect(onCards, hasLength(onCards.toSet().length), reason: 'each on one card only');
      expect(settingCards, hasLength(8));
      for (final k in known) {
        expect(settingCardOf(k), isNotNull, reason: k);
      }
    });

    testWidgets('eight cards; a card opens its page under uppercase sub-headings; back to the cards',
        (tester) async {
      await _size(tester, 390, 844);
      final center = _Center()
        ..values = {
          for (final d in platformSettingDefs) d.key: const SettingValue(value: 1),
        };
      final router = _router(center, at: Routes.consoleSettings,
          page: SettingsSection(center: center));
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      for (final c in settingCards) {
        expect(find.byKey(Key('settings-card-${c.key}')), findsOneWidget, reason: c.key);
      }
      await tester.tap(find.byKey(const Key('settings-card-livraison')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, Routes.consoleSettingsCard('livraison'));
      for (final h in ['PRIX', 'DISTANCE', 'LIVREURS', 'DÉLAIS']) {
        await tester.scrollUntilVisible(find.text(h), 200,
            scrollable: find
                .descendant(of: find.byKey(const Key('settings-page-livraison')), matching: find.byType(Scrollable))
                .first);
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.byKey(const Key('setting-courier_licence_required')), findsOneWidget);
      expect(find.byKey(const Key('setting-pro_price_month')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-back')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, Routes.consoleSettings);
      // Création opens the types of business and the creation flow.
      await tester.tap(find.byKey(const Key('settings-card-creation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-link-${Routes.consoleKinds}')));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, Routes.consoleKinds);
    });

    testWidgets('« Chercher un réglage… » finds a setting by its French name, accents or not',
        (tester) async {
      await _size(tester, 390, 844);
      final center = _Center()
        ..values = {for (final d in platformSettingDefs) d.key: const SettingValue(value: 1)};
      await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settings-search')), 'kilometre');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setting-delivery_per_km')), findsOneWidget);
      expect(find.byKey(const Key('setting-pro_price_month')), findsNothing);
      expect(find.byKey(const Key('settings-card-pro')), findsNothing, reason: 'the cards give way');
      // Found, it is changed right there.
      await tester.tap(find.byKey(const Key('setting-delivery_per_km')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('setting-field')), '175');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pumpAndSettle();
      expect(center.calls, ['set:delivery_per_km=175']);
      await tester.enterText(find.byKey(const Key('settings-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-none')), findsOneWidget);
    });

    testWidgets('… and by its English name, on a French screen and an English one', (tester) async {
      await _size(tester, 390, 844);
      final center = _Center()
        ..values = {for (final d in platformSettingDefs) d.key: const SettingValue(value: 1)};
      await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('settings-search')), 'welcome e-mail');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setting-welcome_email_on')), findsOneWidget);

      await tester.pumpWidget(_en(SettingsSection(key: const ValueKey('en'), center: center)));
      await tester.pumpAndSettle();
      expect(find.text('Search a setting…'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('settings-search')), 'livraison');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setting-delivery_base')), findsOneWidget,
          reason: 'the French name, on an English screen');
      await tester.enterText(find.byKey(const Key('settings-search')), 'per kilometre');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setting-delivery_per_km')), findsOneWidget);
    });
  });
}

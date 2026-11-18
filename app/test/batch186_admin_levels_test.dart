import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/two_step.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/features/account/two_step_screen.dart';
import 'package:kaj_app/features/admin/admin_access_sheet.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';

/// 186 in the app: each admin, their sections. The server holds them
/// (database/tests/test_batch186.sql); here: the console shows only the
/// places given, the sheet chooses an admin's sections (only those the
/// chooser holds, never touching an admin of everything), « Administrateurs »
/// lists them with their authenticator, and the code screen says whose
/// account it asks for.
class _Console extends ConsoleRepository {
  _Console() : super(null);

  final calls = <String>[];
  List<PlatformAdminEntry> list = const [
    PlatformAdminEntry(userId: 'me', name: 'Jairus', email: 'j@example.com', me: true, twoStep: true),
    PlatformAdminEntry(userId: 'u2', name: 'Tertius', email: 't@example.com', access: {'clients', 'street'}),
  ];

  @override
  Future<List<PlatformAdminEntry>> admins() async => list;

  @override
  Future<void> setAdminAccess(String userId, {required bool on, Set<String>? sections}) async {
    final s = sections == null ? 'all' : [for (final k in platformSections) if (sections.contains(k)) k].join(',');
    calls.add('set:$userId:$on:$s');
  }

  @override
  Future<void> resetTwoStep(String userId) async => calls.add('reset:$userId');
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);
}

class _Step extends TwoStep {
  _Step() : super(null);

  @override
  Future<String?> verifiedFactorId() async => 'f1';
}

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('the console, the places given', () {
    GoRouter router(Set<String>? sections, String at) => GoRouter(initialLocation: at, routes: [
          ShellRoute(
            builder: (_, _, child) =>
                CommandCenterShell(center: _Center(), platformAdmin: true, sections: sections, child: child),
            routes: [
              for (final p in [Routes.console, Routes.consoleBusinesses, Routes.consolePro, Routes.consoleFeatured, Routes.consoleSettings])
                GoRoute(path: p, builder: (_, _) => Scaffold(body: Text('page $p'))),
            ],
          ),
        ]);

    testWidgets('« Argent » only: one place on the bar; another place\'s page stays out of sight', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router({'money'}, Routes.consoleBusinesses)));
      await tester.pumpAndSettle();
      // one place: no bar to switch between places
      expect(find.byKey(const Key('center-bar')), findsNothing);
      expect(find.text('page ${Routes.consoleBusinesses}'), findsNothing);
      expect(find.text('« Clients » ne vous est pas ouvert.'), findsOneWidget);
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.consolePro}'), findsOneWidget);
    });

    testWidgets('« Administrateurs » alone opens « Réglages »; everything: the five', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router({'admins', 'street'}, Routes.consoleSettings)));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(find.byKey(const Key('center-bar'))).destinations, hasLength(2));
      expect(find.byKey(const Key('center-bar-settings')), findsOneWidget);
      expect(find.byKey(const Key('center-bar-street')), findsOneWidget);
      expect(find.text('page ${Routes.consoleSettings}'), findsOneWidget);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router(null, Routes.console)));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(find.byKey(const Key('center-bar'))).destinations, hasLength(5));
    });
  });

  group('the sheet', () {
    Future<void> open(WidgetTester tester, _Console console, {PlatformAdminEntry? current, Set<String>? mine}) async {
      await _tall(tester);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), navigatorKey: nav, home: const Scaffold()));
      // pushed, as the sheet is: it pops itself when saved
      nav.currentState!.push(MaterialPageRoute<bool>(
        builder: (_) => Scaffold(
          body: AdminAccessSheet(console: console, userId: 'u4', label: 'Tertius', current: current, mine: mine),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('an admin of everything names one for two sections', (tester) async {
      final console = _Console();
      await open(tester, console);
      await tester.tap(find.byKey(const Key('admin-access-on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-access-some')));
      await tester.pumpAndSettle();
      // none ticked: nothing to save
      expect(tester.widget<FilledButton>(find.byKey(const Key('admin-access-save'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('admin-access-street')));
      await tester.tap(find.byKey(const Key('admin-access-clients')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-access-save')));
      await tester.pumpAndSettle();
      expect(console.calls, ['set:u4:true:clients,street']);
    });

    testWidgets('« Tout »; and removing an admin', (tester) async {
      final console = _Console();
      await open(tester, console);
      await tester.tap(find.byKey(const Key('admin-access-on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-access-save')));
      await tester.pumpAndSettle();
      expect(console.calls, ['set:u4:true:all']);

      final again = _Console();
      await open(tester, again, current: const PlatformAdminEntry(userId: 'u4', access: {'money'}));
      await tester.tap(find.byKey(const Key('admin-access-on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-access-save')));
      await tester.pumpAndSettle();
      expect(again.calls, ['set:u4:false:all']);
    });

    testWidgets('an admin of a few sections offers only theirs, and never touches an admin of everything', (tester) async {
      final console = _Console();
      await open(tester, console, mine: {'clients', 'street', 'admins'});
      await tester.tap(find.byKey(const Key('admin-access-on')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-access-everything')), findsNothing);
      for (final s in ['clients', 'street', 'admins']) {
        expect(find.byKey(Key('admin-access-$s')), findsOneWidget, reason: s);
      }
      for (final s in ['today', 'money', 'settings']) {
        expect(find.byKey(Key('admin-access-$s')), findsNothing, reason: s);
      }

      await open(tester, _Console(),
          current: const PlatformAdminEntry(userId: 'u4', twoStep: true), mine: {'clients', 'admins'});
      expect(find.text('Seul un administrateur complet modifie un administrateur complet.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('admin-access-save'))).onPressed, isNull);
      expect(find.byKey(const Key('admin-access-reset-two-step')), findsNothing);
    });

    testWidgets('a lost phone: the authenticator reset, after a word', (tester) async {
      final console = _Console();
      await open(tester, console, current: const PlatformAdminEntry(userId: 'u4', access: {'street'}, twoStep: true));
      await tester.tap(find.byKey(const Key('admin-access-reset-two-step')));
      await tester.pumpAndSettle();
      expect(find.text('Réinitialiser l\'application de Tertius ?'), findsOneWidget);
      await tester.tap(find.text('Réinitialiser'));
      await tester.pumpAndSettle();
      expect(console.calls, ['reset:u4']);
    });
  });

  testWidgets('« Administrateurs »: each with their sections and their authenticator', (tester) async {
    await _tall(tester);
    final console = _Console();
    await tester.pumpWidget(MaterialApp(home: AdminsScreen(console: console)));
    await tester.pumpAndSettle();
    expect(find.text('Jairus (vous)'), findsOneWidget);
    expect(find.text('Tout'), findsOneWidget);
    expect(find.text('Clients · La rue'), findsOneWidget);
    expect(find.text('Application d\'authentification pas encore configurée'), findsOneWidget);
    expect(find.text('Application d\'authentification configurée'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-u2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-access-sheet')), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('admin-access-clients'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('admin-access-money'))).value, isFalse);
  });

  testWidgets('the code screen says whose account it asks for', (tester) async {
    await _tall(tester);
    await tester.pumpWidget(MaterialApp(
      home: TwoStepScreen(
        twoStep: _Step(),
        enrolled: true,
        account: 'Jairus Kabore · j@example.com',
        onPassed: () async {},
        onSignOut: () async {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Code de votre application'), findsOneWidget);
    expect(find.text('Compte : Jairus Kabore · j@example.com'), findsOneWidget);
    expect(find.text('Ce n\'est pas votre compte ? Se déconnecter'), findsOneWidget);
  });
}

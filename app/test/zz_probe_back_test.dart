import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/business_cover.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/features/home/business_frame.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The owner's question (108): « Do I still have this bar when I open
/// articles or commandes or facture or any other feature? » — yes: one
/// frame around every page of the business, the place on screen selected,
/// a tap switches tool, back from a tool returns to the home, a sheet still
/// covers the bar, a deep link lands with its bar. For the shop, the farm
/// and the association alike.
class _Shop extends RetailRepository {
  _Shop(super.client);

  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();

  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async => const [];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];

  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;

  @override
  Future<int> pendingOrders(String orgId) async => 2;
}

const _shop = OrgSummary(
  id: 'org-1',
  name: 'Boutique Awa',
  slug: 'boutique-awa',
  profile: 'retail',
  roles: ['owner'],
  currency: 'XOF',
);
const _farm = OrgSummary(id: 'farm-1', name: 'Ferme Ignace', profile: 'farm', roles: ['owner']);
const _asso = OrgSummary(id: 'asso-1', name: 'Entraide', profile: 'association', roles: ['owner']);

/// A tool's page: its name in its own app bar, and a sheet to open.
Widget _tool(String name) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text('Page $name')),
        body: Center(
          child: FilledButton(
            key: Key('sheet-$name'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const SizedBox(height: 200, child: Center(child: Text('La feuille'))),
            ),
            child: const Text('Ouvrir la feuille'),
          ),
        ),
      ),
    );

/// Whether the page « saisie » holds input not saved (A4).
bool _dirty = false;

GoRouter _router(Widget Function() home, OrgSummary org, {String? at}) {
  final cover = BusinessCover();
  return GoRouter(
      initialLocation: at ?? '/o/${org.id}',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('La rue'))),
        ShellRoute(
          observers: [cover],
          builder: (context, state, child) =>
              BusinessFrame(org: org, location: state.uri.path, cover: cover, child: child),
          routes: [
            GoRoute(
              path: '/o/:orgId',
              builder: (_, _) => BusinessPage(child: home()),
              routes: [
                for (final r in const [
                  'produits', 'commandes', 'factures', 'compte', 'administration', 'equipe',
                  'stock', 'bandes', 'a-vendre', 'services', 'chemin', 'credits', 'production',
                  'photos', 'journal', 'rapports', 'notifications',
                ])
                  GoRoute(
                    path: r,
                    builder: (_, _) => BusinessPage(child: _tool(r)),
                    routes: [
                      GoRoute(path: ':id', builder: (_, s) => BusinessPage(child: _tool('$r ${s.pathParameters['id']}'))),
                    ],
                  ),
                GoRoute(path: 'probe', builder: (_, _) => BusinessPage(child: _probe())),
                // A page with input (a new invoice, a rubrique of the
                // settings): unsaved while [_dirty].
                GoRoute(
                  path: 'saisie',
                  builder: (_, _) =>
                      BusinessPage(child: UnsavedInput(isDirty: () => _dirty, child: _tool('saisie'))),
                ),
              ],
            ),
          ],
        ),
      ],
    );
}

Widget _app(GoRouter router) => MaterialApp.router(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      routerConfig: router,
    );

Future<void> _size(WidgetTester tester, double width, [double height = 844]) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

List<String> _labels(WidgetTester tester) => tester
    .widgetList<NavigationDestination>(find.byType(NavigationDestination))
    .map((d) => d.label)
    .toList();

String _selected(WidgetTester tester) {
  final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
  return _labels(tester)[bar.selectedIndex];
}


Widget _probe() => Builder(builder: (context) => Scaffold(
  appBar: AppBar(title: const Text('Probe'), actions: [
    PopupMenuButton<int>(key: const Key('menu'), itemBuilder: (_) => const [PopupMenuItem(value: 1, child: Text('Un choix'))]),
  ]),
  body: Column(children: [
    TextButton(key: const Key('dlg'), onPressed: () => showDialog<void>(context: context, builder: (_) => const AlertDialog(content: Text('Le dialogue'))), child: const Text('d')),
    TextButton(key: const Key('sht'), onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox(height: 100, child: Text('La feuille'))), child: const Text('s')),
    TextButton(key: const Key('date'), onPressed: () => showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDate: DateTime(2025)), child: const Text('t')),
    TextButton(key: const Key('snack'), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Le message'), action: SnackBarAction(label: 'Annuler', onPressed: () {}), duration: const Duration(minutes: 1))), child: const Text('n')),
    MenuAnchor(menuChildren: [MenuItemButton(child: const Text('Item ancre'), onPressed: () {})], builder: (c, ctl, _) => TextButton(key: const Key('anchor'), onPressed: ctl.open, child: const Text('a'))),
  ]),
));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  testWidgets('flag probe', (tester) async {
    final calls = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') calls.add(call.arguments);
      return null;
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _size(tester, 390, 1400);
    final router = _router(() => const Scaffold(body: Text('Home')), _shop);
    await tester.pumpWidget(_app(router));
    await _settle(tester);
    print('home: $calls'); calls.clear();
    router.push('/o/org-1/probe');
    await _settle(tester);
    print('tool page: $calls'); calls.clear();
    // open dialog via root from the page context
    showDialog<void>(context: tester.element(find.text('Probe')), builder: (_) => const AlertDialog(content: Text('Le dialogue')));
    await _settle(tester);
    print('dialog open: $calls'); calls.clear();
    Navigator.of(tester.element(find.text('Le dialogue'))).pop();
    await _settle(tester);
    print('dialog closed on tool page: $calls'); calls.clear();
    router.go('/o/org-1');
    await _settle(tester); calls.clear();
    showModalBottomSheet<void>(context: tester.element(find.text('Home')), builder: (c) => const SizedBox(height: 100, child: Text('La feuille')));
    await _settle(tester);
    print('home sheet open: $calls'); calls.clear();
    showDialog<void>(context: tester.element(find.text('La feuille')), builder: (_) => const AlertDialog(content: Text('Le dialogue')));
    await _settle(tester);
    Navigator.of(tester.element(find.text('Le dialogue'))).pop();
    await _settle(tester);
    print('sheet on home, dialog from it closed; sheet=${find.text('La feuille').evaluate().length}: $calls'); calls.clear();
  });

  testWidgets('web probe', (tester) async {
    await _size(tester, 390, 1400);
    final router = _router(() => const Scaffold(body: Text('Home')), _shop);
    await tester.pumpWidget(_app(router));
    await _settle(tester);
    router.push('/o/org-1/probe');
    await _settle(tester);
    await tester.tap(find.byKey(const Key('sht')));
    await _settle(tester);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(const MethodCall('pushRouteInformation', {'location': '/o/org-1', 'state': null})), (_) {});
    await _settle(tester);
    print('web back with sheet: sheet=${find.text('La feuille').evaluate().length} probe=${find.text('Probe').evaluate().length} path=${router.state.uri.path}');
  });
  for (final c in [['dlg','Le dialogue'],['sht','La feuille'],['date','Sélectionner une date'],['snack','Le message'],['menu','Un choix'],['anchor','Item ancre']]) {
    testWidgets('probe ${c[0]}', (tester) async {
      await _size(tester, 390, 1400);
      final router = _router(() => const Scaffold(body: Text('Home')), _shop, at: '/o/org-1/produits');
      // swap the produits page for the probe
      await tester.pumpWidget(_app(router));
      await _settle(tester);
      router.go('/o/org-1');
      await _settle(tester);
      router.push('/o/org-1/probe');
      await _settle(tester);
      await tester.tap(find.byKey(Key(c[0])));
      await _settle(tester);
      print('${c[0]} open: ${find.text(c[1]).evaluate().length} at ${router.state.uri.path}');
      await tester.binding.handlePopRoute();
      await _settle(tester);
      print('${c[0]} after back: shown=${find.text(c[1]).evaluate().length} probe=${find.text('Probe').evaluate().length} path=${router.state.uri.path}');
    });
  }
}

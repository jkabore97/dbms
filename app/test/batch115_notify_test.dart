import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/console/models.dart' show OrgRow;
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/admin/center/bulk_sheet.dart';
import 'package:kaj_app/features/home/home_nav.dart';
import 'package:kaj_app/features/notify/notification_settings_sheet.dart';
import 'package:kaj_app/features/notify/notifications_screen.dart';
import 'package:kaj_app/features/notify/page_bell.dart';
import 'package:kaj_app/features/notify/push_offer.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 115, the app's half of the bell: each bell counts its own list,
/// live, « 9+ » past nine; a list marks read exactly what it showed; the
/// bell on every tool page; the bar's numbers; the switches and the test;
/// Mara's message to the whole team. The server's half is test_batch115.sql.

NotificationRow _row(String id, String kind, {String? org, Map<String, dynamic>? params, bool read = false}) =>
    NotificationRow.fromRow({
      'id': id,
      'kind': kind,
      'message': 'm $id',
      'created_at': '2026-10-08T08:00:00Z',
      'read_at': read ? '2026-10-08T09:00:00Z' : null,
      'org_id': org,
      'params': params,
    });

class _Notify extends NotificationsRepository {
  _Notify({this.rows = const [], this.counted = NotificationCounts.none, this.prefList = const []})
      : super(null);

  List<NotificationRow> rows;
  NotificationCounts counted;
  List<NotificationPref> prefList;
  final marked = <String>[];
  final setPrefs = <String, bool>{};
  final homeAsked = <String>[];
  Map<String, int> home = const {};
  ({int web, int android, bool? webhook})? test = (web: 1, android: 0, webhook: null);
  NotifyScope? listed;

  @override
  bool get isConfigured => true;
  @override
  Future<List<NotificationRow>> inScope(NotifyScope scope, {int limit = 50}) async {
    listed = scope;
    return rows.where(scope.holds).toList();
  }
  @override
  Future<void> markRead(Iterable<String> ids) async => marked.addAll(ids);
  @override
  Future<NotificationCounts> counts() async => counted;
  @override
  Future<Map<String, int>> homeCounts(String orgId) async {
    homeAsked.add(orgId);
    return home;
  }
  @override
  Future<List<NotificationPref>> prefs() async => prefList;
  @override
  Future<void> setPref(String type, bool enabled) async => setPrefs[type] = enabled;
  @override
  Future<({int web, int android, bool? webhook})?> sendTest() async => test;
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      locale: const Locale('fr'),
      home: child,
    );

void main() {
  group('whose list a row is in (115\'s notification_scope)', () {
    test('the server\'s rules, for a database before 115', () {
      expect(_row('1', 'order_accepted', org: 'o1', params: {'to': 'customer'}).scope, 'customer');
      expect(_row('2', 'low_stock', org: 'o1', params: {'to': 'shop'}).scope, 'shop');
      expect(_row('3', 'new_device', params: {'device': 'X'}).scope, 'me');
      expect(_row('4', 'courier_approved', params: {'to': 'courier'}).scope, 'courier');
      expect(_row('5', 'org_application').scope, 'platform');
      expect(_row('6', 'spot_requested').scope, 'platform');
      expect(_row('7', 'order_ready', org: 'o1').scope, 'customer');
      expect(_row('8', 'delivery_available', org: 'o1', params: {'to': 'courier'}).scope, 'courier');
      expect(_row('9', 'test_push', params: {'to': 'me'}).scope, 'me');
    });

    test('a business\'s list holds its own rows and the account\'s, never another business\'s', () {
      const a = NotifyScope.org('a');
      expect(a.holds(_row('1', 'low_stock', org: 'a', params: {'to': 'shop'})), isTrue);
      expect(a.holds(_row('2', 'low_stock', org: 'b', params: {'to': 'shop'})), isFalse);
      expect(a.holds(_row('3', 'order_accepted', org: 'a', params: {'to': 'customer'})), isFalse);
      expect(a.holds(_row('4', 'new_device')), isTrue);
      expect(NotifyScope.customer.holds(_row('5', 'order_accepted', org: 'a', params: {'to': 'customer'})), isTrue);
    });

    test('the counts: each bell its own, with the account\'s', () {
      final c = NotificationCounts.fromJson({
        'orgs': {'a': 3, 'b': 12},
        'customer': 2,
        'courier': 0,
        'platform': 4,
        'me': 1,
      });
      expect(c.of(const NotifyScope.org('a')), 4);
      expect(c.of(const NotifyScope.org('b')), 13);
      expect(c.of(const NotifyScope.org('z')), 1);
      expect(c.of(NotifyScope.customer), 3);
      expect(c.of(NotifyScope.platform), 5);
      final rows = NotificationCounts.fromRows([
        _row('1', 'low_stock', org: 'a', params: {'to': 'shop'}),
        _row('2', 'low_stock', org: 'a', params: {'to': 'shop'}, read: true),
        _row('3', 'order_accepted', org: 'a', params: {'to': 'customer'}),
      ]);
      expect(rows.orgs, {'a': 1});
      expect(rows.customer, 1);
    });
  });

  group('the bell', () {
    testWidgets('a red bubble with its own number, « 9+ » past nine, live', (tester) async {
      final notify = _Notify(counted: NotificationCounts.fromJson({'orgs': {'a': 3, 'b': 12}, 'me': 0}));
      await tester.pumpWidget(_app(Scaffold(
        appBar: AppBar(actions: [
          NotificationBell(notify: notify, scope: const NotifyScope.org('a'), listRoute: '/x'),
          NotificationBell(notify: notify, scope: const NotifyScope.org('b'), listRoute: '/y'),
          NotificationBell(notify: notify, scope: NotifyScope.customer, listRoute: '/z'),
        ]),
      )));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('9+'), findsOneWidget);
      final badges = tester.widgetList<Badge>(find.byKey(const Key('bell-count'))).toList();
      expect(badges[2].isLabelVisible, isFalse);
      // A row arrives (Realtime, the minute, the return to the app): read again.
      notify.counted = NotificationCounts.fromJson({'orgs': {'a': 5}, 'customer': 1, 'me': 0});
      await notify.bell.refresh();
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('9+'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    test('the bubble\'s words', () {
      expect(NotificationBell.label(9), '9');
      expect(NotificationBell.label(10), '9+');
    });
  });

  group('the list', () {
    testWidgets('marks read exactly the unread rows it shows — never another list\'s', (tester) async {
      final notify = _Notify(rows: [
        _row('a1', 'low_stock', org: 'a', params: {'to': 'shop', 'name': 'Savon'}),
        _row('a2', 'member_joined', org: 'a', params: {'to': 'shop'}, read: true),
        _row('b1', 'low_stock', org: 'b', params: {'to': 'shop'}),
        _row('c1', 'order_accepted', org: 'a', params: {'to': 'customer'}),
        _row('me1', 'new_device', params: {'device': 'Tecno'}),
      ]);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => NotificationsScreen(notify: notify, scope: const NotifyScope.org('a'))),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        locale: const Locale('fr'),
      ));
      await tester.pumpAndSettle();
      expect(notify.listed, const NotifyScope.org('a'));
      expect(find.byKey(const Key('notification-a1')), findsOneWidget);
      expect(find.byKey(const Key('notification-me1')), findsOneWidget);
      expect(find.byKey(const Key('notification-b1')), findsNothing);
      expect(find.byKey(const Key('notification-c1')), findsNothing);
      expect(notify.marked, unorderedEquals(['a1', 'me1']));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the bell on every tool page', () {
    test('every page of the business but its home and the list itself', () {
      expect(PageBell.showsOn('o1', '/o/o1'), isFalse);
      expect(PageBell.showsOn('o1', '/o/o1/'), isFalse);
      expect(PageBell.showsOn('o1', '/o/o1/notifications'), isFalse);
      expect(PageBell.showsOn('o1', '/o/o1/produits'), isTrue);
      expect(PageBell.showsOn('o1', '/o/o1/factures/f1'), isTrue);
    });

    testWidgets('at the bar\'s end, the page\'s own actions moved one place left', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final notify = _Notify(counted: NotificationCounts.fromJson({'orgs': {'o1': 2}}));
      const org = OrgSummary(id: 'o1', name: 'Boutique', profile: 'retail');
      await tester.pumpWidget(_app(PageBell(
        org: org,
        notify: notify,
        path: '/o/o1/produits',
        enabled: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('Articles'), actions: [
            IconButton(key: const Key('own-action'), onPressed: () {}, icon: const Icon(Icons.search)),
          ]),
        ),
      )));
      await tester.pump();
      final bell = tester.getRect(find.byKey(const Key('page-bell')));
      final own = tester.getRect(find.byKey(const Key('own-action')));
      // ignore: avoid_print
      print('BELL $bell OWN $own');
      expect(bell.right, greaterThan(own.right));
      expect(bell.overlaps(own), isFalse);
      expect(bell.top, lessThan(kToolbarHeight));
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the bar\'s numbers', () {
    testWidgets('« 9+ » past nine; Plus says what waits under it, added up', (tester) async {
      final nav = HomeNav(
        home: HomeDestination(icon: Icons.home, label: 'Vente', onTap: () {}, route: ''),
        primary: [
          HomeDestination(icon: Icons.sell, label: 'Articles', onTap: () {}, badge: 14, route: 'produits'),
          HomeDestination(icon: Icons.inbox, label: 'Commandes', onTap: () {}, badge: 2, route: 'commandes'),
          HomeDestination(icon: Icons.receipt, label: 'Factures', onTap: () {}, route: 'factures'),
        ],
        more: [
          HomeDestination(icon: Icons.groups, label: 'Équipe', onTap: () {}, badge: 1, route: 'equipe'),
          HomeDestination(icon: Icons.person, label: 'Compte', onTap: () {}, badge: 3, route: 'compte'),
        ],
      );
      late List<HomeDestination> slots;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        slots = nav.slots(context);
        return Scaffold(bottomNavigationBar: nav.bar(context));
      })));
      expect(slots.last.label, 'Plus');
      expect(slots.last.badge, 4);
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    test('read only for the businesses whose bar is on screen', () async {
      final notify = _Notify()..home = {'orders': 2, 'articles': 1};
      final bell = notify.bell;
      bell.watchHome('o1');
      void listener() {}
      bell.addListener(listener);
      await bell.refresh();
      expect(notify.homeAsked.toSet(), {'o1'});
      expect(bell.homeCount('o1', 'orders'), 2);
      expect(bell.homeCount('o2', 'orders'), 0);
      expect(bell.knowsHome('o1'), isTrue);
      bell.removeListener(listener);
      bell.unwatchHome('o1');
      bell.dispose();
    });
  });

  group('« Notifications »: the switches and the test', () {
    testWidgets('only the person\'s audiences; a switch moves; the test says where it went', (tester) async {
      final notify = _Notify(prefList: const [
        NotificationPref(type: 'order_updates', audience: 'customer', label: 'Mes commandes', enabled: true),
        NotificationPref(type: 'courier_idle', audience: 'courier', label: 'Rappel après 7 jours sans livraison', enabled: false),
        NotificationPref(type: 'shop_stock', audience: 'shop', label: 'Stock bas', enabled: true),
      ]);
      await tester.pumpWidget(_app(Scaffold(
        body: NotificationSettingsSheet(notify: notify, audiences: const {'customer'}),
      )));
      for (var i = 0; i < 5; i++) { await tester.pump(const Duration(milliseconds: 100)); }
      // ignore: avoid_print
      print('SPIN ${find.byType(CircularProgressIndicator).evaluate().length} ${find.byType(SwitchListTile).evaluate().length}');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pref-order_updates')), findsOneWidget);
      expect(find.byKey(const Key('pref-courier_idle')), findsNothing);
      expect(find.byKey(const Key('pref-shop_stock')), findsNothing);
      await tester.tap(find.byKey(const Key('pref-order_updates')));
      await tester.pumpAndSettle();
      expect(notify.setPrefs, {'order_updates': false});
      await tester.tap(find.byKey(const Key('notify-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Envoyée à 1 appareil(s)'), findsOneWidget);
      notify.test = null;
      await tester.tap(find.byKey(const Key('notify-test')));
      await tester.pumpAndSettle();
      expect(find.text('Le test arrive avec la prochaine mise à jour du serveur.'), findsOneWidget);
    });

    testWidgets('no push here (the test host): no offer drawn, nothing asked', (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: PushOfferCard(notify: _Notify(), message: 'Soyez prévenu.', doorbell: true),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('push-offer')), findsNothing);
      await tester.pumpWidget(_app(const Scaffold(body: PushOfferCard(notify: null, message: 'x'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('push-offer')), findsNothing);
    });
  });

  group('Mara\'s message', () {
    testWidgets('« Toute l\'équipe » sends the audience; « Responsables » as before', (tester) async {
      final center = _Center();
      Future<void> send(bool team) async {
        await tester.pumpWidget(_app(Scaffold(
          body: BulkSheet(
            action: BulkAction.message,
            orgs: const [
              OrgRow(id: 'r1', name: 'Boutique Awa', slug: 'boutique-awa', profile: 'retail',
                  currency: 'XOF', memberCount: 2),
            ],
            center: center,
          ),
        )));
        await tester.pumpAndSettle();
        if (team) {
          await tester.tap(find.text('Toute l\'équipe'));
          await tester.pumpAndSettle();
          expect(find.text('Il arrive dans la cloche de chaque membre de leur équipe.'), findsOneWidget);
        }
        await tester.enterText(find.byKey(const Key('bulk-message-text')), 'Bonne semaine');
        await tester.tap(find.text('Envoyer').last);
        await tester.pumpAndSettle();
      }

      await send(false);
      expect(center.args.last, {'message': 'Bonne semaine'});
      await tester.pumpWidget(const SizedBox());
      await send(true);
      expect(center.args.last, {'message': 'Bonne semaine', 'audience': 'team'});
    });
  });
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);
  final args = <Map<String, Object?>>[];
  @override
  Future<BulkResult> bulk(String action, List<String> orgIds, Map<String, Object?> a) async {
    args.add(a);
    return const BulkResult(done: 1);
  }
}

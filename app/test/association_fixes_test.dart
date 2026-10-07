import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/features/account/compte_screen.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/cauris/path_card.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/notify/notifications_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The owner, about associations: « Why is Production in association »,
/// « Association will also have 2 business locked, only accessible with
/// pro », and « Make sure the notification system covers the user needs »
/// (099). The server half is test_association_fixes.sql.
const _assoc = OrgSummary(
    id: 'a1', name: 'Entraide', profile: 'association', roles: ['owner']);
const _church = OrgSummary(
    id: 'c1', name: 'Église', profile: 'church', roles: ['owner']);
const _shop = OrgSummary(
    id: 's1', name: 'Boutique', profile: 'retail', roles: ['owner']);
const _farm =
    OrgSummary(id: 'f1', name: 'Ferme', profile: 'farm', roles: ['owner']);

NotificationRow _row(String kind, String message,
        {String? org = 'a1', Map<String, dynamic> params = const {}}) =>
    NotificationRow(
      id: 'n-$kind',
      kind: kind,
      message: message,
      createdAt: DateTime.utc(2026, 10, 7, 9),
      orgId: org,
      params: params,
    );

Widget _host(Widget child, {String language = 'en'}) => MaterialApp(
      locale: Locale(language),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: child,
    );

/// A line, as the phone in [language] reads it.
Future<String> _line(WidgetTester tester, NotificationRow n,
    {String language = 'en'}) async {
  late String said;
  await tester.pumpWidget(_host(
    Builder(builder: (context) {
      said = notificationLine(context, n);
      return const SizedBox();
    }),
    language: language,
  ));
  // The money format's narrow and no-break spaces, as plain spaces.
  return said.replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');
}

class _Bell extends NotificationsRepository {
  _Bell(this.rows) : super(null);
  final List<NotificationRow> rows;
  @override
  bool get isConfigured => true;
  @override
  Future<List<NotificationRow>> recent({int limit = 50}) async => rows;
  @override
  Future<void> markAllRead() async {}
}

class _Admin extends AdminRepository {
  _Admin(this.profile) : super(null);
  final String profile;

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
        'id': orgId,
        'name': 'Entraide',
        'slug': 'entraide',
        'profile': profile,
        'default_currency': 'XOF',
      };
  @override
  Future<String?> waveMerchant(String orgId) async => null;
  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];
  @override
  Future<
      ({
        bool enabled,
        String? blurb,
        double? lat,
        double? lng,
        double? deliveryBase,
        double? deliveryPerKm,
      })> storefront(String orgId) async => (
        enabled: true,
        blurb: 'Cours du soir' as String?,
        lat: null as double?,
        lng: null as double?,
        deliveryBase: null as double?,
        deliveryPerKm: null as double?,
      );
  @override
  Future<double?> deliveryReach(String orgId) async => null;
  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;
  @override
  Future<({String? phone, String? address})> orgContact(String orgId) async =>
      (phone: null, address: null);
  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async =>
      const VitrineChecklist(published: 1, withPhoto: 0, minItems: 1);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('an association\'s menus', () {
    test('Compte › Outils: no production, its books, carnet and tontines', () {
      for (final org in [_assoc, _church]) {
        expect(CompteScreen.toolsFor(org, OrgAccess.allEdit, admin: true),
            ['accounting', 'credits', 'tontines'],
            reason: '${org.profile} sees no shop or farm tool');
      }
      expect(CompteScreen.toolsFor(_shop, OrgAccess.allEdit, admin: true),
          ['analytics', 'accounting', 'corrections', 'credits', 'tontines', 'production']);
      expect(CompteScreen.toolsFor(_farm, OrgAccess.allEdit, admin: true),
          ['accounting', 'credits', 'tontines', 'production']);
      // The owner's dial still hides what it hides.
      expect(
          CompteScreen.toolsFor(
              _assoc, const OrgAccess.forTier({'credits': 'hidden'}),
              admin: false),
          ['accounting', 'tontines']);
    });

    test('an association is one, under either name', () {
      expect(_assoc.isAssociation, isTrue);
      expect(_church.isAssociation, isTrue);
      expect(_shop.isAssociation, isFalse);
      expect(_farm.isAssociation, isFalse);
    });

    Future<void> settings(WidgetTester tester, String profile,
        {String? part}) async {
      tester.view.physicalSize = const Size(600, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // A fresh screen each time: the rubrique is read once, at the start.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        home: OrgSettingsScreen(
            admin: _Admin(profile), orgId: 'a1', initialPart: part),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the settings offer an association no delivery; its spots stay',
        (tester) async {
      await settings(tester, 'association');
      expect(find.text('Vos services'), findsOneWidget);
      expect(find.text('Livraison'), findsNothing);
      expect(find.text('Équipe et accès'), findsOneWidget);
      await settings(tester, 'association', part: 'vitrine');
      expect(find.byKey(const Key('vitrine-advanced')), findsOneWidget);
      // The whole-vitrine spot only — and the spots it already asked or
      // paid for, where a « spot approved » bell opens.
      expect(find.byKey(const Key('vitrine-spots')), findsOneWidget);
    });

    testWidgets('a shop keeps its delivery and its spots', (tester) async {
      await settings(tester, 'retail');
      expect(find.text('Livraison'), findsOneWidget);
      await settings(tester, 'retail', part: 'vitrine');
      expect(find.byKey(const Key('vitrine-spots')), findsOneWidget);
    });
  });

  group('a second business, with Pro', () {
    test('org_progress\'s lock reaches the « 2e entreprise » row', () {
      final states = FeatureStates.fromJson({
        'plan': 'free',
        'progress': {
          'gated': false,
          'locks': {
            'invoices': false,
            'production': false,
            'credits': false,
            'second_business': true,
          },
        },
      });
      expect(states.progress.locks('second_business'), isTrue);
      expect(states.progress.locks('credits'), isFalse);
      expect(states.progress.locks('invoices'), isFalse);
    });

    testWidgets('the lock on an association says Mara Pro and opens it',
        (tester) async {
      var opened = false;
      await tester.pumpWidget(_host(
        Scaffold(
          body: PathGateSheet(
            org: _assoc,
            feature: 'second_business',
            // An association is not on Le Chemin: no path to read.
            load: () async => null,
            onPath: () => opened = true,
          ),
        ),
        language: 'fr',
      ));
      await tester.pump();
      expect(find.text('2e entreprise'), findsOneWidget);
      expect(find.text('Se débloque : Mara Pro'), findsOneWidget);
      expect(find.byKey(const Key('path-need')), findsNothing);
      await tester.tap(find.byKey(const Key('path-go')));
      expect(opened, isTrue);
      expect(find.text('Voir Mara Pro'), findsOneWidget);
    });
  });

  group('a tap on the bell opens what it is about', () {
    String? target(NotificationRow n, {bool admin = false, String? profile}) =>
        notificationTarget(n,
            isAdminOf: (_) => admin, profileOf: (_) => profile);

    test('orders and bookings: the shop\'s Commandes, the customer\'s', () {
      expect(target(_row('new_order', '', params: {'to': 'shop', 'booking': true})),
          '/o/a1/commandes');
      expect(target(_row('order_withdrawn', '', params: {'to': 'shop'})),
          '/o/a1/commandes');
      expect(target(_row('delivery_taken', '', params: {'to': 'shop'})),
          '/o/a1/commandes');
      expect(target(_row('order_accepted', '', params: {'to': 'customer', 'booking': true})),
          '/mes-commandes');
      expect(target(_row('order_picked_up', '', params: {'to': 'customer'})),
          '/mes-commandes');
      expect(target(_row('order_courier', '', params: {'to': 'customer'})),
          '/mes-commandes');
      // One kind, two audiences: the facts say whose.
      expect(target(_row('order_delivered', '', params: {'to': 'shop'})),
          '/o/a1/commandes');
      expect(target(_row('order_delivered', '', params: {'to': 'customer'})),
          '/mes-commandes');
      expect(target(_row('delivery_failed', '', params: {'to': 'customer'})),
          '/mes-commandes');
      expect(target(_row('order_paid', '', params: {'to': 'shop'})),
          '/o/a1/commandes');
      // A row from before 099: the person's place in the business decides.
      expect(target(_row('order_delivered', 'Votre commande…'), admin: true),
          '/o/a1/commandes');
      expect(target(_row('order_delivered', 'Votre commande…')), '/mes-commandes');
    });

    test('the courier\'s, the path, the plan, the tools', () {
      expect(target(_row('delivery_cancelled', '', params: {'to': 'courier'})),
          '/livreur');
      expect(target(_row('courier_approved', '', org: null)), '/livreur');
      expect(target(_row('unlock', '', params: {'step': 'invoices'})),
          '/o/a1/chemin');
      expect(target(_row('cauris_board', '')), '/o/a1/classement');
      expect(target(_row('cauris_prize', '')), '/o/a1/chemin');
      expect(target(_row('pro_active', '')), '/o/a1/kaj-pro');
      expect(target(_row('spot_approved', '')),
          '/o/a1/administration/parametres?partie=vitrine');
      expect(target(_row('spot_refused', '')),
          '/o/a1/administration/parametres?partie=vitrine');
      expect(
          target(_row('low_stock', '',
              params: {'name': 'Savon noir', 'product_id': 'p1'})),
          '/o/a1/produits?q=Savon+noir');
      expect(target(_row('low_stock', ''), profile: 'farm'), '/o/a1/a-vendre');
      expect(target(_row('member_joined', '')), '/o/a1/equipe');
      expect(target(_row('debt_settled', '', params: {'customer_id': 'k1'})),
          '/o/a1/credits/k1');
      expect(target(_row('tontine_ready', '', params: {'tontine_id': 't1'})),
          '/o/a1/tontines/t1');
      expect(target(_row('new_device', '', org: null)), '/securite');
      expect(target(_row('org_application', '', org: null)), '/demandes');
      expect(target(_row('spot_paid', '', org: null)), '/console/a-la-une');
      // What the platform typed has nothing behind it.
      expect(target(_row('platform_message', 'Mara : bonjour')), isNull);
      expect(target(_row('something_new', '')), '/o/a1');
    });

    testWidgets('the list opens it, in English', (tester) async {
      final router = GoRouter(
        initialLocation: '/n',
        routes: [
          GoRoute(
            path: '/n',
            builder: (_, _) => NotificationsScreen(
              notify: _Bell([
                _row('new_order', 'Nouvelle demande de Awa : 2 000,00 XOF',
                    params: {
                      'to': 'shop',
                      'booking': true,
                      'name': 'Awa',
                      'total': 2000,
                      'currency': 'XOF',
                      'wave': false,
                      'fee': null,
                    }),
                _row('platform_message', 'Mara : bonne semaine'),
              ]),
            ),
          ),
          GoRoute(
            path: '/o/:id/commandes',
            builder: (_, s) => Text('COMMANDES ${s.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('New request from Awa: 2'), findsOneWidget);
      // The platform's own words, as typed.
      expect(find.text('Mara : bonne semaine'), findsOneWidget);
      expect(
          tester
              .widget<ListTile>(find.byKey(const Key('notification-n-platform_message')))
              .onTap,
          isNull);
      await tester.tap(find.textContaining('New request from Awa'));
      await tester.pumpAndSettle();
      expect(find.text('COMMANDES a1'), findsOneWidget);
    });
  });

  group('the bell in the phone\'s language', () {
    testWidgets('a French phone reads the server\'s words', (tester) async {
      final n = _row('order_picked_up', 'Votre réservation chez Entraide : terminée',
          params: {'to': 'customer', 'booking': true, 'shop': 'Entraide', 'status': 'picked_up'});
      expect(await _line(tester, n, language: 'fr'),
          'Votre réservation chez Entraide : terminée');
      expect(await _line(tester, n), 'Your booking at Entraide: done');
    });

    testWidgets('a row with no facts reads as written', (tester) async {
      expect(await _line(tester, _row('low_stock', 'Stock bas : Savon (3 restant)')),
          'Stock bas : Savon (3 restant)');
    });

    testWidgets('each kind the businesses hear, in English', (tester) async {
      final lines = {
        _row('new_order', '', params: {
          'to': 'shop', 'booking': false, 'name': 'Awa', 'total': 4500,
          'currency': 'XOF', 'wave': true, 'fee': 1000,
        }): 'New order from Awa: 4 500 FCFA (Wave) + delivery 1 000 FCFA',
        _row('order_withdrawn', '', params: {'to': 'shop', 'booking': true, 'name': 'Awa'}):
            'Awa cancelled their request',
        _row('order_refused', '', params: {
          'to': 'customer', 'booking': false, 'shop': 'Boutique', 'status': 'refused',
        }): 'Your order at Boutique: refused',
        _row('order_picked_up', '', params: {
          'to': 'customer', 'booking': false, 'shop': 'Boutique', 'status': 'picked_up',
        }): 'Your order at Boutique: collected',
        _row('low_stock', '', params: {'name': 'Savon', 'quantity': 3}):
            'Low stock: Savon (3 left)',
        _row('member_joined', '', params: {'who': 'Bénévole', 'org': 'Entraide'}):
            'Bénévole joined Entraide',
        _row('debt_settled', '', params: {'customer': 'Awa', 'amount': 5000}):
            'Credit settled: Awa has paid off 5 000 FCFA',
        _row('tontine_ready', '', params: {'name': 'Femmes', 'round': 2}):
            'Tontine Femmes: round 2 is ready to close, everyone has paid',
        _row('delivery_failed', '', params: {'to': 'shop', 'name': 'Awa', 'reason': 'absent'}):
            'Delivery to Awa failed (customer absent): the courier is bringing the order back.',
        _row('order_in_transit', '', params: {'to': 'customer', 'shop': 'Boutique', 'self': true}):
            'Boutique is delivering it: your order is on the way',
        _row('order_paid', '', params: {'to': 'customer', 'shop': 'Boutique', 'wave': false}):
            'Your payment at Boutique is confirmed',
        _row('unlock', '', params: {'step': 'invoices', 'articles': 8, 'photos': 3}):
            'Invoices unlocked: 8 items for sale and 3 with a photo.',
        _row('unlock', '', params: {'step': 'credits', 'orders': 3}):
            'Credit book unlocked: 3 orders completed.',
        _row('pro_active', '', params: {'until': '2026-11-07', 'card': true}):
            'Mara Pro is active, paid by card, until 07/11/2026.',
        _row('cauris_board', '', params: {
          'league': 'retail|Ouagadougou|petites',
          'top': [
            {'rank': 1, 'name': 'Salon Awa', 'score': 40},
            {'rank': 2, 'name': null, 'score': 30},
          ],
          'rank': 2, 'score': 30, 'first': false, 'gap': 11,
        }): '🏆 Shops · Ouagadougou · small: 1. Salon Awa 40 · 2. a shop 30. '
            'You are 2nd: 11 more cauris for the place ahead.',
        _row('cauris_prize', '', params: {
          'league': 'farm|Bobo|grandes', 'rank': 1, 'points': 50, 'spot': true,
        }): '🏆 1st of the week in Farms · Bobo · large! +50 cauris, and your vitrine featured for 7 days.',
        _row('new_device', '', org: null, params: {'device': 'Chrome'}):
            'New sign-in to your account on Chrome. Not you? Open Account › Security and sign out of the other devices.',
      };
      for (final e in lines.entries) {
        expect(await _line(tester, e.key), e.value, reason: e.key.kind);
      }
    });
  });
}

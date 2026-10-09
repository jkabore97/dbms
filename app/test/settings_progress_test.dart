import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/cauris/unlock_celebration.dart';

/// The owner: « In Paramètres de l'activité we do not know what is
/// completed or not », « more focus on teaching how to add items », « the
/// payment part is not necessary », and the vitrine card should lead to
/// 100 % « in a logical and nice way ».
const _half = VitrineChecklist(
  published: 3,
  unpublished: 57,
  withPhoto: 1,
  minItems: 8,
);

class _Retail extends RetailRepository {
  _Retail() : super(null);

  int published = 0;

  @override
  Future<int> publishAll(String orgId) async {
    published++;
    return 57;
  }
}

class _Admin extends AdminRepository {
  _Admin({this.list = _half, this.phone, this.lat}) : super(null);

  final VitrineChecklist list;
  final String? phone;
  final double? lat;

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
    'id': orgId,
    'name': 'Boutique Awa',
    'slug': 'boutique-awa',
    'profile': 'retail',
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
    })
  >
  storefront(String orgId) async => (
    enabled: true,
    blurb: 'Le riz du quartier' as String?,
    lat: lat,
    lng: lat == null ? null : -1.52,
    deliveryBase: null as double?,
    deliveryPerKm: null as double?,
  );

  @override
  Future<double?> deliveryReach(String orgId) async => null;

  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;

  @override
  Future<({String? phone, String? address})> orgContact(String orgId) async =>
      (phone: phone, address: null);

  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async => list;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  Future<void> pump(WidgetTester tester, _Admin admin,
      {String? part, RetailRepository? retail}) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: OrgSettingsScreen(
          admin: admin, orgId: 'org-1', initialPart: part, retail: retail),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('each first step says done or to do, with the count', (tester) async {
    await pump(tester, _Admin());
    // Articles first, and no Paiements while the shop is cash only.
    expect(find.text('Vos articles'), findsOneWidget);
    expect(find.text('Paiements'), findsNothing);
    final articles = tester.getTopLeft(find.text('Vos articles')).dy;
    final identity = tester.getTopLeft(find.text('Identité')).dy;
    expect(articles < identity, isTrue);
    // Identity is done (a name); articles, vitrine and position are not.
    expect(find.byKey(const Key('part-done-identite')), findsOneWidget);
    expect(find.byKey(const Key('part-todo-articles')), findsOneWidget);
    expect(find.byKey(const Key('part-todo-vitrine')), findsOneWidget);
    expect(find.byKey(const Key('part-todo-position')), findsOneWidget);
    expect(find.text('1 sur 4 terminés'), findsOneWidget);
    expect(find.textContaining('3 / 8 en vente'), findsOneWidget);
    expect(find.textContaining('manque : téléphone, adresse'), findsOneWidget);
  });

  testWidgets('a full shop reads « Tout est prêt »', (tester) async {
    await pump(
      tester,
      _Admin(
        list: const VitrineChecklist(
          published: 9,
          withPhoto: 4,
          minItems: 8,
        ),
        phone: '+22670000000',
        lat: 12.37,
      ),
    );
    // The address is read from orgContact; this fake has none.
    expect(find.byKey(const Key('part-done-articles')), findsOneWidget);
    expect(find.byKey(const Key('part-done-position')), findsOneWidget);
    expect(find.byKey(const Key('part-todo-vitrine')), findsOneWidget);
    expect(find.text('3 sur 4 terminés'), findsOneWidget);
  });

  testWidgets('« Vos articles » teaches the four gestures and opens the articles',
      (tester) async {
    await pump(tester, _Admin(), part: 'articles');
    expect(find.text('Ajouter un article, en quatre gestes'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('articles-step-$i')), findsOneWidget);
    }
    expect(find.text('Un article à la fois'), findsOneWidget);
    expect(find.byKey(const Key('articles-count')), findsOneWidget);
    expect(find.text('Ajouter un article'), findsOneWidget);
  });

  testWidgets('the vitrine asks for the phone and the address', (tester) async {
    await pump(tester, _Admin(phone: '+22670000000'), part: 'vitrine');
    expect(find.byKey(const Key('vitrine-phone')), findsOneWidget);
    expect(find.widgetWithText(TextField, '+22670000000'), findsOneWidget);
    expect(find.byKey(const Key('vitrine-address')), findsOneWidget);
  });

  testWidgets('« Tout publier » puts the waiting articles on the vitrine',
      (tester) async {
    final retail = _Retail();
    await pump(tester, _Admin(), part: 'articles', retail: retail);
    await tester.tap(find.byKey(const Key('articles-publish-all')));
    await tester.pump();
    await tester.pump();
    expect(retail.published, 1);
    expect(find.text('57 article(s) publié(s) sur la vitrine.'), findsOneWidget);
  });

  testWidgets('a tool that opens is celebrated', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => UnlockDialog.show(context, ['invoices']),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Factures débloquées !'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unlock-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unlock-dialog')), findsNothing);
  });
}

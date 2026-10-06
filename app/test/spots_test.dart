import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/format/money.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/featured_screen.dart';
import 'package:kaj_app/features/admin/spots_card.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Spots for sale (071).
///
/// The audit: À la une existed, but only the platform could fill it, by
/// hand; an owner could not ask, pay or see what a spot earned. Each test is
/// one step of buying one: ask, pay, be approved, be seen, be counted.
class _Admin extends AdminRepository {
  _Admin() : super(null);

  final asked = <String>[];
  final claimed = <String>[];
  final decided = <String>[];
  List<Promotion> mine = const [];
  List<PlatformPromotion> queue = const [];

  @override
  Future<SpotTerms> spotTerms() async =>
      const SpotTerms(wave: '+226 70 11 22 33', waveName: 'Mara');

  @override
  Future<String> requestPromotion(String orgId,
      {String? productId, required int days}) async {
    asked.add('${productId ?? 'shop'}:$days');
    mine = [
      Promotion(
          id: 'pm1',
          kind: productId == null ? 'shop' : 'article',
          productId: productId,
          productName: 'Pagne',
          days: days,
          price: 1000,
          status: 'requested'),
    ];
    return 'pm1';
  }

  @override
  Future<void> claimPromotionPaid(String promotionId, {String? note}) async {
    claimed.add(promotionId);
  }

  @override
  Future<List<Promotion>> myPromotions(String orgId) async => mine;

  @override
  Future<List<PlatformPromotion>> platformPromotions() async => queue;

  @override
  Future<void> decidePromotion(String promotionId,
      {required bool approve}) async {
    decided.add('$promotionId:$approve');
    queue = const [];
  }

  @override
  Future<List<FeaturedCandidate>> featuredCandidates() async => const [];
}

class _Retail extends RetailRepository {
  _Retail() : super(null);

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async =>
      const [
        Product(id: 'p1', name: 'Pagne', salePrice: 5000, quantity: 4, isPublished: true),
        Product(id: 'p2', name: 'Caché', salePrice: 900, quantity: 4),
        Product(id: 'p3', name: 'Vide', salePrice: 900, quantity: 0, isPublished: true),
      ];
}

class _Street extends StorefrontRepository {
  _Street() : super(null);

  final seen = <List<String>>[];

  @override
  bool get isConfigured => true;

  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) async =>
      const [
        DirectoryEntry(orgId: 'o1', name: 'Alimentation Yaar', slug: 'yaar', profile: 'retail'),
        DirectoryEntry(orgId: 'o2', name: 'Boutique Awa', slug: 'awa', profile: 'retail'),
      ];

  @override
  Future<List<FeaturedItem>> featured() async => const [
        FeaturedItem(
            id: 'p1',
            name: 'Pagne',
            price: 5000,
            inStock: true,
            shopName: 'Boutique Awa',
            shopSlug: 'awa'),
      ];

  @override
  Future<Set<String>> spotlights() async => {'awa'};

  @override
  Future<void> recordSeen(List<String> productIds) async => seen.add(productIds);

  @override
  Future<Map<String, List<ShopPreview>>> previews(List<String> slugs) async =>
      const {};
}

String _f(num v) => moneyFormat('XOF').format(v);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR');
  });

  group('where a spot is, in the owner\'s words', () {
    final now = DateTime(2026, 10, 5, 12);
    Promotion at(String status, {DateTime? start, DateTime? end}) => Promotion(
        id: 'x', kind: 'article', days: 7, status: status,
        startsAt: start, endsAt: end);

    test('asked, paid, queued, running, over', () {
      expect(at('requested').stateLabel(now), 'En attente de paiement');
      expect(at('paid_claimed').stateLabel(now), 'Paiement en vérification');
      expect(
          at('approved', start: now.add(const Duration(days: 1)),
                  end: now.add(const Duration(days: 8)))
              .stateLabel(now),
          'Programmée');
      expect(
          at('approved', start: now.subtract(const Duration(days: 1)),
                  end: now.add(const Duration(days: 6)))
              .stateLabel(now),
          'En cours');
      expect(
          at('approved', start: now.subtract(const Duration(days: 9)),
                  end: now.subtract(const Duration(days: 2)))
              .stateLabel(now),
          'Terminée');
    });
  });

  testWidgets('an owner asks for a spot, pays by Wave and says so',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = _Admin();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SpotsCard(orgId: 'o1', admin: admin, retail: _Retail()),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Mettre en avant'));
    await tester.pumpAndSettle();

    // Only an article ready for the street is offered, priced.
    expect(find.text('Pagne · ${_f(5000)}'), findsOneWidget);
    expect(find.textContaining('Caché'), findsNothing);
    expect(find.textContaining('Vide'), findsNothing);
    expect(find.text('Prix : ${_f(1000)}'), findsOneWidget);

    await tester.tap(find.text('Continuer vers le paiement'));
    await tester.pumpAndSettle();
    expect(admin.asked, ['p1:7']);
    expect(find.text('+226 70 11 22 33'), findsOneWidget);

    await tester.tap(find.text("J'ai payé"));
    await tester.pumpAndSettle();
    expect(admin.claimed, ['pm1']);
    expect(find.text("Merci, c'est noté."), findsOneWidget);

    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Pagne'), findsOneWidget, reason: 'the card lists it');
    expect(find.text('En attente de paiement'), findsOneWidget);
  });

  testWidgets('the whole shop for 30 days is priced as such; Pro is told '
      'its 7-day article spot is included', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => SpotSheet.open(context,
                orgId: 'o1', admin: _Admin(), retail: _Retail(), isPro: true),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Offert'), findsOneWidget);

    await tester.tap(find.text('La boutique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 jours'));
    await tester.pumpAndSettle();
    expect(find.text('Prix : ${_f(8000)}'), findsOneWidget);
    expect(find.textContaining('Offert'), findsNothing);
  });

  testWidgets('the console validates a paid spot', (tester) async {
    final admin = _Admin()
      ..queue = const [
        PlatformPromotion(
            id: 'pm9',
            orgId: 'o1',
            orgName: 'Boutique Awa',
            kind: 'article',
            productName: 'Pagne',
            days: 7,
            price: 1000,
            status: 'paid_claimed',
            note: 'Wave Awa'),
      ];
    await tester.pumpWidget(MaterialApp(home: FeaturedScreen(admin: admin)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Boutique Awa · Pagne'), findsOneWidget);
    expect(find.textContaining('dit avoir payé'), findsOneWidget);
    await tester.tap(find.text('Valider'));
    await tester.pump();
    await tester.pump();
    expect(admin.decided, ['pm9:true']);
    expect(find.text('Valider'), findsNothing);
  });

  testWidgets('a paid shop leads the street, marked; the strip is counted',
      (tester) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = await tester.runAsync(
        () => LocalDb.open(path: inMemoryDatabasePath));
    addTearDown(() => tester.runAsync(() => db!.close()));
    final street = _Street();
    await tester.pumpWidget(MaterialApp(
      home: DirectoryScreen(
        storefront: street,
        capture: CaptureRepository(null, db: db!),
        session: SessionController(
          db: db,
          auth: AuthRepository(null),
          admin: AdminRepository(null),
          accounting: AccountingRepository(null),
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Sponsorisé'), findsNWidgets(2),
        reason: 'the strip\'s label and the paid shop\'s card');
    final awa = tester.getTopLeft(find.text('Boutique Awa').last);
    final yaar = tester.getTopLeft(find.text('Alimentation Yaar'));
    expect(awa.dy < yaar.dy || awa.dx < yaar.dx, isTrue,
        reason: 'the paid shop comes before the alphabet');
    expect(street.seen, [
      ['p1']
    ]);
  });
}

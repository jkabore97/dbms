import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/cauris/cauris_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/cauris_console_card.dart';
import 'package:kaj_app/features/cauris/cauris_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Cauris (084): the wallet the owner reads, the rules the platform sets,
/// and the vitrine counting a phone, not a reload.
class _Cauris extends CaurisRepository {
  _Cauris() : super(null);
  final referrals = <String>[];
  final ruleEdits = <String>[];
  int milestoneCalls = 0;

  @override
  Future<CaurisWallet?> wallet(String orgId) async => CaurisWallet.fromJson({
        'balance': 260,
        'week': 45,
        'expires_on': '2027-04-06',
        'referral_code': 'elim-shop',
        'referred': referrals.isNotEmpty,
        'history': [
          {'delta': 15, 'reason': 'returning_customer', 'label': 'Un client revenu',
           'at': '2026-10-06T10:00:00Z'},
          {'delta': -10, 'reason': 'shop_cancel', 'label': 'Commande acceptée puis annulée',
           'at': '2026-10-05T10:00:00Z'},
        ],
        'rules': [
          {'key': 'order_done', 'points': 10, 'label': 'Commande terminée'},
          {'key': 'visitor', 'points': 1, 'daily_cap': 30, 'label': 'Un visiteur sur la vitrine'},
        ],
      });

  @override
  Future<void> milestones(String orgId) async => milestoneCalls++;

  @override
  Future<String> setReferral(String orgId, String code) async {
    referrals.add(code);
    return 'Boutique Awa';
  }

  @override
  Future<List<CaurisRule>> rules() async => const [
        CaurisRule(key: 'order_done', points: 10, label: 'Commande terminée'),
      ];

  @override
  Future<void> setRule(String key, int points, {int? dailyCap}) async =>
      ruleEdits.add('$key=$points');

  @override
  Future<List<CaurisWatchRow>> watch() async => const [
        CaurisWatchRow(orgId: 'a', orgName: 'Boutique Louche', week: 300,
            balance: 300, orders: 12, topCustomerShare: 0.83),
        CaurisWatchRow(orgId: 'b', orgName: 'Elim Shop', week: 120,
            balance: 400, orders: 9, topCustomerShare: 0.2),
      ];
}

class _Shop extends StorefrontRepository {
  _Shop() : super(null);

  final visitors = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<PublicShop?> shop(String slug) async => const PublicShop(
      orgId: 'o1', name: 'Elim Shop', slug: 'elim-shop', profile: 'retail');

  @override
  Future<List<PublicItem>> items(String slug) async => const [];

  @override
  Future<void> recordVisitor(String slug, String visitorId) async =>
      visitors.add(visitorId);
}

const _org = OrgSummary(
    id: 'o1', name: 'Elim Shop', profile: 'retail', roles: ['owner']);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR');
  });

  testWidgets('the wallet counts up, says the week and how to earn, and '
      'traces every cauri', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cauris = _Cauris();
    await tester.pumpWidget(MaterialApp(home: CaurisScreen(org: _org, cauris: cauris)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('260'), findsOneWidget);
    expect(find.text('Cette semaine : +45'), findsOneWidget);
    expect(cauris.milestoneCalls, 1, reason: 'a complete vitrine is checked on the way in');
    expect(find.text('Commande terminée'), findsOneWidget);
    expect(find.text('jusqu\'à 30 par jour'), findsOneWidget);
    expect(find.text('+15'), findsOneWidget);
    expect(find.text('-10'), findsOneWidget);
    expect(find.textContaining('« elim-shop »'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('referral-code')), 'boutique-awa');
    await tester.tap(find.text('Valider'));
    await tester.pump();
    await tester.pump();
    expect(cauris.referrals, ['boutique-awa']);
    expect(find.textContaining('Boutique Awa est votre parrain'), findsOneWidget);
    expect(find.byKey(const Key('referral-code')), findsNothing,
        reason: 'said once');
  });

  testWidgets('the platform edits a rule and sees the shape of an abuse',
      (tester) async {
    final cauris = _Cauris();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
            child: CaurisConsoleCard(cauris: cauris)))));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('83 % d\'un seul client'), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget,
        reason: 'only the one with most orders from one customer');

    await tester.tap(find.byKey(const Key('rule-order_done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-points')), '12');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(cauris.ruleEdits, ['order_done=12']);
  });

  testWidgets('the vitrine counts this phone as one visitor, the same one '
      'next time', (tester) async {
    final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
    final shop = _Shop();
    Widget screen() => MaterialApp(
          home: StorefrontScreen(
            slug: 'elim-shop',
            storefront: shop,
            capture: CaptureRepository(null, db: db!),
            session: SessionController(
              db: db,
              auth: AuthRepository(null),
              admin: AdminRepository(null),
              accounting: AccountingRepository(null),
            ),
          ),
        );
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(screen());
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
    }
    expect(shop.visitors.length, 2);
    expect(shop.visitors.first.length, greaterThanOrEqualTo(8));
    expect(shop.visitors.toSet().length, 1, reason: 'one phone, one id');
    await tester.runAsync(() => db!.close());
  });
}

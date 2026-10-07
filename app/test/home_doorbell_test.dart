import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/church/church_home_screen.dart';
import 'package:kaj_app/features/farm/farm_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The doorbell on every home (100): a farm's new order and an
/// association's new demande ring on its home as a shop's order always
/// has — the tone chosen in Compte › Préférences, a line with « Voir ».
class _Orders extends RetailRepository {
  _Orders() : super(null);

  int pending = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<int> pendingOrders(String orgId) async => pending;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  Widget app(Widget home) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: home,
      );

  testWidgets('an association\'s new demande rings on its home', (tester) async {
    final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
    addTearDown(() => tester.runAsync(() => db!.close()));
    final orders = _Orders()..pending = 1;
    const org = OrgSummary(
        id: 'a1', name: 'Entraide', profile: 'association', roles: ['owner'], currency: 'XOF');
    await tester.pumpWidget(app(ChurchHomeScreen(
        db: db!, orgId: org.id, orgName: org.name, org: org, retail: orders)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    // What was there when the home opened is not news.
    expect(find.textContaining('Nouvelle demande'), findsNothing);

    orders.pending = 2;
    await tester.pump(const Duration(seconds: 91));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nouvelle demande : 2 à traiter sur la vitrine.'), findsOneWidget);
    expect(find.text('Voir'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  });

  testWidgets('a farm\'s new order rings on its home; a fall is quiet', (tester) async {
    final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
    addTearDown(() => tester.runAsync(() => db!.close()));
    final orders = _Orders();
    const org = OrgSummary(
        id: 'f1', name: 'Ferme du Nord', profile: 'farm', roles: ['owner'], currency: 'XOF');
    await tester.pumpWidget(app(FarmHomeScreen(db: db!, org: org, retail: orders)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    orders.pending = 1;
    await tester.pump(const Duration(seconds: 91));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nouvelle commande : 1 à traiter sur la vitrine.'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(FarmHomeScreen))).clearSnackBars();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    orders.pending = 0;
    await tester.pump(const Duration(seconds: 91));
    await tester.pump();
    expect(find.textContaining('Nouvelle commande'), findsNothing);
    // The home's own reads finish before the database closes.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  });
}

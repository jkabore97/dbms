import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';
import 'package:kaj_app/features/storefront/directory_screen.dart';
import 'package:kaj_app/features/storefront/shop_skeleton.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The page before its content. While the street, a shop or the courier's
/// board is still on its way, the shape of it is already there — no spinner
/// on a blank page — and it gives way to the real thing the moment the
/// answer lands. Held still when the device asked for less motion; one word
/// to a screen reader.
class _SlowStreet extends StorefrontRepository {
  _SlowStreet() : super(null);

  final directoryGate = Completer<List<DirectoryEntry>>();
  final shopGate = Completer<PublicShop?>();

  @override
  bool get isConfigured => true;

  @override
  Future<List<DirectoryEntry>> directory({double? lat, double? lng}) =>
      directoryGate.future;

  @override
  Future<List<FeaturedItem>> featured() async => const [];

  @override
  Future<PublicShop?> shop(String slug) => shopGate.future;

  @override
  Future<List<PublicItem>> items(String slug) async =>
      const [PublicItem(id: 'p1', name: 'Café Touba', price: 450, inStock: true)];
}

class _SlowCourier extends CourierRepository {
  _SlowCourier() : super(null);

  final gate = Completer<String?>();

  @override
  bool get isConfigured => true;

  @override
  Future<String?> status() => gate.future;

  @override
  Future<List<DeliveryJob>> available() async => const [];

  @override
  Future<List<DeliveryJob>> mine() async => const [];

  @override
  Future<List<CourierEarnings>> earnings() async => const [];
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  SessionController session() => SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );

  testWidgets('the street shows its shape until the shops arrive',
      (tester) async {
    final street = _SlowStreet();
    await tester.pumpWidget(MaterialApp(
      home: DirectoryScreen(
        storefront: street,
        capture: CaptureRepository(null, db: db),
        session: session(),
      ),
    ));
    await tester.pump();
    expect(find.byType(ShopSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Bone), findsWidgets);

    street.directoryGate.complete(const [
      DirectoryEntry(
          orgId: 'o1', name: 'Boutique Awa', slug: 'awa', profile: 'retail'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ShopSkeleton), findsNothing);
    expect(find.text('Boutique Awa'), findsOneWidget);
  });

  testWidgets('a shop shows its shelf shape until the shop arrives',
      (tester) async {
    final street = _SlowStreet();
    await tester.pumpWidget(MaterialApp(
      home: StorefrontScreen(
        slug: 'awa',
        storefront: street,
        capture: CaptureRepository(null, db: db),
        session: session(),
      ),
    ));
    await tester.pump();
    expect(find.byType(ShopSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    street.shopGate.complete(const PublicShop(
        orgId: 'o1', name: 'Boutique Awa', slug: 'awa', profile: 'retail'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ShopSkeleton), findsNothing);
    expect(find.text('Boutique Awa'), findsWidgets);
    // The basket restore writes nothing, but reads the real database.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
  });

  testWidgets('the courier board shows rows until the status arrives',
      (tester) async {
    final courier = _SlowCourier();
    await tester.pumpWidget(MaterialApp(home: CourierScreen(courier: courier)));
    await tester.pump();
    expect(find.byType(ShopSkeleton), findsOneWidget);
    courier.gate.complete('approved');
    await tester.pump();
    await tester.pump();
    expect(find.byType(ShopSkeleton), findsNothing);
    expect(find.textContaining('Disponibles'), findsOneWidget);
  });

  testWidgets('the skeleton breathes, and is one word to a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home: ShopSkeleton.list()));
    final fade = find.descendant(
        of: find.byType(ShopSkeleton), matching: find.byType(FadeTransition));
    expect(fade, findsOneWidget);
    final before = tester.widget<FadeTransition>(fade).opacity.value;
    await tester.pump(const Duration(milliseconds: 550));
    final after = tester.widget<FadeTransition>(fade).opacity.value;
    expect(after, isNot(closeTo(before, 0.05)));

    expect(find.bySemanticsLabel('Chargement…'), findsOneWidget);
    // Not one bone is announced.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Chargement…')).childrenCount,
      0,
    );
    handle.dispose();
  });

  testWidgets('less motion asked for: the shapes hold still', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: ShopSkeleton.shelf()),
    ));
    expect(find.byType(Bone), findsWidgets);
    expect(
      find.descendant(
          of: find.byType(ShopSkeleton), matching: find.byType(FadeTransition)),
      findsNothing,
    );
  });
}

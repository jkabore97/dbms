import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'zz_shot_r_lib.dart';

class _V extends StorefrontRepository {
  _V(this.theme) : super(null);
  final String? theme;
  @override
  bool get isConfigured => true;
  @override
  Future<PublicShop?> shop(String slug) async => PublicShop(
      orgId: 'o1', name: 'Elim Shop', slug: 'elim-shop', profile: 'retail', theme: theme,
      blurb: 'Pagnes, savons et épices', address: 'Gounghin',
      style: const StorefrontStyle(tagline: 'Pagnes et gâteaux depuis 1998'));
  @override
  Future<List<PublicItem>> items(String slug) async => const [
        PublicItem(id: 'p1', name: 'Sucre', price: 750, inStock: true),
        PublicItem(id: 'p2', name: 'Pagne', price: 6000, inStock: true),
        PublicItem(id: 'p3', name: 'Savon', price: 450, inStock: true),
      ];
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadFonts();
  });
  for (final w in [390.0, 1280.0]) {
    for (final (name, theme) in [('before', null), ('after', 'prune')]) {
      testWidgets('r5 $name $w', (tester) async {
        size(tester, w, 844);
        final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
        await tester.pumpWidget(app(StorefrontScreen(
          slug: 'elim-shop',
          storefront: _V(theme),
          capture: CaptureRepository(null, db: db),
          session: SessionController(
              db: db, auth: AuthRepository(null), admin: AdminRepository(null),
              accounting: AccountingRepository(null)),
        )));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        await tester.pump(const Duration(seconds: 2));
        await shoot(tester, 'b122_R_r5_vitrine_prune_${name}_${w.toInt()}');
      });
    }
  }
}

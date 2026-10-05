import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every page inside a business that the code opens by a typed path must
/// exist. The vitrine card on the shop home once pushed `parametres` where
/// the settings live at `administration/parametres`, and a shopkeeper got
/// the router's red « Page Not Found ». This reads every
/// `Routes.inside(…, '…')` in lib/ and asks the real router for each.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('every typed path inside a business resolves to a page', () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final router = buildRouter(
      SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      ),
    );
    final typed = RegExp(r"Routes\.inside\([^,]+,\s*'([^']+)'");
    final paths = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in typed.allMatches(f.readAsStringSync())) {
        // An interpolated id stands for any id; a query is not the path.
        paths.add(
          m.group(1)!.replaceAll(RegExp(r'\$\{?\w+\}?'), 'x1').split('?').first,
        );
      }
    }
    expect(paths, isNotEmpty);
    final missing = [
      for (final p in paths)
        if (router.configuration.findMatch(Uri.parse('/o/org-1/$p')).isEmpty) p,
    ];
    expect(missing, isEmpty, reason: 'no page for: $missing');
    expect(Routes.orgSettings('o1'), '/o/o1/administration/parametres');
    expect(
      router.configuration.findMatch(Uri.parse('/o/o1/parametres')).isEmpty,
      isTrue,
      reason: 'the address the card used to open really is not a page',
    );
  });

  testWidgets('an unknown address shows the way home, not a debug page', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: NotFoundScreen()));
    expect(find.text("Cette page n'existe pas"), findsOneWidget);
    expect(find.text("Retour à l'accueil"), findsOneWidget);
  });
}

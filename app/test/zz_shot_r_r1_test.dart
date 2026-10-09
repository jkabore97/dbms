import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/security/security_settings.dart';
import 'package:kaj_app/features/account/security_screen.dart';
import 'package:local_auth/local_auth.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'zz_shot_r_lib.dart';

class _Bio extends LocalAuthentication {
  _Bio(this.enrolled);
  final bool enrolled;
  @override
  Future<bool> get canCheckBiometrics async => true;
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      enrolled ? const [BiometricType.face] : const [];
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR');
    await loadFonts();
  });
  for (final enrolled in [true, false]) {
    for (final lang in ['fr', 'en']) {
      testWidgets('r1 $enrolled $lang', (tester) async {
        size(tester, 390, 844);
        final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
        final s = SecuritySettings(db, biometrics: _Bio(enrolled));
        await tester.runAsync(s.load);
        await tester.pumpWidget(app(SecurityScreen(settings: s), lang: lang));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await shoot(tester, 'b122_R_r1_security_${enrolled ? 'enrolled' : 'none'}_$lang');
        await tester.runAsync(db.close);
      });
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The report: "every time I reload a page the loading icon keeps spinning
/// and never shows the page." The server logs for that minute show the
/// resolve completing — profiles, claim_my_invitations, my_orgs, all 200 —
/// and then nothing from the page that should have appeared.
///
/// What is different from every reload the routing suite walks: the token
/// was still live, so there was no code screen in between. The address bar
/// named the business page from the first frame, the resolve finished with
/// the address unchanged, and the page had to redraw in place.
class _LiveAuth extends AuthRepository {
  _LiveAuth() : super(null);

  final gate = Completer<List<OrgSummary>>();

  @override
  bool get hasLiveSession => true;

  @override
  Future<List<OrgSummary>> fetchOrgs() => gate.future;
}

class _QuietAdmin extends AdminRepository {
  _QuietAdmin() : super(null);

  @override
  Future<bool> isPlatformAdmin() async => false;

  @override
  Future<int> claimMyInvitations() async => 0;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  Future<void> flush(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
  }

  const org = OrgSummary(
      id: 'org-1', name: 'Boutique Sanou', profile: 'retail', roles: ['owner']);

  Future<_LiveAuth> reloadAt(WidgetTester tester, String location) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
    addTearDown(
        () => tester.binding.platformDispatcher.defaultRouteNameTestValue = '/');

    // A device that signed in before, with a code — and, this time, a token
    // the server still honours.
    await tester.runAsync(() async {
      final salt = PinCodec.newSalt();
      await db.saveIdentity(LocalIdentity(
        userId: 'user-israel',
        displayName: 'Israel',
        phone: '+22670000001',
        pinSalt: salt,
        pinHash: PinCodec.hash('1379', salt),
        orgsRefreshedAt: DateTime.now(),
      ));
      await db.cacheOrgs(const [org]);
    });

    final auth = _LiveAuth();
    await tester.pumpWidget(KajApp(
      db: db,
      auth: auth,
      admin: _QuietAdmin(),
      reports: ReportsRepository(null),
      accounting: AccountingRepository(null),
      console: ConsoleRepository(null),
      farm: FarmRepository(null),
      invoicing: InvoicingRepository(null),
      retail: RetailRepository(null),
      staff: StaffRepository(null),
      capture: CaptureRepository(null, db: db),
      onboarding: OnboardingRepository(null),
    ));
    await flush(tester);
    return auth;
  }

  testWidgets(
      'a live-session reload of a business page redraws when the list lands',
      (tester) async {
    final auth = await reloadAt(tester, '/o/org-1/produits');

    // Mid-resolve: the address is right, the list is not here yet, so the
    // page holds the door with a spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Articles'), findsNothing);

    // my_orgs answers.
    auth.gate.complete(const [org]);
    await flush(tester);

    expect(find.text('Articles'), findsOneWidget,
        reason: 'the org list landed with the address unchanged, and the '
            'page never redrew — the spinner the owner saw on every reload');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the same reload on the business home', (tester) async {
    final auth = await reloadAt(tester, '/o/org-1');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    auth.gate.complete(const [org]);
    await flush(tester);

    expect(find.text('Boutique Sanou'), findsWidgets,
        reason: 'the home never appeared after the list landed');
  });
}

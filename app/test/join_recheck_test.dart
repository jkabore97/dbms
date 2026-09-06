import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/features/auth/join_or_apply_screen.dart';

/// The waiting screen checks for itself whether the wait is over.
///
/// The report: an applicant the platform approved stayed on this page until
/// they reinstalled the app. Approval creates their business server-side, so
/// `my_orgs()` returns it — but the app fetched that list once at launch and
/// never again. The screen now re-reads its application and re-resolves the
/// org list on a timer while somebody waits, so approval reaches them with
/// no button to tap and no reinstall.
class _FakeOnboarding extends OnboardingRepository {
  _FakeOnboarding(this._app) : super(null);

  OrgApplication? _app;
  set app(OrgApplication? a) => _app = a;

  @override
  Future<bool> isProfileComplete() async => true;

  @override
  Future<OrgApplication?> myApplication() async => _app;
}

const _pending = OrgApplication(
    id: 'a1', name: 'Chez Awa', slug: 'chez-awa', profile: 'retail');
const _approved = OrgApplication(
    id: 'a1',
    name: 'Chez Awa',
    slug: 'chez-awa',
    profile: 'retail',
    status: 'approved');

void main() {
  Future<int> pumpWaiting(
    WidgetTester tester,
    _FakeOnboarding onboarding,
    void Function() onRetry,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: JoinOrApplyScreen(
        identity: const LocalIdentity(userId: 'u1', phone: '+22670000000'),
        onboarding: onboarding,
        admin: AdminRepository(null),
        onRetry: () async => onRetry(),
        onSignOut: () {},
      ),
    ));
    // initState kicks off the first _load; let it settle.
    await tester.pump();
    await tester.pump();
    return 0;
  }

  testWidgets('re-checks on a timer while an application is pending',
      (tester) async {
    final onboarding = _FakeOnboarding(_pending);
    var retries = 0;
    await pumpWaiting(tester, onboarding, () => retries++);

    // The pending card is up, and nothing has been re-resolved yet.
    expect(find.text('Demande envoyée'), findsOneWidget);
    expect(retries, 0);

    // Twelve seconds later the screen has checked for itself.
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    expect(retries, greaterThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox()); // dispose → cancels the timer
  });

  testWidgets('when approval lands, the card says it and the business opens',
      (tester) async {
    final onboarding = _FakeOnboarding(_pending);
    var retries = 0;
    await pumpWaiting(tester, onboarding, () => retries++);
    expect(find.text('Demande envoyée'), findsOneWidget);

    // The platform approves between one check and the next.
    onboarding.app = _approved;
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    await tester.pump();

    // The card now says it is opening the business, and the org list was
    // re-resolved (the real router then carries the applicant in).
    expect(find.textContaining('Ouverture de votre entreprise'), findsOneWidget);
    expect(retries, greaterThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the timer stops when the screen goes away', (tester) async {
    final onboarding = _FakeOnboarding(_pending);
    var retries = 0;
    await pumpWaiting(tester, onboarding, () => retries++);

    await tester.pumpWidget(const SizedBox());
    final before = retries;
    // No pending timer should fire after disposal — pumping past the interval
    // must not add a retry, and the test framework would flag a live timer.
    await tester.pump(const Duration(seconds: 30));
    expect(retries, before);
  });
}

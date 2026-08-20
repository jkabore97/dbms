import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/features/admin/platform_people_screen.dart';

/// The platform admin's global people directory (047): it lists accounts across
/// every business, filters as you type, and opens a person to their businesses
/// and the actions a platform admin may take.
class _FakeConsole extends ConsoleRepository {
  _FakeConsole() : super(null);

  final _all = const [
    PlatformPerson(
        userId: 'u1',
        isPlatformAdmin: false,
        businessCount: 2,
        fullName: 'Awa Traoré',
        email: 'awa@example.com'),
    PlatformPerson(
        userId: 'u2',
        isPlatformAdmin: true,
        businessCount: 0,
        fullName: 'Kaj Admin'),
  ];

  @override
  Future<List<PlatformPerson>> searchPeople(String? query,
      {int limit = 50, int offset = 0}) async {
    final q = (query ?? '').trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((p) => p.label.toLowerCase().contains(q)).toList();
  }

  @override
  Future<List<PersonOrg>> userOrgs(String userId) async => const [
        PersonOrg(
            orgId: 'o1',
            orgName: 'Boutique A',
            profile: 'retail',
            role: 'owner'),
      ];
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('lists every account and filters as you type', (tester) async {
    await tester.pumpWidget(wrap(PlatformPeopleScreen(
      console: _FakeConsole(),
      admin: AdminRepository(null),
    )));
    await tester.pump(); // resolve the initial load

    expect(find.text('Awa Traoré'), findsOneWidget);
    expect(find.text('Kaj Admin'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'awa');
    // The 300ms debounce, then the reload.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Awa Traoré'), findsOneWidget);
    expect(find.text('Kaj Admin'), findsNothing);
  });

  testWidgets('opening a person shows their businesses and the platform toggle',
      (tester) async {
    await tester.pumpWidget(wrap(PlatformPeopleScreen(
      console: _FakeConsole(),
      admin: AdminRepository(null),
    )));
    await tester.pump();

    await tester.tap(find.text('Awa Traoré'));
    await tester.pump(); // open the sheet
    await tester.pump(); // resolve userOrgs

    expect(find.text('Boutique A'), findsOneWidget);
    expect(find.text('Accès plateforme (Kaj)'), findsOneWidget);
    // The account Worker is not configured here, so the reset/delete buttons
    // are replaced by the note that says so.
    expect(find.textContaining('service de comptes'), findsOneWidget);
    expect(find.text('Réinitialiser le mot de passe'), findsNothing);
  });
}

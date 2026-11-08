import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/features/admin/add_to_business_sheet.dart';

/// The owner (169): « I want to be able to add a user that already has an
/// account to a business. » From Awa's sheet the platform admin finds the
/// business, chooses the role, and adds — no invitation code. A refusal
/// from the server is said, and the sheet stays open.
class _Console extends ConsoleRepository {
  _Console({this.refuse}) : super(null);

  final String? refuse;
  final calls = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<OrgPage> searchOrgs({
    String? query,
    String? profile,
    String status = 'active',
    String? activity,
    String sort = 'activity',
    int limit = 50,
    int offset = 0,
  }) async {
    calls.add('search:$query:$status');
    return const OrgPage(rows: [
      OrgRow(id: 'shop', name: 'Boutique Mara', slug: 'boutique-mara', profile: 'retail', currency: 'XOF', memberCount: 2),
      OrgRow(id: 'farm', name: 'Ferme Kaj', slug: 'ferme-kaj', profile: 'farm', currency: 'XOF', memberCount: 1),
    ], total: 2);
  }

  @override
  Future<void> addMember({required String orgId, required String userId, required String role}) async {
    calls.add('add:$orgId:$userId:$role');
    if (refuse != null) throw Exception(refuse);
  }
}

Future<void> _open(WidgetTester tester, _Console console) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AddToBusinessSheet(
        console: console,
        person: const PlatformPerson(userId: 'awa', isPlatformAdmin: false, businessCount: 0, fullName: 'Awa'),
      ),
    ),
  ));
}

void main() {
  testWidgets('find the business, choose the role, add — no code', (tester) async {
    final console = _Console();
    await _open(tester, console);
    expect(find.byKey(const Key('add-confirm')), findsNothing, reason: 'nothing to add before a business is chosen');

    await tester.enterText(find.byKey(const Key('add-org-search')), 'ferme');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(console.calls.first, 'search:ferme:active', reason: 'active businesses only');
    await tester.tap(find.byKey(const Key('add-org-pick-farm')));
    await tester.pumpAndSettle();

    expect(find.text('Ferme Kaj'), findsOneWidget);
    expect(find.byKey(const Key('add-role-super_admin')), findsNothing);
    expect(find.byKey(const Key('add-role-owner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-role-manager')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-confirm')));
    await tester.pumpAndSettle();
    expect(console.calls.last, 'add:farm:awa:manager');
  });

  testWidgets('a refusal is said and the sheet stays', (tester) async {
    final console = _Console(refuse: 'Awa fait déjà partie de « Boutique Mara » (employee).');
    await _open(tester, console);
    await tester.enterText(find.byKey(const Key('add-org-search')), 'boutique');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-org-pick-shop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-confirm')));
    await tester.pumpAndSettle();
    expect(console.calls.last, 'add:shop:awa:employee', reason: 'employee by default');
    expect(find.textContaining('fait déjà partie'), findsOneWidget);
    expect(find.byKey(const Key('add-confirm')), findsOneWidget);
  });
}

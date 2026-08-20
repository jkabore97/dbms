import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/models.dart';
import 'package:kaj_app/features/admin/people_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The People tab as an account manager: tapping a member opens a menu, and the
/// two Worker-backed actions (reset password, delete account) appear only when
/// the account Worker's address was compiled in. Role change and remove are
/// always there.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin({required this.canManage}) : super(null);

  final bool canManage;

  @override
  bool get canManageAccounts => canManage;

  @override
  String? get currentUserId => 'someone-else';

  @override
  Future<List<Member>> fetchMembers(String orgId) async => const [
        Member(
          membershipId: 'm1',
          userId: 'u1',
          role: 'employee',
          scopeKind: 'org',
          scopeId: 'o1',
          visibility: 'full',
          fullName: 'Awa',
        ),
      ];

  @override
  Future<List<Invitation>> fetchInvitations(String orgId) async => const [];

  @override
  Future<List<Entity>> fetchStructure(String orgId) async => const [];
}

void main() {
  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: child,
      );

  Future<void> openMenu(WidgetTester tester, {required bool canManage}) async {
    await tester.pumpWidget(wrap(PeopleScreen(
      admin: _FakeAdmin(canManage: canManage),
      orgId: 'o1',
      orgName: 'Boutique',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Awa'));
    await tester.pumpAndSettle();
  }

  testWidgets('without the account Worker, only role change and remove show',
      (tester) async {
    await openMenu(tester, canManage: false);

    expect(find.text('Changer la responsabilité'), findsOneWidget);
    expect(find.text("Retirer de l'entreprise"), findsOneWidget);
    expect(find.text('Réinitialiser le mot de passe'), findsNothing);
    expect(find.text('Supprimer le compte'), findsNothing);
  });

  testWidgets('with the account Worker, password reset and delete appear too',
      (tester) async {
    await openMenu(tester, canManage: true);

    expect(find.text('Changer la responsabilité'), findsOneWidget);
    expect(find.text("Retirer de l'entreprise"), findsOneWidget);
    expect(find.text('Réinitialiser le mot de passe'), findsOneWidget);
    expect(find.text('Supprimer le compte'), findsOneWidget);
  });
}

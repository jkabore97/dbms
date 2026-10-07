import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/models.dart';
import 'package:kaj_app/core/admin/team.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/features/admin/member_edit_sheet.dart';
import 'package:kaj_app/features/admin/team_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Équipe as the account manager (101 folded the old People screen into
/// it): tapping a person opens what may be done to them. Everything that
/// manages somebody — the salary, their information, the responsibility,
/// a sign-out, the removal — is offered only for a person the caller
/// outranks, never the owner nor oneself (the client mirror of 045's rule);
/// the two Worker-backed actions (reset password, delete account) appear
/// only when the account Worker's address was compiled in.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin({required this.canManage, this.memberRole = 'employee'})
      : super(null);

  final bool canManage;
  final String memberRole;
  final roleChanges = <String>[];

  @override
  bool get canManageAccounts => canManage;

  @override
  String? get currentUserId => 'me';

  @override
  Future<TeamOverview?> teamOverview(String orgId) async => TeamOverview(
        seats: const TeamSeats(free: 1, used: 1, open: false),
        members: [
          const TeamMember(userId: 'u0', name: 'Patronne', roles: ['owner'],
              isOwner: true, membershipIds: ['m0'], salary: 90000, period: 'month'),
          const TeamMember(userId: 'me', name: 'Moi', roles: ['admin'], isMe: true,
              membershipIds: ['m9'], salary: 70000, period: 'month'),
          TeamMember(userId: 'u1', name: 'Awa', roles: [memberRole],
              membershipIds: const ['m1'], salary: 45000, period: 'month'),
        ],
      );

  @override
  Future<List<Member>> fetchMembers(String orgId) async => [
        Member(
          membershipId: 'm1',
          userId: 'u1',
          role: memberRole,
          scopeKind: 'org',
          scopeId: 'o1',
          visibility: 'full',
          fullName: 'Awa',
          phone: '+22670000001',
        ),
        const Member(
          membershipId: 'm0',
          userId: 'u0',
          role: 'owner',
          scopeKind: 'org',
          scopeId: 'o1',
          visibility: 'full',
          fullName: 'Patronne',
        ),
      ];

  @override
  Future<void> setMembershipRole(String membershipId, String role) async =>
      roleChanges.add('$membershipId:$role');
}

void main() {
  Widget wrap(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: child,
      );

  Future<_FakeAdmin> open(
    WidgetTester tester, {
    required bool canManage,
    List<String> callerRoles = const ['admin'],
    String memberRole = 'employee',
    String tap = 'u1',
  }) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = _FakeAdmin(canManage: canManage, memberRole: memberRole);
    await tester.pumpWidget(wrap(TeamScreen(
      org: OrgSummary(id: 'o1', name: 'Boutique', profile: 'retail', roles: callerRoles),
      admin: admin,
      onboarding: OnboardingRepository(null),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('team-member-$tap')));
    await tester.pumpAndSettle();
    return admin;
  }

  testWidgets('without the account Worker, no password reset nor deletion',
      (tester) async {
    await open(tester, canManage: false);

    expect(find.text('Modifier les informations'), findsOneWidget);
    expect(find.text('Changer la responsabilité'), findsOneWidget);
    expect(find.text("Retirer de l'équipe"), findsOneWidget);
    expect(find.text('Salaire'), findsOneWidget);
    expect(find.text('Réinitialiser le mot de passe'), findsNothing);
    expect(find.text('Supprimer le compte'), findsNothing);
  });

  testWidgets('with the account Worker, the information and every action',
      (tester) async {
    await open(tester, canManage: true);

    // The information is shown…
    expect(find.text('+22670000001'), findsOneWidget);
    // …and, because the caller outranks them, every action.
    expect(find.text('Modifier les informations'), findsOneWidget);
    expect(find.text('Changer la responsabilité'), findsOneWidget);
    expect(find.text("Retirer de l'équipe"), findsOneWidget);
    expect(find.text('Réinitialiser le mot de passe'), findsOneWidget);
    expect(find.text('Supprimer le compte'), findsOneWidget);
  });

  testWidgets('a peer or somebody above: no action, no salary', (tester) async {
    await open(tester, canManage: true, memberRole: 'admin');

    expect(find.text('Salaire'), findsNothing);
    expect(find.text('Modifier les informations'), findsNothing);
    expect(find.text('Changer la responsabilité'), findsNothing);
    expect(find.text('Réinitialiser le mot de passe'), findsNothing);
    expect(find.text('Supprimer le compte'), findsNothing);
    expect(find.text("Retirer de l'équipe"), findsNothing);
    expect(find.text('Vous ne pouvez pas modifier ce compte.'), findsOneWidget);
  });

  testWidgets('the owner and oneself: no salary, no edit, no removal',
      (tester) async {
    await open(tester, canManage: true, tap: 'u0');
    expect(find.byKey(const Key('team-action-salary')), findsNothing);
    expect(find.byKey(const Key('team-action-edit')), findsNothing);
    expect(find.byKey(const Key('team-action-remove')), findsNothing);
    expect(find.text('Le propriétaire gère ses propres informations.'), findsOneWidget);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-member-me')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-action-salary')), findsNothing);
    expect(find.byKey(const Key('team-action-signout')), findsNothing);
  });

  testWidgets('salaries: an admin sees only those below; the owner every one',
      (tester) async {
    await open(tester, canManage: false, tap: 'u1');
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    // An admin: Awa's (below) shown; the owner's and their own not.
    expect(find.textContaining('45'), findsWidgets);
    expect(find.textContaining('90'), findsNothing);
    expect(find.textContaining('70'), findsNothing);
  });

  testWidgets('the owner reads every salary', (tester) async {
    await open(tester, canManage: false, callerRoles: const ['owner']);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.textContaining('90'), findsWidgets);
    expect(find.textContaining('70'), findsWidgets);
  });

  testWidgets('a role is changed among those below the caller, never super admin',
      (tester) async {
    final admin = await open(tester, canManage: false);
    await tester.tap(find.byKey(const Key('team-action-role')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-role-super_admin')), findsNothing);
    expect(find.byKey(const Key('team-role-admin')), findsNothing);
    expect(find.byKey(const Key('team-role-manager')), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-role-manager')));
    await tester.tap(find.byKey(const Key('team-role-save')));
    await tester.pumpAndSettle();
    expect(admin.roleChanges, ['m1:manager']);
  });

  test('the roles an owner and an admin may hand out', () {
    expect(grantableRolesFor(const ['owner']), contains('admin'));
    expect(grantableRolesFor(const ['owner']), isNot(contains('super_admin')));
    expect(grantableRolesFor(const ['admin']), isNot(contains('admin')));
    expect(grantableRolesFor(const ['employee']), ['observer']);
  });

  test('the rank ladder places each role where the server does', () {
    // super_admin is Kaj's platform staff: above a store's owner. The
    // platform-admin flag is above everything.
    expect(accountRoleRank('platform_admin'),
        greaterThan(accountRoleRank('super_admin')));
    expect(accountRoleRank('super_admin'), greaterThan(accountRoleRank('owner')));
    expect(accountRoleRank('owner'), greaterThan(accountRoleRank('admin')));
    expect(accountRoleRank('admin'), greaterThan(accountRoleRank('manager')));
    expect(accountRoleRank('manager'), greaterThan(accountRoleRank('employee')));
    expect(accountRoleRank('sorcier-inconnu'), 0);
    expect(accountRankOf(const ['employee', 'admin']), accountRoleRank('admin'));
  });
}

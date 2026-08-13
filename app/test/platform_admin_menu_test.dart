import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';

/// What a platform admin is allowed to see, asserted on the predicate every
/// screen gates on.
///
/// This exists because of a bug that made almost the entire admin surface
/// invisible to exactly the account most likely to need it, and stayed
/// invisible through four merged pull requests.
///
/// `my_orgs()` has, since 010, returned a single role — `platform_admin` —
/// for somebody who runs the platform: they are a member of no business and
/// can open all of them. `OrgSummary.isAdmin` knew the three *membership*
/// roles and nothing else, so it answered false for every business, and
/// everything behind it disappeared: Administration, Personnel, and the
/// invitation generator.
///
/// Nothing caught it. `flutter analyze` cannot — both branches type-check —
/// and no test asked the question, because every existing test builds an org
/// from a membership role. So the case below is the one that was missing.
void main() {
  OrgSummary org(List<String> roles) => OrgSummary(
        id: '00000000-0000-0000-0000-000000000001',
        name: 'Boutique',
        profile: 'retail',
        roles: roles,
      );

  group('a platform admin', () {
    test('counts as an admin of every business they can open', () {
      // The exact shape my_orgs() returns for them: one role, and not one of
      // the membership roles.
      expect(org(['platform_admin']).isAdmin, isTrue,
          reason: 'the account that runs the platform was locked out of '
              'Administration, Personnel and inviting anybody');
    });

    test('counts as a super admin, which the console is gated on', () {
      expect(org(['platform_admin']).isSuperAdmin, isTrue);
    });

    test('is not mistaken for an observer', () {
      expect(org(['platform_admin']).isObserverOnly, isFalse);
    });
  });

  group('ordinary members are unchanged', () {
    test('an owner is an admin and a super admin', () {
      expect(org(['owner']).isAdmin, isTrue);
      expect(org(['owner']).isSuperAdmin, isTrue);
    });

    test('an admin administers but is not a super admin', () {
      expect(org(['admin']).isAdmin, isTrue);
      expect(org(['admin']).isSuperAdmin, isFalse);
    });

    test('a manager does not administer', () {
      expect(org(['manager']).isAdmin, isFalse);
    });

    test('an employee does not administer', () {
      expect(org(['employee']).isAdmin, isFalse);
      expect(org(['employee']).isSuperAdmin, isFalse);
    });

    test('an observer is still only an observer', () {
      expect(org(['observer']).isAdmin, isFalse);
      expect(org(['observer']).isObserverOnly, isTrue);
    });

    test('somebody holding two roles gets the stronger one', () {
      expect(org(['observer', 'admin']).isAdmin, isTrue);
      expect(org(['observer', 'admin']).isObserverOnly, isFalse);
    });
  });
}

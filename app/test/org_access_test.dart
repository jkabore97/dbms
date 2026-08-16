import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/org_access.dart';

/// The client half of the owner's dial: defaults mirror the server's, tiers
/// resolve the way feature_access() resolves them, and admins are never
/// dialled down. The refusals themselves are proven by test_team_access.sql.
void main() {
  test('the untouched dial is today: everything edit, reports view', () {
    const access = OrgAccess.forTier({});
    for (final f in OrgAccess.features) {
      expect(access.canSee(f), isTrue, reason: f);
      expect(access.canEdit(f), f != 'reports', reason: f);
    }
  });

  test('rules land on their feature and nowhere else', () {
    const access = OrgAccess.forTier({
      'products': 'view',
      'credits': 'hidden',
    });
    expect(access.canSee('products'), isTrue);
    expect(access.canEdit('products'), isFalse);
    expect(access.canSee('credits'), isFalse);
    expect(access.canEdit('production'), isTrue);
  });

  test('an admin ignores every rule', () {
    expect(OrgAccess.allEdit.canEdit('credits'), isTrue);
    expect(OrgAccess.allEdit.canSee('reports'), isTrue);
    expect(OrgAccess.allEdit.canEdit('reports'), isTrue);
  });

  test('tiers resolve like the server does', () {
    expect(OrgAccess.tierOf(['employee']), 'employee');
    expect(OrgAccess.tierOf(['supervisor']), 'supervisor');
    expect(OrgAccess.tierOf(['manager']), 'supervisor');
    expect(OrgAccess.tierOf(['employee', 'manager']), 'supervisor');
    expect(OrgAccess.tierOf(['observer']), 'employee');
  });
}

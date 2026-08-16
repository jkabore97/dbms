/// What the signed-in person may do with each tool of one business.
///
/// The server is the contract — feature_access() in migration 031 refuses
/// what must be refused whatever this object says. This is the courteous
/// half: it decides which buttons exist at all, so an employee whose owner
/// closed the carnet never sees a carnet to be refused by.
///
/// Defaults mirror the server's exactly: every feature 'edit' except
/// reports at 'view', so an unloaded or offline state behaves like a
/// business that never touched the dial.
class OrgAccess {
  const OrgAccess._(this._rules, {required this.isAdmin});

  /// Owners and admins: every tool, always. Also the default handed to
  /// screens in tests and in builds with no server.
  static const allEdit = OrgAccess._({}, isAdmin: true);

  /// The rules of one tier, as fetched for the signed-in member.
  const OrgAccess.forTier(Map<String, String> rules)
      : this._(rules, isAdmin: false);

  final Map<String, String> _rules;
  final bool isAdmin;

  /// 'hidden' | 'view' | 'edit' for a feature key from 031.
  String accessTo(String feature) {
    if (isAdmin) return 'edit';
    return _rules[feature] ?? (feature == 'reports' ? 'view' : 'edit');
  }

  bool canSee(String feature) => accessTo(feature) != 'hidden';
  bool canEdit(String feature) => accessTo(feature) == 'edit';

  /// Which tier a membership's roles fall into — the same mapping
  /// feature_access() makes server-side. Admin roles never reach here;
  /// the caller checks org.isAdmin first.
  static String tierOf(List<String> roles) =>
      roles.any((r) => r == 'manager' || r == 'supervisor')
          ? 'supervisor'
          : 'employee';

  /// The feature keys of 031, in the order the owner's screen shows them.
  static const features = [
    'products',
    'production',
    'credits',
    'tontines',
    'invoices',
    'photos',
    'reports',
    'staff',
  ];
}

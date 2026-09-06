import 'package:flutter/foundation.dart' show setEquals;

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
///
/// Since 066 a second layer sits on top of the dial: the plan. On a Free
/// business the Pro tools answer 'view' — never 'hidden', the owner keeps
/// seeing them with a badge — and only ever from 'edit'. Whatever the dial
/// hid stays hidden. Same rule as `feature_access()` server-side.
class OrgAccess {
  const OrgAccess._(this._rules,
      {required this.isAdmin, this.proLocked = const {}});

  /// Owners and admins: every tool, always. Also the default handed to
  /// screens in tests and in builds with no server.
  static const allEdit = OrgAccess._({}, isAdmin: true);

  /// An owner or admin of a business whose plan locks [proLocked].
  const OrgAccess.admin({Set<String> proLocked = const {}})
      : this._(const {}, isAdmin: true, proLocked: proLocked);

  /// The rules of one tier, as fetched for the signed-in member.
  const OrgAccess.forTier(Map<String, String> rules,
      {Set<String> proLocked = const {}})
      : this._(rules, isAdmin: false, proLocked: proLocked);

  final Map<String, String> _rules;
  final bool isAdmin;

  /// Tool keys the business's plan holds at 'view' (066). Empty on Pro,
  /// empty for the platform admin, the Pro list on a Free business.
  final Set<String> proLocked;

  /// 'hidden' | 'view' | 'edit' for a feature key from 031 or 066.
  String accessTo(String feature) {
    final own = isAdmin
        ? 'edit'
        : _rules[feature] ?? (feature == 'reports' ? 'view' : 'edit');
    if (own == 'edit' && proLocked.contains(feature)) return 'view';
    return own;
  }

  bool canSee(String feature) => accessTo(feature) != 'hidden';
  bool canEdit(String feature) => accessTo(feature) == 'edit';

  /// Whether to draw the Pro badge on this tool: the plan is what holds it,
  /// not the dial. A tool the dial hid gets no badge — there is nothing to
  /// see behind it either way.
  bool isProLocked(String feature) =>
      proLocked.contains(feature) && accessTo(feature) != 'hidden';

  /// Which tier a membership's roles fall into — the same mapping
  /// feature_access() makes server-side. Admin roles never reach here;
  /// the caller checks org.isAdmin first.
  static String tierOf(List<String> roles) =>
      roles.any((r) => r == 'manager' || r == 'supervisor')
          ? 'supervisor'
          : 'employee';

  /// Value equality, so the session can tell a freshly fetched dial from the
  /// one already in effect and skip a rebuild — and a redirect — when nothing
  /// actually changed.
  @override
  bool operator ==(Object other) {
    if (other is! OrgAccess) return false;
    if (other.isAdmin != isAdmin || other._rules.length != _rules.length) {
      return false;
    }
    if (!setEquals(other.proLocked, proLocked)) return false;
    for (final e in _rules.entries) {
      if (other._rules[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        isAdmin,
        Object.hashAllUnordered(
            _rules.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(proLocked),
      );

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

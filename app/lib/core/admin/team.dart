import '../cauris/feature_states.dart';

/// The Équipe screen's one read (100's team_overview): the seats, the
/// people with their salary, and the invitations still out.
class TeamOverview {
  const TeamOverview({
    required this.seats,
    this.members = const [],
    this.invitations = const [],
    this.orgName,
  });

  final TeamSeats seats;
  final List<TeamMember> members;
  final List<TeamInvite> invitations;

  /// The business's name, for the message an invitation is shared with.
  final String? orgName;

  factory TeamOverview.fromJson(Map<String, dynamic> j) => TeamOverview(
        seats: TeamSeats.fromJson(
            Map<String, dynamic>.from((j['seats'] as Map?) ?? const {})),
        members: [
          for (final m in (j['members'] as List? ?? const []))
            if (m is Map) TeamMember.fromJson(Map<String, dynamic>.from(m)),
        ],
        invitations: [
          for (final i in (j['invitations'] as List? ?? const []))
            if (i is Map) TeamInvite.fromJson(Map<String, dynamic>.from(i)),
        ],
        orgName: j['org_name'] as String?,
      );
}

/// Somebody in the business, and what they are paid — when it was said.
class TeamMember {
  const TeamMember({
    required this.userId,
    required this.name,
    this.phone,
    this.roles = const [],
    this.isOwner = false,
    this.salary,
    this.period,
    this.hourly,
    this.isMe = false,
    this.membershipIds = const [],
  });

  final String userId;
  final String name;
  final String? phone;
  final List<String> roles;
  final bool isOwner;

  /// The signed-in person themself: not removed from here.
  final bool isMe;

  /// Their grants in this business — all of them go when they are removed
  /// from the team (004's delete, as Administration › Personnes does).
  final List<String> membershipIds;

  /// Paid by the hour in « Paie et journées » (a casual, 012): the rate,
  /// changed there. Null otherwise.
  final double? hourly;

  /// Null when no salary was recorded.
  final double? salary;

  /// 'month' | 'week' | 'day'.
  final String? period;

  /// The highest of this person's roles, for one label.
  String get role {
    const order = ['owner', 'super_admin', 'admin', 'manager', 'supervisor',
        'employee', 'observer'];
    for (final r in order) {
      if (roles.contains(r)) return r;
    }
    return roles.isEmpty ? 'employee' : roles.first;
  }

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    final s = j['salary'];
    return TeamMember(
      userId: '${j['user_id']}',
      name: '${j['name'] ?? ''}'.trim().isEmpty ? '—' : '${j['name']}',
      phone: j['phone'] as String?,
      roles: [for (final r in (j['roles'] as List? ?? const [])) '$r'],
      isOwner: j['owner'] == true,
      salary: s is num ? s.toDouble() : double.tryParse('${s ?? ''}'),
      period: j['period'] as String?,
      hourly: _num(j['hourly']),
      isMe: j['me'] == true,
      membershipIds: [for (final m in (j['memberships'] as List? ?? const [])) '$m'],
    );
  }
}

/// An invitation not claimed yet.
class TeamInvite {
  const TeamInvite({
    required this.id,
    required this.code,
    this.name,
    this.phone,
    this.role,
    this.blocked = false,
    this.expiresAt,
  });

  final DateTime? expiresAt;

  final String id;
  final String code;
  final String? name;
  final String? phone;
  final String? role;

  /// The seat is taken and this is not for somebody already in: claimed
  /// now, it would be refused (« ne peut pas entrer : place prise »).
  final bool blocked;

  factory TeamInvite.fromJson(Map<String, dynamic> j) => TeamInvite(
        id: '${j['id']}',
        code: '${j['code'] ?? ''}',
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        role: j['role'] as String?,
        blocked: j['blocked'] == true,
        expiresAt: DateTime.tryParse('${j['expires_at'] ?? ''}')?.toLocal(),
      );
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

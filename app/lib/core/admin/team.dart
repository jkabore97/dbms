import '../cauris/feature_states.dart';

/// The Équipe screen's one read (100's team_overview): the seats, the
/// people with their salary, and the invitations still out.
class TeamOverview {
  const TeamOverview({
    required this.seats,
    this.members = const [],
    this.invitations = const [],
  });

  final TeamSeats seats;
  final List<TeamMember> members;
  final List<TeamInvite> invitations;

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
  });

  final String userId;
  final String name;
  final String? phone;
  final List<String> roles;
  final bool isOwner;

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
    );
  }
}

/// An invitation not claimed yet.
class TeamInvite {
  const TeamInvite({required this.id, required this.code, this.name, this.phone, this.role});

  final String id;
  final String code;
  final String? name;
  final String? phone;
  final String? role;

  factory TeamInvite.fromJson(Map<String, dynamic> j) => TeamInvite(
        id: '${j['id']}',
        code: '${j['code'] ?? ''}',
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        role: j['role'] as String?,
      );
}

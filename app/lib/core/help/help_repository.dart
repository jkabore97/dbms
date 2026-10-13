import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart' show isSchemaOutOfDate;

/// « Besoin d'aide » (batch 136, migration 133): a Pro business asks Mara's
/// training team, a trainer takes it, the business closes it. Every door
/// is the server's (help_* functions): the Pro gate, the limits, who sees
/// what and the temporary access are all checked there; this only carries
/// the answers.
///
/// A database without 133 answers « no such function »: [state] then says
/// [HelpState.missing], and the app shows the basic « Aide » — never an
/// error, never an empty button.
class HelpRepository {
  HelpRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient _c() {
    final c = _client;
    if (c == null) {
      throw StateError('Cette version a été compilée sans serveur.');
    }
    return c;
  }

  Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

  /// What the button and the « Aide » page need for this business.
  Future<HelpState> state(String orgId) async {
    try {
      return HelpState.fromJson(
        _map(await _c().rpc('help_state', params: {'p_org_id': orgId})),
      );
    } catch (e) {
      if (isSchemaOutOfDate(e)) return HelpState.missing;
      rethrow;
    }
  }

  /// « Envoyer la demande ».
  Future<HelpRequest> create({
    required String orgId,
    required String subject,
    required String contact,
    String? message,
    String? phone,
    String? photoDocumentId,
    Map<String, String> context = const {},
  }) async {
    final v = await _c().rpc(
      'help_request_create',
      params: {
        'p_org_id': orgId,
        'p_subject': subject,
        'p_message': message,
        'p_contact': contact,
        'p_phone': phone,
        'p_photo': photoDocumentId,
        'p_context': context,
      },
    );
    return HelpRequest.fromJson(_map(v));
  }

  Future<HelpRequest> reopen(String id) async => HelpRequest.fromJson(
    _map(await _c().rpc('help_reopen', params: {'p_request': id})),
  );

  /// [rating]: 1 (👍), -1 (👎) or null.
  Future<HelpRequest> close(String id, {int? rating}) async =>
      HelpRequest.fromJson(
        _map(
          await _c().rpc(
            'help_close',
            params: {'p_request': id, 'p_rating': rating},
          ),
        ),
      );

  Future<HelpRequest> grantAccess(String id) async => HelpRequest.fromJson(
    _map(await _c().rpc('help_access_grant', params: {'p_request': id})),
  );

  Future<void> revokeAccess(String id) async {
    await _c().rpc('help_access_revoke', params: {'p_request': id});
  }

  // -- The trainer's side ---------------------------------------------------

  /// The inbox; [HelpInbox.none] for anybody who is not a trainer (and on
  /// a database without 133).
  Future<HelpInbox> inbox() async {
    try {
      return HelpInbox.fromJson(_map(await _c().rpc('help_inbox')));
    } catch (e) {
      if (isSchemaOutOfDate(e)) return HelpInbox.none;
      rethrow;
    }
  }

  Future<bool> setOnDuty(bool on) async =>
      (await _c().rpc('help_set_on_duty', params: {'p_on': on})) == true;

  Future<InboxRequest> take(String id) async => InboxRequest.fromJson(
    _map(await _c().rpc('help_take', params: {'p_request': id})),
  );

  /// [answer]: 'accepted' or 'call_instead'.
  Future<InboxRequest> answerVisit(
    String id,
    String answer, {
    String? note,
  }) async => InboxRequest.fromJson(
    _map(
      await _c().rpc(
        'help_visit_answer',
        params: {'p_request': id, 'p_answer': answer, 'p_note': note},
      ),
    ),
  );

  Future<InboxRequest> resolve(String id, {String? note}) async =>
      InboxRequest.fromJson(
        _map(
          await _c().rpc(
            'help_resolve',
            params: {'p_request': id, 'p_note': note},
          ),
        ),
      );

  /// « Ouvrir l'activité (lecture seule) »: the business's id while the
  /// access lives (the server counts the opening).
  Future<String> openAccess(String id) async =>
      '${await _c().rpc('help_access_opened', params: {'p_request': id})}';

  // -- The platform's side --------------------------------------------------

  /// « Aujourd'hui »'s two counters; null for a non-admin or without 133.
  Future<Map<String, int>?> todoCounts() async {
    try {
      final v = await _c().rpc('help_todo_counts');
      if (v is! Map) return null;
      return {for (final e in v.entries) '${e.key}': _int(e.value)};
    } catch (e) {
      if (isSchemaOutOfDate(e)) return null;
      rethrow;
    }
  }

  /// The console; null for a non-admin or without 133.
  Future<HelpConsole?> console() async {
    try {
      final v = await _c().rpc('help_console');
      return v is Map
          ? HelpConsole.fromJson(Map<String, dynamic>.from(v))
          : null;
    } catch (e) {
      if (isSchemaOutOfDate(e)) return null;
      rethrow;
    }
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();
String? _text(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

/// The help hours, on Ouagadougou's clock (UTC all year).
class HelpHours {
  const HelpHours({
    this.open = 7,
    this.close = 21,
    this.inHours = true,
    this.nextOpen,
  });

  factory HelpHours.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    return HelpHours(
      open: j['open'] == null ? 7 : _int(j['open']),
      close: j['close'] == null ? 21 : _int(j['close']),
      inHours: j['in_hours'] != false,
      nextOpen: _date(j['next_open']),
    );
  }

  final int open;
  final int close;
  final bool inHours;
  final DateTime? nextOpen;
}

class HelpState {
  const HelpState({
    required this.available,
    this.pro = false,
    this.hours = const HelpHours(),
    this.request,
    this.left = 0,
    this.installed = true,
  });

  /// A database without 133: the basic « Aide ».
  static const missing = HelpState(available: true, installed: false);

  factory HelpState.fromJson(Map<String, dynamic> j) => HelpState(
    available: j['available'] == true,
    pro: j['pro'] == true,
    hours: HelpHours.fromJson(j['hours']),
    request: j['request'] is Map
        ? HelpRequest.fromJson(Map<String, dynamic>.from(j['request'] as Map))
        : null,
    left: _int(j['left']),
  );

  /// This person may ask here (a member who is not an observer).
  final bool available;

  /// The business is on Mara Pro: the trainers' queue.
  final bool pro;
  final HelpHours hours;

  /// The active request (or the last resolved, not closed yet).
  final HelpRequest? request;

  /// Requests left today.
  final int left;

  /// 133 is on the database.
  final bool installed;

  /// The trainers' « Besoin d'aide », rather than the basic « Aide ».
  bool get trainers => installed && available && pro;
}

class HelpTrainer {
  const HelpTrainer({required this.firstName, this.phone, this.member = false});

  factory HelpTrainer.fromJson(Map<String, dynamic> j) => HelpTrainer(
    firstName: _text(j['first_name']) ?? 'Mara',
    phone: _text(j['phone']),
    member: j['member'] == true,
  );

  final String firstName;

  /// Digits, for the call and WhatsApp buttons.
  final String? phone;

  /// Already of the business (an assigned trainer): no access to give.
  final bool member;
}

class HelpAccess {
  const HelpAccess({
    required this.expiresAt,
    this.live = true,
    this.opened = 0,
  });

  factory HelpAccess.fromJson(Map<String, dynamic> j) => HelpAccess(
    expiresAt: _date(j['expires_at']) ?? DateTime.now(),
    live: j['live'] != false,
    opened: _int(j['opened']),
  );

  final DateTime expiresAt;
  final bool live;
  final int opened;
}

class HelpEvent {
  const HelpEvent(this.event, this.at, [this.who]);
  final String event;
  final DateTime at;
  final String? who;
}

/// One request as its business reads it.
class HelpRequest {
  const HelpRequest({
    required this.id,
    required this.subject,
    required this.contact,
    required this.status,
    required this.createdAt,
    this.message,
    this.routedAt,
    this.queued = false,
    this.escalated = false,
    this.takenAt,
    this.trainer,
    this.visitAnswer,
    this.visitNote,
    this.resolvedAt,
    this.resolutionNote,
    this.rating,
    this.access,
    this.events = const [],
    this.hasPhoto = false,
    this.mine = false,
  });

  factory HelpRequest.fromJson(Map<String, dynamic> j) => HelpRequest(
    id: '${j['id'] ?? ''}',
    subject: _text(j['subject']) ?? 'autre',
    contact: _text(j['contact']) ?? 'whatsapp',
    status: _text(j['status']) ?? 'open',
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    message: _text(j['message']),
    routedAt: _date(j['routed_at']),
    queued: j['queued'] == true,
    escalated: j['escalated'] == true,
    takenAt: _date(j['taken_at']),
    trainer: j['trainer'] is Map
        ? HelpTrainer.fromJson(Map<String, dynamic>.from(j['trainer'] as Map))
        : null,
    visitAnswer: _text(j['visit_answer']),
    visitNote: _text(j['visit_note']),
    resolvedAt: _date(j['resolved_at']),
    resolutionNote: _text(j['resolution_note']),
    rating: j['rating'] == null ? null : _int(j['rating']),
    access: j['access'] is Map
        ? HelpAccess.fromJson(Map<String, dynamic>.from(j['access'] as Map))
        : null,
    events: [
      for (final e in (j['events'] is List ? j['events'] as List : const []))
        if (e is Map)
          HelpEvent(
            '${e['event']}',
            _date(e['at']) ?? DateTime.now(),
            _text(e['who']),
          ),
    ],
    hasPhoto: j['photo_document_id'] != null,
    mine: j['mine'] == true,
  );

  final String id;
  final String subject;

  /// 'call' | 'whatsapp' | 'visit'.
  final String contact;

  /// 'open' | 'taken' | 'resolved' | 'closed'.
  final String status;
  final DateTime createdAt;
  final String? message;
  final DateTime? routedAt;

  /// Made out of the hours: routed at the next opening.
  final bool queued;
  final bool escalated;
  final DateTime? takenAt;
  final HelpTrainer? trainer;

  /// A visit asked for: 'accepted' or 'call_instead'.
  final String? visitAnswer;
  final String? visitNote;
  final DateTime? resolvedAt;
  final String? resolutionNote;
  final int? rating;

  /// The live (or last) temporary access.
  final HelpAccess? access;
  final List<HelpEvent> events;
  final bool hasPhoto;

  /// The caller asked it (else one of the business's admins reads it).
  final bool mine;

  bool get active => status == 'open' || status == 'taken';

  /// Still waiting for the routing (made out of the hours).
  bool get waitingForHours =>
      status == 'open' && routedAt != null && routedAt!.isAfter(DateTime.now());

  /// « Autoriser l'accès 48 h » is offered: a trainer who is not of the
  /// business took it, and no access lives.
  bool get canGrant =>
      (status == 'taken' || status == 'resolved') &&
      trainer != null &&
      !trainer!.member &&
      !(access?.live ?? false);
}

/// One request as a trainer reads it.
class InboxRequest {
  const InboxRequest({
    required this.id,
    required this.orgId,
    required this.org,
    required this.profile,
    required this.subject,
    required this.contact,
    required this.status,
    required this.createdAt,
    this.city,
    this.message,
    this.screen,
    this.escalated = false,
    this.mine = false,
    this.takenBy,
    this.assigned = false,
    this.member = false,
    this.requester,
    this.phone,
    this.visitAnswer,
    this.resolvedAt,
    this.closedAt,
    this.rating,
    this.accessUntil,
  });

  factory InboxRequest.fromJson(Map<String, dynamic> j) {
    final access = j['access'];
    return InboxRequest(
      id: '${j['id'] ?? ''}',
      orgId: '${j['org_id'] ?? ''}',
      org: _text(j['org']) ?? '',
      profile: _text(j['profile']) ?? 'retail',
      subject: _text(j['subject']) ?? 'autre',
      contact: _text(j['contact']) ?? 'whatsapp',
      status: _text(j['status']) ?? 'open',
      createdAt: _date(j['created_at']) ?? DateTime.now(),
      city: _text(j['city']),
      message: _text(j['message']),
      screen: j['context'] is Map
          ? _text((j['context'] as Map)['screen'])
          : null,
      escalated: j['escalated'] == true,
      mine: j['mine'] == true,
      takenBy: _text(j['taken_by']),
      assigned: j['assigned'] == true,
      member: j['member'] == true,
      requester: _text(j['requester']),
      phone: _text(j['phone']),
      visitAnswer: _text(j['visit_answer']),
      resolvedAt: _date(j['resolved_at']),
      closedAt: _date(j['closed_at']),
      rating: j['rating'] == null ? null : _int(j['rating']),
      accessUntil: access is Map && access['live'] != false
          ? _date(access['expires_at'])
          : null,
    );
  }

  final String id;
  final String orgId;
  final String org;
  final String profile;
  final String subject;
  final String contact;
  final String status;
  final DateTime createdAt;
  final String? city;
  final String? message;
  final String? screen;
  final bool escalated;

  /// The caller took it.
  final bool mine;
  final String? takenBy;

  /// The caller is assigned to the business (038).
  final bool assigned;

  /// The caller is of the business already: no access is needed.
  final bool member;
  final String? requester;

  /// The person's number — only for the one who took it.
  final String? phone;
  final String? visitAnswer;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final int? rating;

  /// The temporary access lives until then.
  final DateTime? accessUntil;

  bool get open => status == 'open';
  bool get inProgress => status == 'taken' && mine;
  bool get done => status == 'resolved' || status == 'closed';
}

class HelpInbox {
  const HelpInbox({
    required this.trainer,
    this.admin = false,
    this.onDuty = true,
    this.inHours = true,
    this.hours = const HelpHours(),
    this.requests = const [],
  });

  static const none = HelpInbox(trainer: false);

  factory HelpInbox.fromJson(Map<String, dynamic> j) => HelpInbox(
    trainer: j['trainer'] == true,
    admin: j['admin'] == true,
    onDuty: j['on_duty'] != false,
    inHours: j['in_hours'] != false,
    hours: HelpHours.fromJson(j['hours']),
    requests: [
      for (final r
          in (j['requests'] is List ? j['requests'] as List : const []))
        if (r is Map) InboxRequest.fromJson(Map<String, dynamic>.from(r)),
    ],
  );

  final bool trainer;
  final bool admin;
  final bool onDuty;
  final bool inHours;
  final HelpHours hours;
  final List<InboxRequest> requests;

  int get waiting => requests.where((r) => r.open).length;
}

class ConsoleTrainer {
  const ConsoleTrainer({
    required this.name,
    this.onDuty = true,
    this.assigned = 0,
    this.taken = 0,
    this.resolved7 = 0,
    this.hasPhone = false,
  });

  factory ConsoleTrainer.fromJson(Map<String, dynamic> j) => ConsoleTrainer(
    name: _text(j['name']) ?? 'Formateur',
    onDuty: j['on_duty'] != false,
    assigned: _int(j['assigned']),
    taken: _int(j['taken']),
    resolved7: _int(j['resolved_7']),
    hasPhone: j['phone'] == true,
  );

  final String name;
  final bool onDuty;
  final int assigned;
  final int taken;
  final int resolved7;
  final bool hasPhone;
}

class ConsoleWaiting {
  const ConsoleWaiting({
    required this.id,
    required this.org,
    required this.subject,
    required this.status,
    this.orgId,
    this.profile,
    this.minutes = 0,
    this.late = false,
    this.escalated = false,
    this.takenBy,
  });

  factory ConsoleWaiting.fromJson(Map<String, dynamic> j) => ConsoleWaiting(
    id: '${j['id'] ?? ''}',
    org: _text(j['org']) ?? '',
    orgId: _text(j['org_id']),
    profile: _text(j['profile']),
    subject: _text(j['subject']) ?? 'autre',
    status: _text(j['status']) ?? 'open',
    minutes: _int(j['minutes']),
    late: j['late'] == true,
    escalated: j['escalated'] == true,
    takenBy: _text(j['taken_by']),
  );

  final String id;
  final String org;
  final String? orgId;
  final String? profile;
  final String subject;
  final String status;
  final int minutes;
  final bool late;
  final bool escalated;
  final String? takenBy;
}

class HelpConsole {
  const HelpConsole({
    this.open = 0,
    this.avgMinutes,
    this.resolved7 = 0,
    this.up = 0,
    this.down = 0,
    this.inHours = true,
    this.hours = const HelpHours(),
    this.whatsapp = 'off',
    this.template = '',
    this.whatsappError,
    this.trainers = const [],
    this.waiting = const [],
  });

  factory HelpConsole.fromJson(Map<String, dynamic> j) {
    final wa = j['whatsapp'] is Map ? j['whatsapp'] as Map : const {};
    return HelpConsole(
      open: _int(j['open']),
      avgMinutes: j['avg_minutes'] == null ? null : _int(j['avg_minutes']),
      resolved7: _int(j['resolved_7']),
      up: _int(j['up']),
      down: _int(j['down']),
      inHours: j['in_hours'] != false,
      hours: HelpHours.fromJson(j['hours']),
      whatsapp: _text(wa['state']) ?? 'off',
      template: _text(wa['template']) ?? '',
      whatsappError: _text(wa['last_error']),
      trainers: [
        for (final t
            in (j['trainers'] is List ? j['trainers'] as List : const []))
          if (t is Map) ConsoleTrainer.fromJson(Map<String, dynamic>.from(t)),
      ],
      waiting: [
        for (final w
            in (j['waiting'] is List ? j['waiting'] as List : const []))
          if (w is Map) ConsoleWaiting.fromJson(Map<String, dynamic>.from(w)),
      ],
    );
  }

  final int open;
  final int? avgMinutes;
  final int resolved7;
  final int up;
  final int down;
  final bool inHours;
  final HelpHours hours;

  /// 'off' (no template set) | 'template' (Meta refused it) | 'failing' |
  /// 'waiting' (nothing carried for 5 minutes) | 'on' | 'unknown'.
  final String whatsapp;
  final String template;
  final String? whatsappError;
  final List<ConsoleTrainer> trainers;
  final List<ConsoleWaiting> waiting;

  /// The share of 👍 among the rated (30 days), or null with none.
  int? get upPercent =>
      up + down == 0 ? null : (100 * up / (up + down)).round();
  List<ConsoleWaiting> get late => waiting.where((w) => w.late).toList();
}

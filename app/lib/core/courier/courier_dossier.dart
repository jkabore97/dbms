import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Becoming a courier (112): the dossier a person fills, one step at a
/// time, and the platform's review of it. Every rule is the server's — which
/// steps are open, what a step needs, who may see a photo — so this file
/// carries the calls and reads the answers.
///
/// The photos never go through Postgres: they go to the uploads Worker
/// (workers/uploads, « A courier's dossier »), under their own private
/// prefix, and come back only to a platform admin ([CourierFiles]).

/// The dossier's steps, in the order the flow asks them.
const courierSteps = ['zone', 'hours', 'vehicle', 'selfie', 'id', 'phone', 'charter'];

/// The vehicles that carry a make, a model, a colour and a plate.
const motorVehicles = {'moto', 'voiture', 'tricycle'};

/// The vehicles whose licence the dossier asks for (optional unless the
/// platform's « Permis de conduire obligatoire » is on).
const licenceVehicles = {'moto', 'voiture'};

/// What the platform asks, as it has set it (courier_rules()).
class CourierRules {
  const CourierRules({
    this.licenceRequired = false,
    this.phoneVerified = false,
    this.mobileMoney = false,
    this.charterVersion = 1,
  });

  /// A moto or a car must show its licence.
  final bool licenceRequired;

  /// The WhatsApp number must be proved (109's code) before sending.
  final bool phoneVerified;

  /// RULE M: a payout mobile-money number is asked only while the platform
  /// takes mobile payment (076's wave_checkout). Otherwise: cash.
  final bool mobileMoney;

  /// The charter's current version — the one an applicant accepts.
  final int charterVersion;

  factory CourierRules.fromJson(Map<String, dynamic>? j) => j == null
      ? const CourierRules()
      : CourierRules(
          licenceRequired: j['licence_required'] == true,
          phoneVerified: j['phone_verified'] == true,
          mobileMoney: j['mobile_money'] == true,
          charterVersion: (j['charter_version'] as num?)?.toInt() ?? 1,
        );
}

/// One line of the dossier's history: sent, sent back, approved…
class CourierEvent {
  const CourierEvent({required this.at, required this.kind, this.reason, this.note, this.steps = const []});

  final DateTime at;

  /// 'sent', 'resent', 'refused', 'photo', 'approved', 'reopened'.
  final String kind;
  final String? reason;
  final String? note;
  final List<String> steps;

  factory CourierEvent.fromJson(Map<String, dynamic> j) => CourierEvent(
        at: DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now(),
        kind: '${j['kind'] ?? ''}',
        reason: j['reason'] as String?,
        note: j['note'] as String?,
        steps: _strings(j['steps']),
      );
}

/// Why a dossier was sent back, with what to redo.
class CourierRefusal {
  const CourierRefusal({required this.reason, this.note, this.steps = const []});

  /// 'blurry', 'unreadable', 'face', 'missing', 'other', 'new_selfie',
  /// 'new_id'.
  final String reason;
  final String? note;
  final List<String> steps;

  bool get isNewPhoto => reason == 'new_selfie' || reason == 'new_id';

  static CourierRefusal? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return CourierRefusal(
      reason: '${j['reason'] ?? 'other'}',
      note: j['note'] as String?,
      steps: _strings(j['steps']),
    );
  }
}

/// A dossier: the applicant's own read (my_courier_application) or the
/// platform's (platform_courier_application, which adds the photo keys).
class CourierDossier {
  const CourierDossier({
    this.userId,
    this.name,
    this.status,
    this.courierStatus,
    this.city,
    this.zones = const [],
    this.days = const [],
    this.hoursFrom,
    this.hoursTo,
    this.vehicle,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColour,
    this.vehiclePlate,
    this.idKind,
    this.phone,
    this.phoneVerified = false,
    this.verifiedPhone,
    this.payoutNumber,
    this.charterVersion,
    this.charterAt,
    this.files = const {},
    this.photos = const {},
    this.openSteps = const [],
    this.refusal,
    this.timeline = const [],
    this.sentAt,
    this.decidedAt,
    this.rules = const CourierRules(),
  });

  final String? userId;
  final String? name;

  /// null (none yet), 'draft', 'pending', 'refused', 'approved'.
  final String? status;

  /// The courier's own state (056): null, 'pending', 'approved',
  /// 'suspended'. Approved here means approved, whatever the dossier says.
  final String? courierStatus;
  final String? city;
  final List<String> zones;
  final List<String> days;
  final String? hoursFrom;
  final String? hoursTo;
  final String? vehicle;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColour;
  final String? vehiclePlate;
  final String? idKind;
  final String? phone;

  /// The platform's read: the dossier's number is the account's proved one.
  final bool phoneVerified;

  /// The applicant's read: the account's number proved on WhatsApp, if any.
  final String? verifiedPhone;
  final String? payoutNumber;
  final int? charterVersion;
  final DateTime? charterAt;

  /// Which photos are there (the applicant's read: never a key).
  final Map<String, bool> files;

  /// The photo keys (the platform's read only), part → key.
  final Map<String, String> photos;

  /// The steps the applicant may fill now.
  final List<String> openSteps;
  final CourierRefusal? refusal;
  final List<CourierEvent> timeline;
  final DateTime? sentAt;
  final DateTime? decidedAt;
  final CourierRules rules;

  /// Approved and not suspended since (a suspension is the courier row's).
  bool get isApprovedCourier =>
      courierStatus == 'approved' || (status == 'approved' && courierStatus != 'suspended');
  bool get isSuspended => courierStatus == 'suspended';
  bool get isMotor => motorVehicles.contains(vehicle);
  bool get asksLicence => licenceVehicles.contains(vehicle);
  bool hasFile(String part) => files[part] == true || photos[part] != null;

  /// Whether a step's answers are all there — what « Suivant » waits for.
  bool stepDone(String step) => switch (step) {
        'zone' => (city ?? '').trim().isNotEmpty && zones.isNotEmpty,
        'hours' => days.isNotEmpty && hoursFrom != null && hoursTo != null,
        'vehicle' => vehicle != null && (!isMotor || (vehiclePlate ?? '').isNotEmpty),
        'selfie' => hasFile('selfie'),
        'id' => idKind != null &&
            hasFile('id_front') &&
            hasFile('id_back') &&
            (!asksLicence || !rules.licenceRequired || hasFile('licence')),
        'phone' => (phone ?? '').isNotEmpty &&
            (!rules.phoneVerified || (verifiedPhone != null && phone == verifiedPhone)),
        'charter' => charterVersion == rules.charterVersion,
        _ => false,
      };

  factory CourierDossier.fromJson(Map<String, dynamic> j) {
    final files = <String, bool>{};
    final f = j['files'];
    if (f is Map) {
      for (final e in f.entries) {
        files['${e.key}'] = e.value == true;
      }
    }
    final photos = <String, String>{};
    final p = j['photos'];
    if (p is Map) {
      for (final e in p.entries) {
        if (e.value is String) photos['${e.key}'] = e.value as String;
      }
    }
    final t = j['timeline'];
    return CourierDossier(
      userId: j['user_id'] as String?,
      name: j['name'] as String?,
      status: j['status'] as String?,
      courierStatus: j['courier_status'] as String?,
      city: j['city'] as String?,
      zones: _strings(j['zones']),
      days: _strings(j['days']),
      hoursFrom: j['hours_from'] as String?,
      hoursTo: j['hours_to'] as String?,
      vehicle: j['vehicle'] as String?,
      vehicleMake: j['vehicle_make'] as String?,
      vehicleModel: j['vehicle_model'] as String?,
      vehicleColour: j['vehicle_colour'] as String?,
      vehiclePlate: j['vehicle_plate'] as String?,
      idKind: j['id_kind'] as String?,
      phone: j['phone'] as String?,
      phoneVerified: j['phone_verified'] == true,
      verifiedPhone: j['verified_phone'] as String?,
      payoutNumber: j['payout_number'] as String?,
      charterVersion: (j['charter_version'] as num?)?.toInt(),
      charterAt: DateTime.tryParse('${j['charter_at']}')?.toLocal(),
      files: files,
      photos: photos,
      openSteps: _strings(j['open_steps']),
      refusal: CourierRefusal.fromJson(j['refusal']),
      timeline: t is List
          ? [for (final e in t) if (e is Map) CourierEvent.fromJson(Map<String, dynamic>.from(e))]
          : const [],
      sentAt: DateTime.tryParse('${j['sent_at']}')?.toLocal(),
      decidedAt: DateTime.tryParse('${j['decided_at']}')?.toLocal(),
      rules: CourierRules.fromJson(j['rules'] is Map ? Map<String, dynamic>.from(j['rules'] as Map) : null),
    );
  }
}

/// One row of « Livreurs à valider » (platform_courier_applications).
class CourierApplicationRow {
  const CourierApplicationRow({
    required this.userId,
    required this.name,
    required this.status,
    this.courierStatus,
    this.city,
    this.vehicle,
    this.sentAt,
    this.decidedAt,
    this.refusalReason,
  });

  final String userId;
  final String name;

  /// 'pending', 'refused', 'approved' or 'suspended'.
  final String status;
  final String? courierStatus;
  final String? city;
  final String? vehicle;
  final DateTime? sentAt;
  final DateTime? decidedAt;
  final String? refusalReason;

  factory CourierApplicationRow.fromRow(Map<String, dynamic> r) => CourierApplicationRow(
        userId: '${r['user_id']}',
        name: '${r['name'] ?? ''}',
        status: '${r['status'] ?? 'pending'}',
        courierStatus: r['courier_status'] as String?,
        city: r['city'] as String?,
        vehicle: r['vehicle'] as String?,
        sentAt: DateTime.tryParse('${r['sent_at']}')?.toLocal(),
        decidedAt: DateTime.tryParse('${r['decided_at']}')?.toLocal(),
        refusalReason: r['refusal_reason'] as String?,
      );
}

/// The dossier's calls, for the applicant and for the platform.
class CourierDossierRepository {
  CourierDossierRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  SupabaseClient _require() {
    final c = _client;
    if (c == null) throw StateError("L'espace livreur a besoin d'une connexion.");
    return c;
  }

  static CourierDossier _read(Object? v) =>
      CourierDossier.fromJson(Map<String, dynamic>.from(v as Map));

  /// The caller's own dossier (or what an empty one needs to start).
  Future<CourierDossier> mine() async => _read(await _require().rpc('my_courier_application'));

  /// Saves one step's answers; the server checks them and answers the
  /// dossier as it now stands.
  Future<CourierDossier> save(String step, Map<String, Object?> answers) async =>
      _read(await _require().rpc('courier_application_save', params: {
        'p_step': step,
        'p_data': answers,
      }));

  /// « Envoyer ma demande ».
  Future<CourierDossier> send() async => _read(await _require().rpc('courier_application_send'));

  // The platform's side ------------------------------------------------

  Future<List<CourierApplicationRow>> applications() async {
    final rows = await _require().rpc('platform_courier_applications') as List<dynamic>;
    return [for (final r in rows) CourierApplicationRow.fromRow(Map<String, dynamic>.from(r as Map))];
  }

  Future<CourierDossier> dossier(String userId) async =>
      _read(await _require().rpc('platform_courier_application', params: {'p_user_id': userId}));

  /// 'approve'; 'refuse' with a [reason] and the [steps] to redo; or
  /// 'new_photo' with [reason] 'selfie' or 'id'. Returns the journal line,
  /// for « Annuler ».
  Future<String?> decide(String userId, String decision,
      {String? reason, List<String>? steps, String? note}) async {
    final id = await _require().rpc('platform_decide_courier_application', params: {
      'p_user_id': userId,
      'p_decision': decision,
      'p_reason': reason,
      'p_steps': steps,
      'p_note': note,
    });
    return id as String?;
  }

  /// « Annuler » a decision, through the journal (104's platform_undo).
  Future<void> undo(String actionId) async {
    await _require().rpc('platform_undo', params: {'p_action': actionId});
  }
}

/// The dossier's photos, through the uploads Worker's courier routes. The
/// Worker asks Postgres, as the caller, before every byte: the applicant
/// may send a photo for a step that is theirs to fill, and only a platform
/// admin gets one back. Nothing here is kept on the device.
class CourierFiles {
  CourierFiles(this._client, {String? url, http.Client? httpClient})
      : _url = _trim(url ?? const String.fromEnvironment('UPLOADS_URL')),
        _http = httpClient ?? http.Client();

  final SupabaseClient? _client;
  final String _url;
  final http.Client _http;

  static String _trim(String u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u;

  /// Whether photos can be sent at all in this build.
  bool get isConfigured => _client != null && _url.isNotEmpty;

  String _token() {
    final t = _client?.auth.currentSession?.accessToken;
    if (t == null) throw const CourierFileException("Connectez-vous d'abord.");
    return t;
  }

  /// Sends one photo of [part] ('selfie', 'id_front', 'id_back', 'licence').
  Future<void> upload(String part, Uint8List bytes, String contentType) async {
    if (!isConfigured) {
      throw const CourierFileException(
          "L'envoi de photos n'est pas configuré dans cette version de l'application.");
    }
    final r = await _http.post(
      Uri.parse('$_url/v1/courier/uploads?part=$part'),
      headers: {'Authorization': 'Bearer ${_token()}', 'Content-Type': contentType},
      body: bytes,
    );
    if (r.statusCode != 201) throw CourierFileException(_message(r));
  }

  /// A dossier photo, for the platform's review. Never cached.
  Future<Uint8List> photo(String key) async {
    final r = await _http.get(
      Uri.parse('$_url/v1/courier/objects/${Uri.encodeComponent(key)}'),
      headers: {'Authorization': 'Bearer ${_token()}'},
    );
    if (r.statusCode != 200) throw CourierFileException(_message(r));
    return r.bodyBytes;
  }

  /// Deletes what is due (30 days after a refusal, a replaced photo…):
  /// everything due for the platform, the caller's own for an applicant.
  /// Best effort, never in the way: a page asks it as it opens.
  Future<void> purge() async {
    if (!isConfigured || _client?.auth.currentSession == null) return;
    try {
      await _http.post(Uri.parse('$_url/v1/courier/purge'),
          headers: {'Authorization': 'Bearer ${_token()}'});
    } catch (_) {
      // The next opening asks again.
    }
  }

  /// The Worker's sentence (French, for the person), or a plain one.
  static String _message(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return "La photo n'a pas pu être envoyée. Vérifiez le réseau.";
  }
}

class CourierFileException implements Exception {
  const CourierFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

List<String> _strings(Object? v) =>
    v is List ? [for (final e in v) if (e != null) '$e'] : const [];

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart' show isSchemaOutOfDate, isOffline;

/// Mara's documents a person accepts (142, batch 147): the Conditions
/// d'utilisation, the Politique de confidentialité, the seller's
/// commitments (before a business is created) and the courier's charter.
abstract final class TermsDoc {
  static const terms = 'terms';
  static const privacy = 'privacy';
  static const seller = 'seller';
  static const courier = 'courier';
  static const all = [terms, privacy, seller, courier];
}

/// One document as the server says it for this person.
class TermsDocState {
  const TermsDocState({required this.current, this.accepted, this.acceptedAt});

  /// The version to accept now.
  final int current;

  /// The latest version this person accepted, or null (never).
  final int? accepted;
  final DateTime? acceptedAt;

  bool get pending => (accepted ?? 0) < current;

  factory TermsDocState.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    return TermsDocState(
      current: (j['current'] as num?)?.toInt() ?? 1,
      accepted: (j['accepted'] as num?)?.toInt(),
      acceptedAt: DateTime.tryParse('${j['accepted_at'] ?? ''}')?.toLocal(),
    );
  }
}

/// What my_terms_state() says: each document, and the « gate » — what the
/// app asks before anything else.
class TermsState {
  const TermsState({
    this.installed = true,
    this.documents = const {},
    this.gate = const [],
    this.changed = false,
    this.owner = false,
    this.courier = false,
    this.date,
    this.changes,
    this.changesEn,
  });

  /// A database before 142: nothing to ask, nothing blocked.
  static const none = TermsState(installed: false);

  /// False before 142 (no my_terms_state): every question is skipped.
  final bool installed;
  final Map<String, TermsDocState> documents;

  /// To accept now, before anything else: the terms and the privacy policy
  /// for everyone, the seller's commitments for someone who owns a
  /// business, the courier's charter for an approved courier.
  final List<String> gate;

  /// An earlier version of the terms was accepted: « Nos conditions ont
  /// changé », with [changes].
  final bool changed;
  final bool owner;
  final bool courier;

  /// The current version's date (« 2026-10-14 »).
  final String? date;

  /// « What changed », in French and in English.
  final String? changes;
  final String? changesEn;

  /// Whether [doc] is still to accept (false before 142).
  bool needs(String doc) => installed && (documents[doc]?.pending ?? false);

  /// The version of [doc] to accept.
  int version(String doc) => documents[doc]?.current ?? 1;

  String? changesIn(String language) {
    final en = changesEn?.trim();
    final fr = changes?.trim();
    if (language == 'en' && en != null && en.isNotEmpty) return en;
    return fr == null || fr.isEmpty ? null : fr;
  }

  factory TermsState.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    final docs = j['documents'] is Map ? j['documents'] as Map : const {};
    final gate = j['gate'] is List ? j['gate'] as List : const [];
    String? text(Object? v) {
      final s = v is String ? v.trim() : '';
      return s.isEmpty ? null : s;
    }

    return TermsState(
      documents: {
        for (final d in TermsDoc.all)
          if (docs[d] != null) d: TermsDocState.fromJson(docs[d]),
      },
      gate: [for (final d in gate) if (TermsDoc.all.contains(d)) d as String],
      changed: j['changed'] == true,
      owner: j['owner'] == true,
      courier: j['courier'] == true,
      date: text(j['date']),
      changes: text(j['changes']),
      changesEn: text(j['changes_en']),
    );
  }
}

/// One acceptance, on a person's fiche in the command center.
class TermsAcceptance {
  const TermsAcceptance({
    required this.document,
    required this.version,
    required this.acceptedAt,
    this.platform,
    this.appVersion,
    this.current = false,
  });

  final String document;
  final int version;
  final DateTime acceptedAt;
  final String? platform;
  final String? appVersion;

  /// The version is (at least) the one asked now.
  final bool current;

  factory TermsAcceptance.fromJson(Map<String, dynamic> j) => TermsAcceptance(
        document: '${j['document']}',
        version: (j['version'] as num?)?.toInt() ?? 1,
        acceptedAt: DateTime.tryParse('${j['accepted_at']}')?.toLocal() ?? DateTime(1970),
        platform: j['platform'] as String?,
        appVersion: j['app_version'] as String?,
        current: j['current'] == true,
      );
}

/// The platform's view: each document's version, since when, until when an
/// existing account is let through, and how many accepted it.
class TermsBoardDoc {
  const TermsBoardDoc({required this.version, this.since, this.graceUntil, this.accepted = 0});

  final int version;
  final DateTime? since;
  final DateTime? graceUntil;
  final int accepted;

  factory TermsBoardDoc.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    return TermsBoardDoc(
      version: (j['version'] as num?)?.toInt() ?? 1,
      since: DateTime.tryParse('${j['since'] ?? ''}')?.toLocal(),
      graceUntil: DateTime.tryParse('${j['grace_until'] ?? ''}')?.toLocal(),
      accepted: (j['accepted'] as num?)?.toInt() ?? 0,
    );
  }
}

class TermsBoard {
  const TermsBoard({this.documents = const {}, this.people = 0, this.date, this.changes, this.changesEn});

  final Map<String, TermsBoardDoc> documents;
  final int people;
  final String? date;
  final String? changes;
  final String? changesEn;

  factory TermsBoard.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    final docs = j['documents'] is Map ? j['documents'] as Map : const {};
    return TermsBoard(
      documents: {for (final d in TermsDoc.all) d: TermsBoardDoc.fromJson(docs[d])},
      people: (j['people'] as num?)?.toInt() ?? 0,
      date: j['date'] as String?,
      changes: j['changes'] as String?,
      changesEn: j['changes_en'] as String?,
    );
  }
}

/// The server's side (142), apart so a test can stand in for it.
abstract class TermsApi {
  /// my_terms_state(); [TermsState.none] on a database before 142.
  Future<TermsState> state();

  /// accept_terms(); the state after.
  Future<TermsState> accept(String doc, int version, {String? platform, String? appVersion});

  /// The command center's (platform admins only, checked on the server).
  Future<TermsBoard?> board();
  Future<List<TermsAcceptance>?> of(String userId);
  Future<TermsBoard> bump(List<String> docs,
      {required String changes, String? changesEn, int graceDays = 14});
}

class SupabaseTermsApi implements TermsApi {
  SupabaseTermsApi(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _c {
    final c = _client;
    if (c == null) throw StateError('Pas de serveur : cette version a été construite sans Supabase.');
    return c;
  }

  @override
  Future<TermsState> state() async {
    if (_client == null) return TermsState.none;
    try {
      return TermsState.fromJson(await _c.rpc('my_terms_state'));
    } catch (e) {
      if (isSchemaOutOfDate(e)) return TermsState.none;
      rethrow;
    }
  }

  @override
  Future<TermsState> accept(String doc, int version, {String? platform, String? appVersion}) async =>
      TermsState.fromJson(await _c.rpc('accept_terms', params: {
        'p_doc': doc,
        'p_version': version,
        'p_platform': platform,
        'p_app_version': appVersion,
      }));

  @override
  Future<TermsBoard?> board() async {
    try {
      return TermsBoard.fromJson(await _c.rpc('platform_terms_board'));
    } catch (e) {
      if (isSchemaOutOfDate(e)) return null;
      rethrow;
    }
  }

  @override
  Future<List<TermsAcceptance>?> of(String userId) async {
    try {
      final rows = await _c.rpc('platform_terms_of', params: {'p_user': userId});
      return [
        for (final r in rows is List ? rows : const [])
          if (r is Map) TermsAcceptance.fromJson(Map<String, dynamic>.from(r)),
      ];
    } catch (e) {
      if (isSchemaOutOfDate(e)) return null;
      rethrow;
    }
  }

  @override
  Future<TermsBoard> bump(List<String> docs,
          {required String changes, String? changesEn, int graceDays = 14}) async =>
      TermsBoard.fromJson(await _c.rpc('platform_terms_bump', params: {
        'p_docs': docs,
        'p_changes': changes,
        'p_changes_en': changesEn,
        'p_grace_days': graceDays,
      }));
}

/// What this person still has to accept, for the whole app: the gate
/// (terms_gate.dart) draws itself from it, the creation of a business and
/// the courier's charter ask it.
///
/// Fails open on purpose: a database before 142, no signal, or a server
/// that does not answer show nothing and block nothing — the server
/// refuses an order, a creation or an application itself (142), so the
/// gate is the courtesy and the server the wall.
class TermsController extends ChangeNotifier {
  TermsController({
    required this.api,
    this.platform,
    this.appVersion,
    this.recheckEvery = const Duration(minutes: 5),
    this.holdFor = Duration.zero,
  });

  final TermsApi api;

  /// How long the app under the gate waits, at most, for the first answer
  /// about a person (the supervisor's 147 review): a short loading state
  /// instead of the business screens flashing before the gate. Past it, or
  /// on any failure, the app shows (fails open). Zero: never held (tests).
  final Duration holdFor;

  /// 'web', 'android' or 'ios', and the app's version: kept with each
  /// acceptance.
  final String? platform;
  final String? appVersion;

  /// How often an open app asks again (a new version, 142's bump).
  final Duration recheckEvery;

  /// The one the app built (main.dart), for the few places with no
  /// context — an order the server refused for want of the terms.
  static TermsController? current;

  String? _userId;
  bool _active = false;
  TermsState? _state;
  DateTime? _askedAt;
  Future<void>? _asking;
  bool _disposed = false;

  /// Bumped by every acceptance and every change of person: an answer to a
  /// question asked before it is stale and never overwrites what came after
  /// (else a refresh in flight when « Continuer » was tapped brought the
  /// gate back over the app it had just left).
  int _generation = 0;

  /// An acceptance the server could not take for want of a working
  /// server (no signal, a 5xx, a function missing) — not a refusal: the
  /// gate steps aside until the next answer about this person (fails
  /// open; the server still refuses an order, a creation, an application).
  bool _waived = false;

  /// [holdFor] running for this person: no answer yet.
  bool _holding = false;
  Timer? _holdTimer;

  TermsState? get state => _state;
  String? get userId => _userId;

  /// Somebody is signed in and past the gates (code, second step).
  bool get active => _active;

  /// The first answer about this person is awaited, briefly ([holdFor]):
  /// the gate draws a loading state over the app meanwhile.
  bool get holding => _active && _holding && _state == null;

  /// What the gate asks now; empty when nothing (or before it is known).
  List<String> get gate => _active && !_waived ? (_state?.gate ?? const []) : const [];

  /// Whether [doc] is still to accept — false while unknown.
  bool needs(String doc) => _state?.needs(doc) ?? false;

  /// Follows the session: [userId] is the person signed in and past the
  /// gates, null otherwise (signed out, at the code screen). A new person
  /// is asked about; the same one again only once [recheckEvery] has
  /// passed (or [force]).
  Future<void> track(String? userId, {bool force = false}) {
    if (userId == null) {
      if (_active) {
        _active = false;
        _notify();
      }
      return Future.value();
    }
    if (userId != _userId) {
      _userId = userId;
      _state = null;
      _askedAt = null;
      _waived = false;
      _generation++;
      _startHold();
    }
    if (!_active) {
      _active = true;
      _notify();
    }
    final asked = _askedAt;
    if (!force && asked != null && DateTime.now().difference(asked) < recheckEvery) {
      return Future.value();
    }
    return refresh();
  }

  /// Signed out: everything forgotten.
  void clear() {
    _userId = null;
    _active = false;
    _state = null;
    _askedAt = null;
    _waived = false;
    _generation++;
    _endHold();
    _notify();
  }

  void _startHold() {
    _endHold();
    if (holdFor <= Duration.zero) return;
    _holding = true;
    _holdTimer = Timer(holdFor, () {
      _holding = false;
      _holdTimer = null;
      _notify();
    });
  }

  void _endHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holding = false;
  }

  /// Asks the server again (one question at a time). An answer about a
  /// person signed out meanwhile, or older than an acceptance made since,
  /// is dropped — and the current person is asked in turn.
  Future<void> refresh() => _asking ??= () async {
        final who = _userId;
        final generation = _generation;
        var stale = false;
        try {
          // Never a question left hanging: one that does not come back
          // would hold every later one (fails open meanwhile).
          final s = await api.state().timeout(const Duration(seconds: 20));
          if (who == _userId && generation == _generation) {
            _state = s;
            _askedAt = DateTime.now();
            _waived = false;
          } else {
            stale = true;
          }
        } catch (e) {
          // No signal, or a refusal we cannot read: what we knew stays, and
          // nothing is blocked for it.
          if (who == _userId && !isOffline(e)) _askedAt = DateTime.now();
        } finally {
          _asking = null;
          if (who == _userId) _endHold();
          _notify();
        }
        // Somebody else signed in, or something was accepted, while the old
        // question was out: asked again, so the answer is today's.
        if (stale && _userId != null && !_disposed) {
          await refresh();
        }
      }();

  /// Accepts [docs] at their current versions, in order. Throws what the
  /// server said: a refusal (a version changed meanwhile) keeps the gate
  /// and reads the state again; a server that could not answer (no
  /// signal, a 5xx, a function missing) lets the person through until the
  /// next answer — never a gate nobody can pass.
  Future<void> accept(Iterable<String> docs) async {
    final s = _state;
    if (s == null || !s.installed) return;
    final who = _userId;
    _generation++;
    try {
      for (final d in docs) {
        if (!s.documents.containsKey(d)) continue;
        final after = await api.accept(d, (_state ?? s).version(d), platform: platform, appVersion: appVersion);
        if (who != _userId) return;
        _state = after;
      }
      _generation++;
      _askedAt = DateTime.now();
      _waived = false;
    } catch (e) {
      if (who == _userId) {
        if (isAcceptRefusal(e)) {
          unawaited(refresh());
        } else {
          _waived = true;
        }
      }
      rethrow;
    } finally {
      _notify();
    }
  }

  /// accept_terms() said no (a raise of 142's: a version changed, an
  /// unknown document, nobody signed in) — as opposed to a server that did
  /// not answer.
  static bool isAcceptRefusal(Object e) =>
      e is PostgrestException &&
      (e.code == 'P0001' ||
          e.message.startsWith('Ces conditions ont changé entre-temps') ||
          e.message == 'Document inconnu.' ||
          e.message.startsWith('Connectez-vous pour accepter'));

  /// [doc] accepted if it is still to accept; nothing otherwise.
  Future<void> ensure(String doc) => needs(doc) ? accept([doc]) : Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _endHold();
    if (identical(current, this)) current = null;
    super.dispose();
  }

  /// A refusal of the server for want of an acceptance (142): the gate is
  /// asked again so it shows.
  static bool isTermsRefusal(String message) =>
      message.startsWith('Acceptez d\'abord les Conditions d\'utilisation') ||
      message.startsWith('Acceptez d\'abord les engagements du vendeur') ||
      message.startsWith('Acceptez d\'abord la charte du livreur');

  /// [error] is the server refusing for want of an acceptance.
  static bool refusedFor(Object error) =>
      error is PostgrestException && isTermsRefusal(error.message);

  /// The platform this build runs on, as 142 keeps it.
  static String? platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }
}

/// The app's [TermsController], for every screen under it.
class TermsScope extends InheritedNotifier<TermsController> {
  const TermsScope({super.key, required TermsController controller, required super.child})
      : super(notifier: controller);

  static TermsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TermsScope>()?.notifier;

  /// Without subscribing (initState, a callback).
  static TermsController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TermsScope>()?.notifier;
}

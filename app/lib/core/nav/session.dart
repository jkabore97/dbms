import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState, User;

import '../access/org_access.dart';
import '../access/plan_terms.dart';
import '../cauris/feature_states.dart';
import '../accounting/accounting_repository.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_repository.dart';
import '../auth/models.dart';
import '../auth/pin_codec.dart';
import '../auth/two_step.dart';
import '../db/local_db.dart';
import '../sync/sync_service.dart';

/// Where the app is between launching and landing in a business.
///
/// These were the phases of `AppRoot`'s state machine, and the questions they
/// answer have not changed: who is this, and whose books may they open. What
/// changed is who reads the answer — the router does, and turns each phase
/// into an address a person can go back to.
enum SessionPhase {
  booting,
  signedOut,
  locked,
  choosingPin,
  resolving,

  /// A platform admin whose token has not passed the second step (077).
  /// The server refuses them everywhere until it has; the app asks.
  twoStep,
  noOrg,
  picking,
  ready,
}

/// Who is signed in, which businesses they may open, and which one is open.
///
/// This used to live inside `AppRoot` as widget state, and every transition was
/// a `setState`. That is exactly why the back button could not be trusted: a
/// `setState` is not a page, so moving from the business picker into a business
/// left no trace in history, and pressing back from inside a business went back
/// past the app itself rather than to the picker.
///
/// Holding it here instead lets the router listen. Each phase now maps to a
/// route, so the browser's back and forward buttons, a refresh and a bookmark
/// all mean what they say.
///
/// Nothing here decides *which* org a person may open. `my_orgs()` does, server
/// side, behind RLS — the client cannot ask for an org it was not granted, and
/// putting an org id in a URL does not change that. Opening `/o/<some id>` for
/// a business you are not a member of resolves to nothing and lands you back on
/// the picker, because the id is looked up in the list the server returned.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.db,
    required this.auth,
    required this.admin,
    required this.accounting,
    this.sync,
    this.twoStep,
    this.resolveTimeout = const Duration(seconds: 12),
  }) {
    // Google hands the session back on its own schedule — on Android, as
    // the browser returns to the app — so the controller listens for it
    // rather than waiting on the button that started it.
    _authEvents = auth.onAuthStateChange?.listen((AuthState s) {
      if (s.event == AuthChangeEvent.signedIn) unawaited(adoptGoogleSession());
    }, onError: (_) {});
  }

  StreamSubscription<AuthState>? _authEvents;

  final LocalDb db;
  final AuthRepository auth;
  final AdminRepository admin;
  final AccountingRepository accounting;
  final SyncService? sync;

  /// The platform admin's second step. Null in tests and in a build with no
  /// server: nobody is asked.
  final TwoStep? twoStep;

  /// At the code screen: whether an authenticator app is already enrolled
  /// (ask its code) or not yet (show how to add one).
  bool _twoStepEnrolled = false;
  bool get twoStepEnrolled => _twoStepEnrolled;

  /// How long a single network step of a resolve may stall before it is
  /// treated as a dead connection. Long enough that a genuinely slow reply
  /// still lands, short enough that a stalled socket does not hang the app
  /// open-endedly. The resolve makes up to three such calls, each bounded
  /// independently. Injectable so a test can prove the fallback without
  /// waiting out the real timeout.
  final Duration resolveTimeout;

  SessionPhase _phase = SessionPhase.booting;
  SessionPhase get phase => _phase;

  LocalIdentity? _identity;
  LocalIdentity? get identity => _identity;

  List<OrgSummary> _orgs = const [];
  List<OrgSummary> get orgs => _orgs;

  /// The business the router last settled on. Kept so a redirect can send
  /// somebody straight back to it, and so `/` knows where "home" is.
  ///
  /// Persisted on the device under [_lastOrgKey], because a value that lives
  /// only in memory forgets itself on every reload: a person with several
  /// businesses was dumped on the picker each time the page refreshed —
  /// sometimes before the org list had even arrived, which showed a picker
  /// with nothing to pick. The device remembers instead, the same way it
  /// remembers the language.
  String? _lastOrgId;
  String? get lastOrgId => _lastOrgId;

  static const _lastOrgKey = 'last_org_id';

  /// What each opened business lets this person see and edit — the owner's
  /// dial from 031, fetched once per business per session. Screens read it
  /// synchronously; until the fetch lands they get the same defaults the
  /// server applies to a business that never touched the dial.
  final Map<String, OrgAccess> _access = {};

  OrgAccess accessFor(String? orgId) {
    if (orgId == null) return OrgAccess.allEdit;
    final loaded = _access[orgId];
    if (loaded != null) return loaded;
    final org = orgById(orgId);
    if (org == null) return OrgAccess.allEdit;
    // The plan lock is known before any fetch — from the cached org row and
    // the default terms — so what screens see first is what the load will
    // confirm, and an owner's load emits nothing (see _loadAccess).
    final locked = _lockedFor(org);
    final hidden = _hiddenFor(org);
    if (org.isAdmin) {
      return locked.isEmpty && hidden.isEmpty
          ? OrgAccess.allEdit
          : OrgAccess.admin(proLocked: locked, hidden: hidden);
    }
    return OrgAccess.forTier(const {}, proLocked: locked, hidden: hidden);
  }

  /// What Mara's switchboard hid for this business (104), as its feature
  /// states said — for everyone in it, Mara's own people included (they
  /// see what the business sees). Nothing until they are read, and nothing
  /// on a business no rule touches.
  Set<String> _hiddenFor(OrgSummary org) =>
      _features[org.id]?.hidden ?? _hiddenKept[org.id] ?? const <String>{};

  /// The hidden set as the device last heard it, per business: an offline
  /// cold start hides what the server last said was hidden, rather than
  /// drawing a tool the server would refuse. Rewritten on every answer.
  final Map<String, Set<String>> _hiddenKept = {};

  static String _hiddenKey(String orgId) => 'hidden_features:$orgId';

  Future<Set<String>?> _readHidden(String orgId) async {
    try {
      final v = await db.readPref(_hiddenKey(orgId));
      if (v == null || v.isEmpty) return null;
      return v.split(',').where((k) => k.isNotEmpty).toSet();
    } catch (_) {
      return null;
    }
  }

  Future<void> _keepHidden(String orgId, Set<String> hidden) async {
    try {
      await db.writePref(
          _hiddenKey(orgId), hidden.isEmpty ? null : (hidden.toList()..sort()).join(','));
    } catch (_) {}
  }

  /// Which tools the plan locks for this business: none on Pro, none for
  /// the platform admin, the Pro list otherwise. The server decides the
  /// same way (pro_locked); this only says where to draw the badge.
  Set<String> _lockedFor(OrgSummary org) {
    final states = _features[org.id];
    if (org.isPro || _isPlatformAdmin || (states?.isPro ?? false)) {
      return const <String>{};
    }
    // A tool unlocked with cauris (085) is open like Pro, for its 30 days.
    return _terms.proFeatures.toSet().difference(states?.unlocked ?? const {});
  }

  /// Each opened business's cauris prices, unlocks and Basic path (085).
  final Map<String, FeatureStates> _features = {};

  FeatureStates? featuresFor(String? orgId) =>
      orgId == null ? null : _features[orgId];

  /// After cauris were spent: read the business's tools again, so its
  /// badges and its gates follow at once.
  Future<void> reloadFeatures(String orgId) async {
    final org = orgById(orgId);
    if (org == null) return;
    await _loadAccess(org);
    _emit();
  }

  /// The line between Kaj and Kaj Pro (066), fetched once per session. The
  /// defaults are what 066 seeds, so a build with no signal badges the same
  /// tools it would online.
  PlanTerms _terms = PlanTerms.defaults;
  bool _termsLoaded = false;
  PlanTerms get planTerms => _terms;

  Future<void> _loadAccess(OrgSummary org) async {
    // The plan's terms, the business's feature states and (for a team
    // member) the owner's dial do not depend on one another: asked at once,
    // a business opens after one round trip instead of three.
    final terms = _termsLoaded
        ? null
        : admin.planTerms().then<Object?>((t) => t, onError: (Object _) => null);
    final states = admin
        .featureStates(org.id)
        .then<Object?>((s) => s, onError: (Object _) => null);
    final rules = org.isAdmin
        ? null
        : admin.featureRulesForTier(org.id, OrgAccess.tierOf(org.roles));
    if (terms != null) {
      final t = await terms;
      // Offline, or a database before 066: the defaults stand.
      if (t is PlanTerms) {
        _terms = t;
        _termsLoaded = true;
      }
    }
    // What the device last heard of the platform's hidden list, read beside
    // the server's questions and never waited for before the dial is set:
    // kept as soon as it lands, unless the server has answered by then.
    final kept = _features.containsKey(org.id) || _hiddenKept.containsKey(org.id)
        ? null
        : _readHidden(org.id).then((k) {
            if (k != null && !_features.containsKey(org.id)) {
              _hiddenKept.putIfAbsent(org.id, () => k);
            }
          });
    final s = await states;
    if (s is FeatureStates) {
      _features[org.id] = s;
      _hiddenKept[org.id] = s.hidden;
      unawaited(_keepHidden(org.id, s.hidden));
    }
    final dial = rules == null ? null : await rules;
    OrgAccess accessNow() {
      final locked = _lockedFor(org);
      final hidden = _hiddenFor(org);
      if (dial == null) {
        return locked.isEmpty && hidden.isEmpty
            ? OrgAccess.allEdit
            : OrgAccess.admin(proLocked: locked, hidden: hidden);
      }
      return OrgAccess.forTier(dial, proLocked: locked, hidden: hidden);
    }

    // Emit only if this changes what screens already see — an unchanged dial
    // (an admin, an untouched business, an offline fetch that came back empty)
    // must not fire a rebuild, because _loadAccess runs during the resolve and
    // open flows where a stray notify re-runs the router's redirect.
    void settle() {
      final next = accessNow();
      final changed = accessFor(org.id) != next;
      _access[org.id] = next;
      if (changed) _emit();
    }

    settle();
    // No answer (offline) and the device's copy still on its way: the dial
    // again once it lands, hiding what the server last said was hidden.
    if (kept != null && s is! FeatureStates) {
      await kept;
      if (!_disposed) settle();
    }
  }

  /// Where a reload was headed before a gate — the PIN screen, the sign-in —
  /// took over.
  ///
  /// Refreshing `/o/x/produits` on a device with a code used to land on the
  /// business home: the redirect sent the browser to `/code`, which replaced
  /// the address, and after unlocking there was nothing left to return to.
  /// The redirect now stashes the interrupted location here and takes it back
  /// once the phase allows it, so a refresh unlocks into the same page.
  ///
  /// No notifyListeners on either side: both calls happen inside the router's
  /// own redirect, which is already navigating.
  String? _returnTo;

  void stashReturnTo(String location) {
    _returnTo = location;
  }

  String? takeReturnTo() {
    final location = _returnTo;
    _returnTo = null;
    return location;
  }

  /// Set when the org list came from the device instead of the server. The
  /// home screen still works; the user simply has not been re-checked.
  bool _orgsFromCache = false;
  bool get orgsFromCache => _orgsFromCache;

  /// Whether this person may create businesses. Re-read from the server on
  /// every resolve and never cached on the device: it decides whether a menu
  /// entry is drawn, and a stale `true` would draw a button whose action the
  /// server refuses anyway.
  bool _isPlatformAdmin = false;
  bool get isPlatformAdmin => _isPlatformAdmin;

  String? _notice;
  String? get notice => _notice;

  bool _syncStarted = false;

  /// The business behind an id from the URL, or null if this person has no
  /// such business. Null is the whole defence against a typed or stale org id:
  /// the list is what the server returned, so an id that is not in it simply
  /// does not resolve.
  OrgSummary? orgById(String? id) {
    if (id == null) return null;
    for (final org in _orgs) {
      if (org.id == id) return org;
    }
    return null;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    unawaited(_authEvents?.cancel());
    super.dispose();
  }

  // ----------------------------------------------------------------
  // Boot
  // ----------------------------------------------------------------

  /// The device's cached org list, or an empty list if even that read fails.
  /// A broken local store must not leave the app wedged on a spinner: empty
  /// falls through to the waiting room, which carries a Retry.
  Future<List<OrgSummary>> _cachedOrgsSafe() async {
    try {
      return await db.cachedOrgs();
    } catch (_) {
      return const [];
    }
  }

  Future<void> boot() async {
    // Back from Google on the web: the page reloaded with the session
    // already in hand (Supabase.initialize swapped the code for it), and
    // nothing on the device knows who this is yet.
    try {
      if (await adoptGoogleSession()) return;
    } catch (_) {}
    try {
      // Bounded like the network steps: this is a local read and should be
      // instant, but a wedged web IndexedDB (a version-change blocked by another
      // open tab, say) can make it hang, and boot() is the one await standing
      // between a cold start and any screen at all. A timeout here means the app
      // always leaves the splash — worst case to sign-in — instead of freezing.
      final identity = await db.loadIdentity().timeout(resolveTimeout);

      if (identity == null) {
        _phase = SessionPhase.signedOut;
        _emit();
        return;
      }

      _identity = identity;

      // A live token means the server has vouched for this person within the
      // hour. Anything else and the device has to vouch for them itself.
      // The code is asked by the resolve, and only of somebody who belongs
      // to a business (108).
      if (auth.hasLiveSession) {
        await resolveOrgs();
        return;
      }

      // The device code protects businesses (108): a phone that holds no
      // business — a shopper's, a courier's — is never locked by it, even
      // with a code set before; the code stays on the device, unused.
      if (!await _holdsBusiness()) {
        await resolveOrgs();
        return;
      }
      if (identity.hasPin) {
        _phase = SessionPhase.locked;
      } else {
        // Signed in once, never set a code, and now the token is stale. There
        // is nothing on the device that can prove who this is, so ask the
        // server.
        _phase = SessionPhase.signedOut;
      }
      _emit();
    } catch (error) {
      // boot() is kicked off unawaited, so a throw here is unhandled and the
      // app freezes on the splash with the phase stuck at `booting`. The local
      // store is the only thing that can fail this early — a broken IndexedDB
      // on the web, most likely. Sign-in is the safe place to land: a page with
      // a way forward, not a spinner with none.
      _phase = SessionPhase.signedOut;
      _emit();
    }
  }

  // ----------------------------------------------------------------
  // Signing in
  // ----------------------------------------------------------------

  /// One sign-in at a time, per person: the password route calls this
  /// itself, and the auth event it raises must not start a second one.
  Future<void>? _signingIn;
  String? _signingInAs;

  Future<void> handleSignedIn(User user) {
    final inFlight = _signingIn;
    if (inFlight != null && _signingInAs == user.id) return inFlight;
    _signingInAs = user.id;
    final run = _handleSignedIn(user);
    _signingIn = run;
    return run.whenComplete(() {
      if (identical(_signingIn, run)) {
        _signingIn = null;
        _signingInAs = null;
      }
    });
  }

  // ----------------------------------------------------------------
  // Google
  // ----------------------------------------------------------------

  /// Set on the device before leaving for Google, so the session that comes
  /// back is known for what it is — and so a password sign-in, which raises
  /// the same auth event, is never taken for one. A web page reload wipes
  /// memory, hence the device. Stale after a quarter of an hour.
  static const _googleKey = 'google_pending';
  static const _googleFresh = Duration(minutes: 15);

  /// The page a gate interrupted ([stashReturnTo]) — a vitrine with its
  /// basket, say (F1) — kept on the device while Google has the person:
  /// on the web Google comes back as a reload, which wipes memory.
  static const _googleReturnKey = 'google_return_to';

  /// The sign-in screen's Google button, and the vitrine's.
  Future<void> signInWithGoogle() async {
    await db.writePref(_googleKey, DateTime.now().toIso8601String());
    await db.writePref(_googleReturnKey, _returnTo);
    try {
      await auth.signInWithGoogle();
    } catch (_) {
      await db.writePref(_googleKey, null);
      await db.writePref(_googleReturnKey, null);
      rethrow;
    }
  }

  /// What went wrong on the way back from Google, for the sign-in screen
  /// to say once. Taken, not read.
  String? _signInProblem;
  String? takeSignInProblem() {
    final p = _signInProblem;
    _signInProblem = null;
    return p;
  }

  /// Takes the session Google handed back and carries on exactly as a
  /// password sign-in does: the identity on the device, then the code to
  /// choose (or the one already there), then the businesses. Returns
  /// whether it did. Nothing happens without the device's note that this
  /// person went to Google, or while somebody is already inside.
  Future<bool> adoptGoogleSession() async {
    if (_signingIn != null) return false;
    String? since;
    try {
      since = await db.readPref(_googleKey);
    } catch (_) {}
    if (since == null) return false;
    final at = DateTime.tryParse(since);
    if (at == null || DateTime.now().difference(at) > _googleFresh) {
      await db.writePref(_googleKey, null);
      return false;
    }
    final user = auth.currentUser;
    // Not back yet (the browser is still open), or came back with nothing.
    if (user == null || !auth.hasLiveSession) return false;
    await db.writePref(_googleKey, null);
    String? back;
    try {
      back = await db.readPref(_googleReturnKey);
      await db.writePref(_googleReturnKey, null);
    } catch (_) {}
    if (_phase != SessionPhase.booting && _phase != SessionPhase.signedOut) {
      return false;
    }
    // Memory wins (a phone never reloaded); the device's copy is for the
    // web's reload.
    if (back != null && back.startsWith('/') && _returnTo == null) {
      stashReturnTo(back);
    }
    try {
      await handleSignedIn(user);
    } catch (error) {
      _signInProblem = AuthRepository.describeError(error);
      _phase = SessionPhase.signedOut;
      _emit();
    }
    return true;
  }

  Future<void> _handleSignedIn(User user) async {
    try {
      await db.writePref(_googleKey, null);
    } catch (_) {}
    final previous = await db.loadIdentity();

    // A second person signing in on the same phone while the first still has
    // unsent work would drain that work under the new person's token: the
    // entries would land on the server recorded by the wrong human, or be
    // refused outright. Neither is acceptable, so the handover waits.
    if (previous != null && previous.userId != user.id) {
      final pending = await db.pendingCount();
      if (pending > 0) {
        await auth.signOut();
        throw StateError(
          '$pending enregistrement${pending > 1 ? 's' : ''} de '
          '${previous.label} ${pending > 1 ? 'attendent' : 'attend'} encore '
          "le réseau. Reconnectez-vous avec ce compte et attendez l'envoi "
          'avant de changer d\'utilisateur.',
        );
      }
      await db.clearIdentity();
    }

    final identity = LocalIdentity(
      userId: user.id,
      displayName: user.userMetadata?['full_name'] as String?,
      phone: user.phone?.isEmpty == true ? null : user.phone,
      email: user.email?.isEmpty == true ? null : user.email,
      // Keep the code already on this device when the same person signs in again.
      pinSalt: previous?.userId == user.id ? previous?.pinSalt : null,
      pinHash: previous?.userId == user.id ? previous?.pinHash : null,
    );

    await db.saveIdentity(identity);
    _identity = identity;

    // The code, if any, is asked by the resolve: only of somebody who
    // belongs to a business (108).
    await resolveOrgs();
  }

  /// Whether this device holds a business of the person's: the list it
  /// last cached. A shopper's or a courier's phone holds none.
  Future<bool> _holdsBusiness() async =>
      (await _cachedOrgsSafe().timeout(resolveTimeout, onTimeout: () => const <OrgSummary>[]))
          .isNotEmpty;

  Future<void> setPin(String pin) async {
    final identity = _identity;
    if (identity == null) return;

    final salt = PinCodec.newSalt();
    final updated = identity.copyWith(
      pinSalt: salt,
      pinHash: PinCodec.hash(pin, salt),
    );

    await db.saveIdentity(updated);
    _identity = updated;
    await resolveOrgs();
  }

  /// Changes the device code from Compte › Sécurité: [current] must match,
  /// [next] must be a code PinCodec accepts. Returns the problem in words,
  /// or null when it is changed. Nothing leaves the phone.
  Future<String?> changePin(String current, String next) async {
    final identity = _identity;
    final salt = identity?.pinSalt;
    final hash = identity?.pinHash;
    if (identity == null || salt == null || hash == null) {
      return 'Aucun code n\'est enregistré sur ce téléphone.';
    }
    if (!PinCodec.verify(current, salt: salt, hash: hash)) {
      return 'Code actuel incorrect.';
    }
    final problem = PinCodec.validate(next);
    if (problem != null) return problem;
    final fresh = PinCodec.newSalt();
    final updated = identity.copyWith(
        pinSalt: fresh, pinHash: PinCodec.hash(next, fresh));
    await db.saveIdentity(updated);
    _identity = updated;
    return null;
  }

  /// The code screen accepted the second step: the token is aal2 now, and
  /// the resolve it interrupted goes on.
  Future<void> twoStepPassed() => resolveOrgs();

  /// PinScreen has already checked the code against the stored hash. From here
  /// the offline path and the online path are the same.
  Future<void> unlock() => resolveOrgs();

  /// The phone was away longer than its lock delay (Compte › Sécurité): the
  /// code is asked again. Only from inside — a person still signing in,
  /// choosing a code or already locked is left where they are — and only
  /// when there is a code to ask for. The router stashes the page, and
  /// unlocking returns to it.
  bool lockNow() {
    final identity = _identity;
    if (identity == null || !identity.hasPin) return false;
    // Nothing of a business on screen or on the device: no lock (108).
    if (_orgs.isEmpty) return false;
    if (_phase != SessionPhase.ready &&
        _phase != SessionPhase.picking &&
        _phase != SessionPhase.noOrg) {
      return false;
    }
    _phase = SessionPhase.locked;
    _emit();
    return true;
  }

  Future<void> signOut() async {
    await auth.signOut();
    await db.clearIdentity();
    await db.writePref(_lastOrgKey, null);
    _identity = null;
    _orgs = const [];
    _access.clear();
    _lastOrgId = null;
    _notice = null;
    _isPlatformAdmin = false;
    _twoStepEnrolled = false;
    _phase = SessionPhase.signedOut;
    _emit();
  }

  // ----------------------------------------------------------------
  // Which businesses?
  // ----------------------------------------------------------------

  Future<void> resolveOrgs() async {
    _phase = SessionPhase.resolving;
    _emit();

    var orgs = <OrgSummary>[];
    var fromCache = false;
    var platformAdmin = false;
    String? notice;

    if (auth.hasLiveSession) {
      // Three questions that do not depend on each other, asked at once:
      // on a market connection every round trip is a third of a second or
      // more, and asked one after the other they kept the spinner up for
      // all three before the business list could even be requested.
      //
      // Each is bounded by a timeout. On a market connection a request can
      // stall — the socket stays open and the reply never comes, so the
      // future neither completes nor throws. A timed-out call is treated as
      // a dead connection: fall back to what the device already knows, show
      // the notice, and let the next resolve retry.
      //
      // * Two-step (077): a platform admin below aal2 is refused by the
      //   server on every call but this one, so the resolve stops at the
      //   code screen when it says so. A stall or an error falls through.
      // * Platform admin: never throws, defaults closed on a stall, and is
      //   needed precisely when the org list comes back empty.
      // * Invitations addressed to this phone or email become memberships
      //   before the org list is asked — otherwise an invited user lands on
      //   the waiting screen with an invitation unclaimed. Best-effort.
      final step = twoStep;
      final askedTwoStep = step?.status().timeout(resolveTimeout);
      final askedAdmin = admin
          .isPlatformAdmin()
          .timeout(resolveTimeout)
          .catchError((Object _) => false);
      final claimed = admin
          .claimMyInvitations()
          .timeout(resolveTimeout)
          .then((_) => null, onError: (Object _) => null);
      if (askedTwoStep != null) {
        try {
          final status = await askedTwoStep;
          if (status.mustAsk) {
            _twoStepEnrolled = status.enrolled;
            _phase = SessionPhase.twoStep;
            _emit();
            return;
          }
        } catch (_) {}
      }
      platformAdmin = await askedAdmin;
      await claimed;

      try {
        orgs = await auth.fetchOrgs().timeout(resolveTimeout);
        await db.cacheOrgs(orgs);

        final identity = _identity;
        if (identity != null) {
          final updated = identity.copyWith(orgsRefreshedAt: DateTime.now());
          await db.saveIdentity(updated);
          _identity = updated;
        }
      } catch (error) {
        // The connection died, or stalled past the timeout, between signing in
        // and asking. Fall back to what this device already knows rather than
        // stranding the user on a spinner.
        orgs = await _cachedOrgsSafe();
        fromCache = true;
        notice = AuthRepository.describeError(error);
      }
    } else {
      orgs = await _cachedOrgsSafe();
      fromCache = true;
    }

    // A failure here must never escape: resolveOrgs is kicked off unawaited by
    // boot(), so anything it throws is unhandled and freezes the app on the
    // spinner with the phase stuck at `resolving`. Sync is best-effort anyway.
    try {
      _startSync();
    } catch (_) {}

    _orgs = orgs;
    // Rules may have changed since the last resolve; the next open refetches.
    _access.clear();
    _orgsFromCache = fromCache;
    _isPlatformAdmin = platformAdmin;
    _notice = notice;

    // What this device last had open, surviving the reload that wipes the
    // in-memory copy. Memory wins when it has an answer — an in-session
    // resolve must not yank somebody back to wherever yesterday ended.
    // Guarded: a failed pref read must not throw out of this unawaited call.
    try {
      _lastOrgId ??= await db.readPref(_lastOrgKey);
    } catch (_) {}

    if (orgs.isEmpty) {
      // Either genuinely uninvited, or offline before the first successful
      // fetch. Both land on the waiting screen, which is the one screen
      // carrying a Retry button.
      _lastOrgId = null;
      _phase = SessionPhase.noOrg;
    } else if (orgs.length == 1) {
      _lastOrgId = orgs.first.id;
      _phase = SessionPhase.ready;
    } else {
      // Somebody who has already opened a business keeps it across a refresh
      // rather than being sent back to the picker to choose it again.
      if (orgById(_lastOrgId) == null) _lastOrgId = null;
      _phase = _lastOrgId == null ? SessionPhase.picking : SessionPhase.ready;
    }

    // The device code protects businesses (108): chosen once this person
    // belongs to one — at the first sign-in of an owner, a member or a
    // trainer, or the day a shopper creates or joins their first business
    // — and before any of its books open. setPin() resolves again.
    final me = _identity;
    if (orgs.isNotEmpty && me != null && !me.hasPin) {
      _phase = SessionPhase.choosingPin;
      _emit();
      return;
    }

    _emit();

    final resolved = orgById(_lastOrgId);
    if (resolved != null) {
      unawaited(cacheChart(resolved));
      // The business this resolve auto-opened (a single-org employee, or the
      // one remembered across a reload) has its id in _lastOrgId already, so
      // the router's later openOrg() early-returns and never loads the dial.
      // Load it here, or an employee sees every tool the owner hid.
      unawaited(_loadAccess(resolved));
    }
  }

  // ----------------------------------------------------------------
  // Keeping an open app current
  // ----------------------------------------------------------------

  /// The audit's finding: what the server says about this person — their
  /// businesses, role in each, plan, team access, suspension — was read at
  /// launch, sign-in and unlock, and never again. An Android app stays open
  /// for days, so a Pro upgrade, a role change, a new business or an owner's
  /// new dial reached that phone only when it was closed and reopened
  /// (#110 fixed the one case of the waiting screen; this is all the rest).
  ///
  /// [refresh] asks again, quietly. Called when the app comes back to the
  /// foreground and every [refreshEvery] while it is open (KajApp). It never
  /// shows a spinner and never fails loudly: no signal leaves everything as
  /// it is. It emits only when the answer changed, and moves the person only
  /// when they must move — the business they had open is no longer theirs
  /// (to the picker), or they had none and now have one (the usual resolve).
  static const refreshEvery = Duration(minutes: 5);

  bool _refreshing = false;
  DateTime? _lastRefresh;

  /// True while a refresh is in flight (tests, and nothing else).
  @visibleForTesting
  bool get refreshing => _refreshing;

  Future<void> refresh({bool force = false}) async {
    if (_refreshing || _disposed || !auth.hasLiveSession) return;
    if (!_settled) return;
    // A burst of resumes (switching apps back and forth) asks once.
    final last = _lastRefresh;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _refreshing = true;
    try {
      var platformAdmin = _isPlatformAdmin;
      try {
        platformAdmin = await admin.isPlatformAdmin().timeout(resolveTimeout);
      } catch (_) {}
      try {
        await admin.claimMyInvitations().timeout(resolveTimeout);
      } catch (_) {}
      final List<OrgSummary> orgs;
      try {
        orgs = await auth.fetchOrgs().timeout(resolveTimeout);
      } catch (_) {
        return; // No signal is not news: everything stays as it is.
      }
      _lastRefresh = DateTime.now();
      // Signed out, locked or re-resolving while we asked: theirs to decide.
      if (_disposed || !_settled) return;
      try {
        await db.cacheOrgs(orgs);
      } catch (_) {}

      if (_phase == SessionPhase.noOrg) {
        // Nothing open, and now something to open: the normal resolve picks
        // where to land, exactly as at launch.
        if (orgs.isNotEmpty) await resolveOrgs();
        return;
      }

      final changed = !_sameOrgs(_orgs, orgs) ||
          platformAdmin != _isPlatformAdmin ||
          _orgsFromCache;
      if (changed) {
        _orgs = orgs;
        _isPlatformAdmin = platformAdmin;
        _orgsFromCache = false;
        _notice = null;
        // A business no longer in the list takes its dial with it.
        _access.removeWhere((id, _) => orgById(id) == null);
        if (orgs.isEmpty) {
          _lastOrgId = null;
          _phase = SessionPhase.noOrg;
        } else if (_phase == SessionPhase.ready && orgById(_lastOrgId) == null) {
          // The open business is no longer theirs.
          _lastOrgId = orgs.length == 1 ? orgs.first.id : null;
          _phase = orgs.length == 1 ? SessionPhase.ready : SessionPhase.picking;
          unawaited(db.writePref(_lastOrgKey, _lastOrgId));
        }
        _emit();
      }

      // The open business's dial and plan lock, re-read either way: an owner
      // may have changed the dial without the org list changing at all.
      // _loadAccess emits only if what screens see would change.
      final open = orgById(_lastOrgId);
      if (open != null && _phase == SessionPhase.ready) {
        _termsLoaded = false;
        await _loadAccess(open);
      }
    } finally {
      _refreshing = false;
    }
  }

  /// The phases a refresh may touch: somebody inside the app, not at a gate
  /// and not mid-resolve.
  bool get _settled =>
      _phase == SessionPhase.ready ||
      _phase == SessionPhase.picking ||
      _phase == SessionPhase.noOrg;

  static bool _sameOrgs(List<OrgSummary> a, List<OrgSummary> b) {
    if (a.length != b.length) return false;
    final byId = {for (final o in a) o.id: o.toCache()};
    for (final o in b) {
      final before = byId[o.id];
      if (before == null || !mapEquals(before, o.toCache())) return false;
    }
    return true;
  }

  /// Which business is open. Called by the router when a `/o/:orgId` route is
  /// entered, so the URL is what decides — not a tap that happened earlier.
  void openOrg(String orgId) {
    if (_lastOrgId == orgId) return;
    if (orgById(orgId) == null) return;
    _lastOrgId = orgId;
    _phase = SessionPhase.ready;
    unawaited(db.writePref(_lastOrgKey, orgId));
    unawaited(_loadAccess(orgById(orgId)!));
    unawaited(cacheChart(orgById(orgId)!));
    // Deliberately no notifyListeners(): the router is already mid-navigation
    // to this route, and telling it to re-run its redirect from inside that
    // navigation is how a redirect loop starts.
  }

  /// Leaving a business for the picker, without signing out. Remembered like
  /// an opening is: somebody who chose the picker gets the picker back on
  /// reload, not the business they left.
  void leaveOrg() {
    _lastOrgId = null;
    _phase = SessionPhase.picking;
    unawaited(db.writePref(_lastOrgKey, null));
    _emit();
  }

  /// Pulls the chart of accounts onto the device in the background.
  ///
  /// Runs once when a business opens, and never blocks anything: a failure
  /// here means the recording sheets fall back to the categories this device
  /// has already used, which is a slightly shorter list and not a broken
  /// screen.
  Future<void> cacheChart(OrgSummary org) async {
    if (!accounting.isConfigured || !auth.hasLiveSession) return;
    try {
      final accounts = await accounting.chartOfAccounts(org.id);
      await db.cacheAccounts(
        org.id,
        accounts.map((a) => a.toCache()).toList(),
      );
    } catch (_) {
      // No signal, or no entitlement. Neither is worth interrupting anyone for.
    }
  }

  void _startSync() {
    final s = sync;
    if (s != null && !_syncStarted) {
      s.start();
      _syncStarted = true;
    }
  }
}

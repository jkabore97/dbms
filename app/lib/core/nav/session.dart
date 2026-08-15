import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../accounting/accounting_repository.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_repository.dart';
import '../auth/models.dart';
import '../auth/pin_codec.dart';
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
  });

  final LocalDb db;
  final AuthRepository auth;
  final AdminRepository admin;
  final AccountingRepository accounting;
  final SyncService? sync;

  SessionPhase _phase = SessionPhase.booting;
  SessionPhase get phase => _phase;

  LocalIdentity? _identity;
  LocalIdentity? get identity => _identity;

  List<OrgSummary> _orgs = const [];
  List<OrgSummary> get orgs => _orgs;

  /// The business the router last settled on. Kept so a redirect can send
  /// somebody straight back to it, and so `/` knows where "home" is.
  String? _lastOrgId;
  String? get lastOrgId => _lastOrgId;

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
    super.dispose();
  }

  // ----------------------------------------------------------------
  // Boot
  // ----------------------------------------------------------------

  Future<void> boot() async {
    final identity = await db.loadIdentity();

    if (identity == null) {
      _phase = SessionPhase.signedOut;
      _emit();
      return;
    }

    _identity = identity;

    // A live token means the server has vouched for this person within the
    // hour. Anything else and the device has to vouch for them itself.
    if (auth.hasLiveSession) {
      if (!identity.hasPin) {
        _phase = SessionPhase.choosingPin;
        _emit();
      } else {
        await resolveOrgs();
      }
      return;
    }

    if (identity.hasPin) {
      _phase = SessionPhase.locked;
    } else {
      // Signed in once, never set a code, and now the token is stale. There is
      // nothing on the device that can prove who this is, so ask the server.
      _phase = SessionPhase.signedOut;
    }
    _emit();
  }

  // ----------------------------------------------------------------
  // Signing in
  // ----------------------------------------------------------------

  Future<void> handleSignedIn(User user) async {
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

    if (!identity.hasPin) {
      _phase = SessionPhase.choosingPin;
      _emit();
    } else {
      await resolveOrgs();
    }
  }

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

  /// PinScreen has already checked the code against the stored hash. From here
  /// the offline path and the online path are the same.
  Future<void> unlock() => resolveOrgs();

  Future<void> signOut() async {
    await auth.signOut();
    await db.clearIdentity();
    _identity = null;
    _orgs = const [];
    _lastOrgId = null;
    _notice = null;
    _isPlatformAdmin = false;
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
      // Asked first and separately: it never throws, and a platform admin with
      // no businesses yet needs it precisely when the org list comes back
      // empty.
      platformAdmin = await admin.isPlatformAdmin();

      try {
        // Anything addressed to this person's phone or email becomes a
        // membership before we ask what they belong to — otherwise an invited
        // user would land on the waiting screen with an invitation sitting
        // unclaimed on the server. Never throws; a missed sweep is picked up
        // on the next launch or by typing the code.
        await admin.claimMyInvitations();

        orgs = await auth.fetchOrgs();
        await db.cacheOrgs(orgs);

        final identity = _identity;
        if (identity != null) {
          final updated = identity.copyWith(orgsRefreshedAt: DateTime.now());
          await db.saveIdentity(updated);
          _identity = updated;
        }
      } catch (error) {
        // The connection died between signing in and asking. Fall back to what
        // this device already knows rather than stranding the user.
        orgs = await db.cachedOrgs();
        fromCache = true;
        notice = AuthRepository.describeError(error);
      }
    } else {
      orgs = await db.cachedOrgs();
      fromCache = true;
    }

    _startSync();

    _orgs = orgs;
    _orgsFromCache = fromCache;
    _isPlatformAdmin = platformAdmin;
    _notice = notice;

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

    _emit();

    final resolved = orgById(_lastOrgId);
    if (resolved != null) unawaited(cacheChart(resolved));
  }

  /// Which business is open. Called by the router when a `/o/:orgId` route is
  /// entered, so the URL is what decides — not a tap that happened earlier.
  void openOrg(String orgId) {
    if (_lastOrgId == orgId) return;
    if (orgById(orgId) == null) return;
    _lastOrgId = orgId;
    _phase = SessionPhase.ready;
    unawaited(cacheChart(orgById(orgId)!));
    // Deliberately no notifyListeners(): the router is already mid-navigation
    // to this route, and telling it to re-run its redirect from inside that
    // navigation is how a redirect loop starts.
  }

  /// Leaving a business for the picker, without signing out.
  void leaveOrg() {
    _lastOrgId = null;
    _phase = SessionPhase.picking;
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

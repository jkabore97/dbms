import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../access/org_access.dart';
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
    if (org == null || org.isAdmin) return OrgAccess.allEdit;
    return const OrgAccess.forTier({});
  }

  Future<void> _loadAccess(OrgSummary org) async {
    final OrgAccess next;
    if (org.isAdmin) {
      next = OrgAccess.allEdit;
    } else {
      final rules =
          await admin.featureRulesForTier(org.id, OrgAccess.tierOf(org.roles));
      next = OrgAccess.forTier(rules);
    }
    // Emit only if this changes what screens already see — an unchanged dial
    // (an admin, an untouched business, an offline fetch that came back empty)
    // must not fire a rebuild, because _loadAccess runs during the resolve and
    // open flows where a stray notify re-runs the router's redirect.
    final changed = accessFor(org.id) != next;
    _access[org.id] = next;
    if (changed) _emit();
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
    await db.writePref(_lastOrgKey, null);
    _identity = null;
    _orgs = const [];
    _access.clear();
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
    // Rules may have changed since the last resolve; the next open refetches.
    _access.clear();
    _orgsFromCache = fromCache;
    _isPlatformAdmin = platformAdmin;
    _notice = notice;

    // What this device last had open, surviving the reload that wipes the
    // in-memory copy. Memory wins when it has an answer — an in-session
    // resolve must not yank somebody back to wherever yesterday ended.
    _lastOrgId ??= await db.readPref(_lastOrgKey);

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
    if (resolved != null) {
      unawaited(cacheChart(resolved));
      // The business this resolve auto-opened (a single-org employee, or the
      // one remembered across a reload) has its id in _lastOrgId already, so
      // the router's later openOrg() early-returns and never loads the dial.
      // Load it here, or an employee sees every tool the owner hid.
      unawaited(_loadAccess(resolved));
    }
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

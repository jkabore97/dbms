import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'core/accounting/accounting_repository.dart';
import 'core/admin/admin_repository.dart';
import 'core/auth/auth_repository.dart';
import 'core/auth/models.dart';
import 'core/auth/pin_codec.dart';
import 'core/capture/capture_repository.dart';
import 'core/console/console_repository.dart';
import 'core/db/local_db.dart';
import 'core/farm/farm_repository.dart';
import 'core/retail/retail_repository.dart';
import 'core/retail/staff.dart';
import 'core/reports/reports_repository.dart';
import 'core/sync/sync_service.dart';
import 'features/accounting/accounting_hub_screen.dart';
import 'features/accounting/journal_screen.dart';
import 'features/admin/admin_home_screen.dart';
import 'features/admin/businesses_screen.dart';
import 'features/admin/create_business_screen.dart';
import 'features/auth/join_by_code_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/no_org_screen.dart';
import 'features/auth/org_picker_screen.dart';
import 'features/auth/pin_screen.dart';
import 'features/home/account_menu.dart';
import 'features/home/home_router.dart';

/// Everything between launching the app and landing in a business.
///
/// The whole flow exists to answer two questions — who is this, and whose
/// books are they allowed to open — and to answer them with no signal as
/// readily as with signal:
///
///   booting -> signed out         no identity on the device
///           -> locked             identity, but the token cannot be refreshed
///           -> choosing a code    signed in, no PIN set yet
///           -> resolving          asking the server which orgs they belong to
///           -> no org / picker / home
///
/// Nothing here decides which org to open. `my_orgs()` does, server-side,
/// behind RLS — the client cannot ask for an org it was not granted.
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.db,
    required this.auth,
    required this.admin,
    required this.reports,
    required this.accounting,
    required this.console,
    required this.farm,
    required this.retail,
    required this.staff,
    required this.capture,
    this.sync,
  });

  final LocalDb db;
  final AuthRepository auth;
  final AdminRepository admin;
  final ReportsRepository reports;
  final AccountingRepository accounting;
  final ConsoleRepository console;
  final FarmRepository farm;
  final RetailRepository retail;
  final StaffRepository staff;
  final CaptureRepository capture;
  final SyncService? sync;

  @override
  State<AppRoot> createState() => _AppRootState();
}

enum _Phase { booting, signedOut, locked, choosingPin, resolving, noOrg, picking, ready }

class _AppRootState extends State<AppRoot> {
  _Phase _phase = _Phase.booting;

  LocalIdentity? _identity;
  List<OrgSummary> _orgs = const [];
  OrgSummary? _org;

  /// Set when the org list came from the device instead of the server. The
  /// home screen still works; the user simply has not been re-checked.
  bool _orgsFromCache = false;

  /// Whether this person may create businesses. Re-read from the server on
  /// every resolve and never cached on the device: it decides whether a menu
  /// entry is drawn, and a stale `true` would draw a button whose action the
  /// server refuses anyway.
  bool _isPlatformAdmin = false;
  String? _notice;
  bool _syncStarted = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  // ----------------------------------------------------------------
  // Boot
  // ----------------------------------------------------------------

  Future<void> _boot() async {
    final identity = await widget.db.loadIdentity();

    if (identity == null) {
      _to(_Phase.signedOut);
      return;
    }

    setState(() => _identity = identity);

    // A live token means the server has vouched for this person within the
    // hour. Anything else and the device has to vouch for them itself.
    if (widget.auth.hasLiveSession) {
      if (!identity.hasPin) {
        _to(_Phase.choosingPin);
      } else {
        await _resolveOrgs();
      }
      return;
    }

    if (identity.hasPin) {
      _to(_Phase.locked);
    } else {
      // Signed in once, never set a code, and now the token is stale. There is
      // nothing on the device that can prove who this is, so ask the server.
      _to(_Phase.signedOut);
    }
  }

  void _to(_Phase phase) {
    if (mounted) setState(() => _phase = phase);
  }

  // ----------------------------------------------------------------
  // Signing in
  // ----------------------------------------------------------------

  Future<void> _handleSignedIn(User user) async {
    final previous = await widget.db.loadIdentity();

    // A second person signing in on the same phone while the first still has
    // unsent work would drain that work under the new person's token: the
    // entries would land on the server recorded by the wrong human, or be
    // refused outright. Neither is acceptable, so the handover waits.
    if (previous != null && previous.userId != user.id) {
      final pending = await widget.db.pendingCount();
      if (pending > 0) {
        await widget.auth.signOut();
        throw StateError(
          '$pending enregistrement${pending > 1 ? 's' : ''} de '
          '${previous.label} ${pending > 1 ? 'attendent' : 'attend'} encore '
          "le réseau. Reconnectez-vous avec ce compte et attendez l'envoi "
          'avant de changer d\'utilisateur.',
        );
      }
      await widget.db.clearIdentity();
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

    await widget.db.saveIdentity(identity);
    if (!mounted) return;
    setState(() => _identity = identity);

    if (!identity.hasPin) {
      _to(_Phase.choosingPin);
    } else {
      await _resolveOrgs();
    }
  }

  Future<void> _setPin(String pin) async {
    final identity = _identity;
    if (identity == null) return;

    final salt = PinCodec.newSalt();
    final updated = identity.copyWith(
      pinSalt: salt,
      pinHash: PinCodec.hash(pin, salt),
    );

    await widget.db.saveIdentity(updated);
    if (!mounted) return;
    setState(() => _identity = updated);
    await _resolveOrgs();
  }

  Future<void> _unlock(String _) async {
    // PinScreen has already checked the code against the stored hash. From
    // here the offline path and the online path are the same.
    await _resolveOrgs();
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
    await widget.db.clearIdentity();
    if (!mounted) return;
    setState(() {
      _identity = null;
      _orgs = const [];
      _org = null;
      _notice = null;
      _phase = _Phase.signedOut;
    });
  }

  // ----------------------------------------------------------------
  // Which businesses?
  // ----------------------------------------------------------------

  Future<void> _resolveOrgs() async {
    _to(_Phase.resolving);

    var orgs = <OrgSummary>[];
    var fromCache = false;
    var platformAdmin = false;
    String? notice;

    if (widget.auth.hasLiveSession) {
      // Asked first and separately: it never throws, and a platform admin with
      // no businesses yet needs it precisely when the org list comes back
      // empty.
      platformAdmin = await widget.admin.isPlatformAdmin();

      try {
        // Anything addressed to this person's phone or email becomes a
        // membership before we ask what they belong to — otherwise an invited
        // user would land on the waiting screen with an invitation sitting
        // unclaimed on the server. Never throws; a missed sweep is picked up
        // on the next launch or by typing the code.
        await widget.admin.claimMyInvitations();

        orgs = await widget.auth.fetchOrgs();
        await widget.db.cacheOrgs(orgs);

        final identity = _identity;
        if (identity != null) {
          final updated = identity.copyWith(orgsRefreshedAt: DateTime.now());
          await widget.db.saveIdentity(updated);
          if (mounted) setState(() => _identity = updated);
        }
      } catch (error) {
        // The connection died between signing in and asking. Fall back to what
        // this device already knows rather than stranding the user.
        orgs = await widget.db.cachedOrgs();
        fromCache = true;
        notice = AuthRepository.describeError(error);
      }
    } else {
      orgs = await widget.db.cachedOrgs();
      fromCache = true;
    }

    if (!mounted) return;

    _startSync();

    setState(() {
      _orgs = orgs;
      _orgsFromCache = fromCache;
      _isPlatformAdmin = platformAdmin;
      _notice = notice;

      if (orgs.isEmpty) {
        // Either genuinely uninvited, or offline before the first successful
        // fetch. Both land on the waiting screen, which is the one screen
        // carrying a Retry button.
        _org = null;
        _phase = _Phase.noOrg;
      } else if (orgs.length == 1) {
        _org = orgs.first;
        _phase = _Phase.ready;
      } else {
        _org = null;
        _phase = _Phase.picking;
      }
    });

    final resolved = _org;
    if (resolved != null) unawaited(_cacheChart(resolved));
  }

  // ----------------------------------------------------------------
  // Joining, and administering
  // ----------------------------------------------------------------

  /// Opens the code screen. A successful claim re-resolves the org list, which
  /// is what moves the user off the waiting screen and into the business.
  Future<void> _joinByCode() async {
    final joined = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => JoinByCodeScreen(admin: widget.admin)),
    );
    if (joined == true) await _resolveOrgs();
  }

  /// Creating a business, then opening it.
  ///
  /// The new org is opened directly rather than left to the usual count-based
  /// routing: a platform admin's list is every business there is, so making
  /// one would otherwise drop them on the picker to hunt for what they just
  /// made.
  /// The platform's own list: every business, archived ones included, with
  /// the buttons that change, archive and destroy one. Reloads the org list
  /// afterwards, because renaming or archiving from in there changes what this
  /// person can open.
  Future<void> _openBusinesses() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusinessesScreen(admin: widget.admin),
      ),
    );
    if (!mounted) return;
    await _resolveOrgs();
  }

  Future<void> _createBusiness() async {
    final orgId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CreateBusinessScreen(admin: widget.admin),
      ),
    );
    if (orgId == null) return;

    await _resolveOrgs();
    if (!mounted) return;

    OrgSummary? created;
    for (final org in _orgs) {
      if (org.id == orgId) {
        created = org;
        break;
      }
    }
    if (created != null) {
      setState(() {
        _org = created;
        _phase = _Phase.ready;
      });
    }
  }

  Future<void> _administer(OrgSummary org) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminHomeScreen(
          admin: widget.admin,
          org: org,
          console: widget.console,
          db: widget.db,
          // Renaming the business changes what my_orgs() returns, and the name
          // in the app bar comes from there rather than from the settings form.
          onOrgChanged: _resolveOrgs,
        ),
      ),
    );
  }

  /// The same screen the accounting hub opens on, reached directly from the
  /// home screen. One screen rather than two: an entry's history is the
  /// journal, and a second list that showed the same rows differently would be
  /// a second thing to keep true.
  Future<void> _openHistory(OrgSummary org) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JournalScreen(
          accounting: widget.accounting,
          org: org,
        ),
      ),
    );
  }

  Future<void> _openAccounting(OrgSummary org) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountingHubScreen(
          accounting: widget.accounting,
          org: org,
          // The chart of accounts screen mirrors what it fetches onto the
          // device, which is what keeps the recording sheets offering real
          // category names once the signal has gone.
          db: widget.db,
        ),
      ),
    );
  }

  /// Pulls the chart of accounts onto the device in the background.
  ///
  /// Runs once when a business opens, and never blocks anything: a failure
  /// here means the recording sheets fall back to the categories this device
  /// has already used, which is a slightly shorter list and not a broken
  /// screen.
  Future<void> _cacheChart(OrgSummary org) async {
    if (!widget.accounting.isConfigured || !widget.auth.hasLiveSession) return;
    try {
      final accounts = await widget.accounting.chartOfAccounts(org.id);
      await widget.db.cacheAccounts(
        org.id,
        accounts.map((a) => a.toCache()).toList(),
      );
    } catch (_) {
      // No signal, or no entitlement. Neither is worth interrupting anyone for.
    }
  }

  void _startSync() {
    final sync = widget.sync;
    if (sync != null && !_syncStarted) {
      sync.start();
      _syncStarted = true;
    }
  }

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.booting:
      case _Phase.resolving:
        return const _Splash();

      case _Phase.signedOut:
        return LoginScreen(auth: widget.auth, onSignedIn: _handleSignedIn);

      case _Phase.locked:
        return PinScreen(
          purpose: PinPurpose.unlock,
          identity: _identity!,
          onPinAccepted: _unlock,
          onSignOut: _signOut,
        );

      case _Phase.choosingPin:
        return PinScreen(
          purpose: PinPurpose.create,
          identity: _identity!,
          onPinAccepted: _setPin,
          onSignOut: _signOut,
        );

      case _Phase.noOrg:
        return NoOrgScreen(
          identity: _identity!,
          onRetry: _resolveOrgs,
          onSignOut: _signOut,
          // A build with no server has nothing to check a code against, and
          // an expired token cannot claim one either.
          onJoinByCode: widget.auth.hasLiveSession ? _joinByCode : null,
          // The bootstrap case: the person who runs the platform, before any
          // business exists. Without this the only way to make the first one
          // is an INSERT by hand.
          onCreateBusiness: _isPlatformAdmin && widget.auth.hasLiveSession
              ? _createBusiness
              : null,
        );

      case _Phase.picking:
        return OrgPickerScreen(
          orgs: _orgs,
          onSelected: (org) => setState(() {
            _org = org;
            _phase = _Phase.ready;
          }),
          onSignOut: _signOut,
          onCreateBusiness: _isPlatformAdmin && widget.auth.hasLiveSession
              ? _createBusiness
              : null,
          onBusinesses: _isPlatformAdmin && widget.auth.hasLiveSession
              ? _openBusinesses
              : null,
        );

      case _Phase.ready:
        final org = _org!;
        return _HomeWithNotice(
          notice: _orgsFromCache ? _notice : null,
          child: homeScreenFor(
            db: widget.db,
            org: org,
            reports: widget.reports,
            farm: widget.farm,
            retail: widget.retail,
            staff: widget.staff,
            capture: widget.capture,
            // Same live-session rule as the reports: the history is paged by
            // the database, so it is offered only while there is a session to
            // page with.
            onHistory: widget.auth.hasLiveSession
                ? () => _openHistory(org)
                : null,
            accountAction: AccountMenu(
              db: widget.db,
              userLabel: _identity?.label ?? '',
              onSignOut: _signOut,
              // All of these need the server, so all of them disappear once
              // the token has expired — the rest of the app keeps working
              // offline. A report computed from a device's partial copy of the
              // books would be a wrong number presented as a right one.
              onAdminister: org.isAdmin && widget.auth.hasLiveSession
                  ? () => _administer(org)
                  : null,
              onAccounting: widget.auth.hasLiveSession
                  ? () => _openAccounting(org)
                  : null,
              onJoinByCode:
                  widget.auth.hasLiveSession ? _joinByCode : null,
              onCreateBusiness: _isPlatformAdmin && widget.auth.hasLiveSession
                  ? _createBusiness
                  : null,
              onBusinesses: _isPlatformAdmin && widget.auth.hasLiveSession
                  ? _openBusinesses
                  : null,
              onSwitchOrg: _orgs.length > 1
                  ? () => setState(() {
                        _org = null;
                        _phase = _Phase.picking;
                      })
                  : null,
            ),
          ),
        );
    }
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Puts a one-line explanation above the home screen when the org list could
/// not be refreshed. The app still works; the user just knows why.
class _HomeWithNotice extends StatefulWidget {
  const _HomeWithNotice({required this.child, this.notice});

  final Widget child;
  final String? notice;

  @override
  State<_HomeWithNotice> createState() => _HomeWithNoticeState();
}

class _HomeWithNoticeState extends State<_HomeWithNotice> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    if (notice == null || _dismissed) return widget.child;

    final theme = Theme.of(context);
    return Column(
      children: [
        Material(
          color: theme.colorScheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      notice,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _dismissed = true),
                    tooltip: 'Masquer',
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

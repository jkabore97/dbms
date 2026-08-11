import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'core/auth/auth_repository.dart';
import 'core/auth/models.dart';
import 'core/auth/pin_codec.dart';
import 'core/db/local_db.dart';
import 'core/sync/sync_service.dart';
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
    this.sync,
  });

  final LocalDb db;
  final AuthRepository auth;
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
    String? notice;

    if (widget.auth.hasLiveSession) {
      try {
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
        );

      case _Phase.picking:
        return OrgPickerScreen(
          orgs: _orgs,
          onSelected: (org) => setState(() {
            _org = org;
            _phase = _Phase.ready;
          }),
          onSignOut: _signOut,
        );

      case _Phase.ready:
        final org = _org!;
        return _HomeWithNotice(
          notice: _orgsFromCache ? _notice : null,
          child: homeScreenFor(
            db: widget.db,
            org: org,
            accountAction: AccountMenu(
              db: widget.db,
              userLabel: _identity?.label ?? '',
              onSignOut: _signOut,
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

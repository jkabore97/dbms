import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../l10n/strings.dart';
import '../notify/notifications_screen.dart';
import 'home_router.dart';

/// A business, open.
///
/// This is what `/o/<id>` renders, and it is the piece that used to be the
/// `ready` branch of `AppRoot`'s build method. It is a page in its own right
/// now, which is the whole point: it has an address, so a person can come back
/// to it with the back button, a bookmark, or a reload.
///
/// Everything the account menu offers is a `push` to another address rather
/// than a callback into a parent's state, so each of those screens is equally
/// a page. What used to be `onSwitchOrg` — a `setState` that swapped the
/// business out from under you and left nothing in history — is now simply
/// going to the picker's address.
class BusinessShell extends StatelessWidget {
  const BusinessShell({super.key, required this.org});

  final OrgSummary org;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final session = scope.session;
    final live = scope.auth.hasLiveSession;
    // The owner's dial: which tools this person is even shown. The server
    // enforces the ones that matter; this decides what exists on screen.
    final access = session.accessFor(org.id);

    final home = _HomeWithNotice(
      notice: session.orgsFromCache ? session.notice : null,
      child: homeScreenFor(
        db: scope.db,
        org: org,
        access: access,
        reports: scope.reports,
        farm: scope.farm,
        invoicing: scope.invoicing,
        retail: scope.retail,
        staff: scope.staff,
        capture: scope.capture,
        // Same live-session rule as the reports: the history is paged by the
        // database, so it is offered only while there is a session to page
        // with.
        onHistory:
            live ? () => context.push(Routes.inside(org.id, 'journal')) : null,
        // One slot, two widgets: the bell rides next to the account button so
        // every home screen gets both without knowing they exist. The bell is
        // always present — greyed offline rather than removed — and the whole
        // account menu folded into one Compte screen, so nothing here has to
        // know which of a dozen destinations a person is even allowed.
        accountAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NotificationBell(
              notify: scope.notify,
              listRoute: Routes.inside(org.id, 'notifications'),
              enabled: live,
            ),
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: Strings.of(context).account,
              onPressed: () => context.push(Routes.inside(org.id, 'compte')),
            ),
          ],
        ),
      ),
    );

    // A frozen business stays fully readable but takes no more writes. The
    // banner is not dismissable — unlike the offline notice, this is not a
    // transient condition the person can wave away; it is the state of the
    // business until the platform lifts it, and every refused save downstream
    // makes more sense with it in view.
    if (!org.suspended) return home;
    return Column(
      children: [
        const _SuspendedBanner(),
        Expanded(child: home),
      ],
    );
  }
}

/// The standing notice on a business the platform has frozen. Members keep
/// their history and their reports; nothing new can be recorded until it is
/// reactivated.
class _SuspendedBanner extends StatelessWidget {
  const _SuspendedBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.lock_outline,
                  size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cette entreprise est suspendue. La consultation reste '
                  'possible, mais aucune nouvelle opération ne peut être '
                  'enregistrée.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
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
                    child: Text(notice, style: theme.textTheme.bodySmall),
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

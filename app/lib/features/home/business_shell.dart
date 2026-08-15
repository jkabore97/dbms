import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../admin/invite_generator_sheet.dart';
import 'account_menu.dart';
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
    final admin = org.isAdmin && live;
    final platform = session.isPlatformAdmin && live;

    return _HomeWithNotice(
      notice: session.orgsFromCache ? session.notice : null,
      child: homeScreenFor(
        db: scope.db,
        org: org,
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
        accountAction: AccountMenu(
          db: scope.db,
          userLabel: session.identity?.label ?? '',
          onSignOut: session.signOut,
          // All of these need the server, so all of them disappear once the
          // token has expired — the rest of the app keeps working offline. A
          // report computed from a device's partial copy of the books would be
          // a wrong number presented as a right one.
          onAdminister: admin
              ? () => context.push(Routes.inside(org.id, 'administration'))
              : null,
          onAccounting: live
              ? () => context.push(Routes.inside(org.id, 'comptabilite'))
              : null,
          onCreateBusiness:
              platform ? () => context.push(Routes.newBusiness) : null,
          onBusinesses: platform ? () => context.push(Routes.console) : null,
          onApplications:
              platform ? () => context.push(Routes.applications) : null,
          // Replaces "J'ai un code": the person holding the app is the
          // manager, and the person who needs reaching does not have it.
          onMyProfile: live ? () => context.push(Routes.myProfile) : null,
          onLanguage: () => context.push(Routes.language),
          onCreditBook: live
              ? () => context.push(Routes.inside(org.id, 'credits'))
              : null,
          onTontines: live
              ? () => context.push(Routes.inside(org.id, 'tontines'))
              : null,
          onApplyForOrg: !session.isPlatformAdmin && live
              ? () => context.push(Routes.applyForBusiness)
              : null,
          onInvite: admin
              ? () => InviteGeneratorSheet.open(context,
                  orgId: org.id, onboarding: scope.onboarding)
              : null,
          // Going to the picker rather than swapping the business out behind
          // the user: it is an address, so back returns here.
          onSwitchOrg:
              session.orgs.length > 1 ? () => context.go(Routes.picker) : null,
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

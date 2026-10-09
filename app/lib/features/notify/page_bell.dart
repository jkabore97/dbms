import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/nav/router.dart';
import '../../core/notify/notifications_repository.dart';
import 'notifications_screen.dart';

/// The business's bell on every tool page (115), at the right end of the
/// page's own top bar — as the home has it — so a ring is seen from
/// Articles, Commandes, Factures and every other page of the shop, the farm
/// and the association.
///
/// Each page draws its own AppBar, so the bell is laid over the bar's last
/// place and the page's own actions are moved one place left to make room
/// for it (AppBarTheme.actionsPadding): the page keeps every button it had.
/// It is part of the page, under a sheet or a dialog as the page is. The
/// home has its bell already; the list itself needs none.
class PageBell extends StatelessWidget {
  const PageBell({
    super.key,
    required this.org,
    required this.notify,
    required this.path,
    required this.enabled,
    required this.child,
  });

  final OrgSummary org;
  final NotificationsRepository notify;

  /// This page's own address (`/o/<id>/factures/…`).
  final String path;

  /// Greyed offline, like the home's.
  final bool enabled;
  final Widget child;

  /// The room the bell takes at the bar's end.
  static const room = 48.0;

  /// Whether a page at [path] of the business draws the bell.
  static bool showsOn(String orgId, String path) {
    final home = Routes.org(orgId);
    var rest = path.startsWith(home) ? path.substring(home.length) : path;
    if (rest.startsWith('/')) rest = rest.substring(1);
    if (rest.endsWith('/')) rest = rest.substring(0, rest.length - 1);
    return rest.isNotEmpty && rest != 'notifications';
  }

  @override
  Widget build(BuildContext context) {
    if (!showsOn(org.id, path)) return child;
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context);
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return Stack(
      children: [
        Theme(
          data: theme.copyWith(
            appBarTheme: theme.appBarTheme.copyWith(
              actionsPadding: const EdgeInsetsDirectional.only(end: room),
            ),
          ),
          child: child,
        ),
        Positioned(
          top: padding.top,
          right: ltr ? padding.right : null,
          left: ltr ? null : padding.left,
          height: kToolbarHeight,
          child: Center(
            child: NotificationBell(
              key: const Key('page-bell'),
              notify: notify,
              scope: NotifyScope.org(org.id),
              listRoute: Routes.inside(org.id, 'notifications'),
              enabled: enabled,
            ),
          ),
        ),
      ],
    );
  }
}

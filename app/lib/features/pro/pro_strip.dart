import 'package:flutter/material.dart';

import '../../core/nav/app_scope.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/nav/router.dart';
import '../../core/theme/kaj_theme.dart';

/// The small « Pro » at the top of every page inside a business that is not
/// on Kaj Pro, for the people who can change that — its owner and admins.
/// One tap opens the Free and Pro side by side (`/o/<id>/kaj-pro`).
///
/// A slim paper strip over the page rather than a button squeezed into
/// each page's own bar: the same place on every page, never over a title or
/// an action, and drawn from one place (the router's _withOrg) so no page
/// can forget it.
class ProStrip extends StatelessWidget {
  const ProStrip({super.key, required this.org, required this.child});

  final OrgSummary org;
  final Widget child;

  /// Whether this person, in this business, is shown the strip.
  static bool shownFor(OrgSummary org) => org.isAdmin && !org.isPro;

  @override
  Widget build(BuildContext context) {
    if (!shownFor(org)) return child;
    // The comparison page itself does not invite to itself.
    final here = GoRouterState.of(context).matchedLocation;
    if (here.endsWith('/kaj-pro')) return child;
    // Not over the first setup (091) nor the business settings: the first
    // steps are the free essentials, without an invitation to pay.
    if (here.contains('/administration/parametres')) return child;
    final features = AppScope.maybeOf(context)?.session.featuresFor(org.id);
    if (features != null && !features.setupDone) return child;
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Material(
          color: kPaper,
          child: Container(
            padding: EdgeInsets.only(top: top),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kLine)),
            ),
            child: SizedBox(
              height: 34,
              child: Center(
                child: ProPill(
                  onTap: () => context.push(Routes.inside(org.id, 'kaj-pro')),
                ),
              ),
            ),
          ),
        ),
        // The page below no longer owns the status bar: the strip does.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The pill itself: ink, small capitals, a spark.
class ProPill extends StatelessWidget {
  const ProPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Passer à Mara Pro',
      excludeSemantics: true,
      child: Material(
        key: const Key('pro-pill'),
        color: kInk,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: kPaper),
                SizedBox(width: 6),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: kPaper,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

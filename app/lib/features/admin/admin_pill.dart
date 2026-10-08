import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/tr.dart';
import '../../core/nav/look_only.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';

/// « Admin » (104): the platform's way into its command center, on the top
/// bar of the homes, the picker, Compte and the street — drawn only for a
/// platform admin. A graphite pill with caramel words, so it is never
/// taken for one of the business's own buttons. A courtesy: the server
/// checks every one of the center's functions itself.
///
/// Kept light (no business screen imported) because the street, which
/// every shopper downloads, carries it too.
class AdminPill extends StatelessWidget {
  const AdminPill({super.key, this.platformAdmin});

  /// Whether to draw it; null reads the session (tests say it outright).
  final bool? platformAdmin;

  @override
  Widget build(BuildContext context) {
    // « Voir comme le commerçant » (106) is the owner's view: no pill.
    if (LookOnly.of(context)) return const SizedBox.shrink();
    final given = platformAdmin;
    if (given != null) return given ? const _Pill() : const SizedBox.shrink();
    final session = AppScope.maybeOf(context)?.session;
    if (session == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) =>
          session.isPlatformAdmin ? const _Pill() : const SizedBox.shrink(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) {
    // A phone's app bar (a farm's or an association's, with the pending
    // chip, the switch button and the bell) has no room for the word: the
    // shield alone, still graphite and caramel, still « Centre admin » to
    // a screen reader.
    final narrow = MediaQuery.sizeOf(context).width < 400;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: context.tr('Centre admin'),
        child: Semantics(
          button: true,
          label: context.tr('Centre admin'),
          child: Material(
            key: const Key('admin-pill'),
            color: maraDeep,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => AdminTrail.enter(context),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: 36, minWidth: narrow ? 40 : 48),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 10 : 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shield_outlined, size: 18, color: maraCaramel),
                      if (!narrow) ...[
                        const SizedBox(width: 6),
                        Text(
                          context.tr('Admin'),
                          style: const TextStyle(
                            color: maraCaramel,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the platform admin came from, in memory only: the page the pill
/// was tapped on (« Quitter » goes back there), and the business the center
/// opened (its home then offers « Retour au centre admin »).
abstract final class AdminTrail {
  static String? _returnTo;

  /// The business the center opened, and the center page it was opened
  /// from.
  static final opened = ValueNotifier<({String orgId, String from})?>(null);

  static String? _here(BuildContext context) {
    try {
      return GoRouter.of(context).state.uri.toString();
    } catch (_) {
      return null;
    }
  }

  /// The center's own addresses: the console's, and the requests' pages.
  static bool inCenter(String location) =>
      location.startsWith(Routes.console) || location.startsWith(Routes.applications);

  /// Into the center — the pill, Compte's « Plateforme » rows, a bell —
  /// at [to], remembering where from, so « Quitter » (and back) return
  /// there.
  static void enter(BuildContext context, {String to = Routes.console}) {
    final here = _here(context);
    if (here != null && !inCenter(here)) _returnTo = here;
    context.push(to);
  }

  /// A page outside the center opened from it (« La rue »): the center is
  /// left for it, so nothing stale is kept to « Quitter » back to.
  static void goOut(BuildContext context, String route) {
    _returnTo = null;
    context.go(route);
  }

  /// « Quitter le centre »: back to the page the pill was tapped on, or the
  /// street.
  static void leave(BuildContext context) {
    final back = _returnTo;
    _returnTo = null;
    context.go(back ?? Routes.directory);
  }

  /// Opens a business from the center, as the platform: its home will say
  /// « Retour au centre admin ».
  static void openBusiness(BuildContext context, String orgId, {String? page}) {
    opened.value = (orgId: orgId, from: _here(context) ?? Routes.console);
    context.go(page ?? Routes.org(orgId));
  }

  /// « Retour au centre admin ».
  static void backToCenter(BuildContext context) {
    final from = opened.value?.from ?? Routes.console;
    opened.value = null;
    context.go(from);
  }

  /// Every new address (the router's redirect): the business the center
  /// opened is forgotten once the admin leaves it another way — another
  /// business, the picker, the street, the center itself, signed out — so
  /// its strip never shows again later, stale. A page pushed from inside
  /// it (its vitrine, Compte's language) keeps it.
  static void sawLocation(String location) {
    final o = opened.value;
    if (o == null) return;
    final home = Routes.org(o.orgId);
    if (location == home || location.startsWith('$home/')) return;
    if (location.startsWith('/o/') ||
        inCenter(location) ||
        location == Routes.picker ||
        location == Routes.directory ||
        location == Routes.signIn ||
        location == Routes.splash ||
        location == '/') {
      opened.value = null;
    }
  }
}

/// The strip across a business's home when the center opened it: whose it
/// is, and the way back to the center.
class AdminReturnBanner extends StatelessWidget {
  const AdminReturnBanner({super.key, required this.orgId, required this.child});

  final String orgId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AdminTrail.opened,
      builder: (context, opened, _) {
        // Not inside « Voir comme le commerçant » (106): that is the
        // owner's view, and the owner has no center to go back to.
        if (opened?.orgId != orgId || LookOnly.of(context)) return child;
        // A phone keeps the way back and drops the words before it.
        final narrow = MediaQuery.sizeOf(context).width < 400;
        return Column(
          children: [
            Material(
              key: const Key('admin-return'),
              color: maraDeep,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 18, color: maraCaramel),
                      const SizedBox(width: 8),
                      if (narrow)
                        const Spacer()
                      else
                        Expanded(
                          child: Text(
                            context.tr('Ouverte depuis le centre admin'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: maraPaper, fontSize: 13),
                          ),
                        ),
                      Flexible(
                        flex: narrow ? 8 : 1,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: maraCaramel,
                            minimumSize: const Size(48, 40),
                          ),
                          onPressed: () => AdminTrail.backToCenter(context),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: Text(context.tr('Retour au centre admin'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The strip took the status bar: the home under it must not
            // pad for it again.
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

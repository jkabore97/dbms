import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/tr.dart';
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
                constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 10 : 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 18, color: maraCaramel),
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

  /// The pill: into the center, remembering where from.
  static void enter(BuildContext context) {
    final here = _here(context);
    if (here != null && !here.startsWith(Routes.console)) _returnTo = here;
    context.push(Routes.console);
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
        if (opened?.orgId != orgId) return child;
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
                      Expanded(
                        child: Text(
                          context.tr('Ouverte depuis le centre admin'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: maraPaper, fontSize: 13),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: maraCaramel,
                          minimumSize: const Size(48, 40),
                        ),
                        onPressed: () => AdminTrail.backToCenter(context),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: Text(context.tr('Retour au centre admin'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../help/help_button.dart';

/// « Ma vitrine » (140) on the top bar of the shop's, the farm's and the
/// association's home, beside « Besoin d'aide »: the business's own vitrine
/// in one tap, as Plus › MA VITRINE › « Voir ma vitrine » opens it (that
/// entry stays). A vitrine not yet visible to customers opens all the same,
/// and says so there (StorefrontScreen's banner for its own people).
///
/// The storefront and its word; the icon alone when the room is small —
/// the width over the text scale under 360, as the help button
/// ([HelpButton.iconOnly]) — its word then in the tooltip and for a screen
/// reader. For the business's own people: not for a trainer's look-only
/// access (an observer), nor for Mara's admin in someone's business, whose
/// bar carries « Admin » already — both keep Plus's entry.
class VitrineButton extends StatelessWidget {
  const VitrineButton({super.key, required this.org});

  final OrgSummary org;

  static bool shownFor(BuildContext context, OrgSummary org) {
    if ((org.slug ?? '').isEmpty || org.isObserverOnly) return false;
    final platformOnly = org.roles.isNotEmpty && org.roles.every((r) => r == 'platform_admin');
    return !platformOnly && !(AppScope.maybeOf(context)?.session.isPlatformAdmin ?? false);
  }

  @override
  Widget build(BuildContext context) {
    if (!shownFor(context, org)) return const SizedBox.shrink();
    final label = context.tr('Ma vitrine');
    final theme = Theme.of(context);
    final ink = theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
    void open() => context.go(Routes.storefront(org.slug!));
    if (HelpButton.iconOnly(context)) {
      return IconButton(
        key: const Key('home-vitrine'),
        tooltip: label,
        onPressed: open,
        icon: const Icon(Icons.storefront_outlined),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: label,
        child: TextButton.icon(
          key: const Key('home-vitrine'),
          style: TextButton.styleFrom(
            foregroundColor: ink,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(48, 40),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: open,
          icon: const Icon(Icons.storefront_outlined, size: 20),
          label: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: Text(label,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}

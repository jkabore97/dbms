import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../help/help_button.dart';
import 'vitrine_sheet.dart';

/// « Ma vitrine » (140) on the top bar of the shop's, the farm's and the
/// association's home, beside « Besoin d'aide »: since 146 the vitrine's
/// entry point — a sheet ([VitrineSheet]) to see it (as Plus › MA VITRINE ›
/// « Voir ma vitrine » opens it; that entry stays), customise it, share it
/// and put it forward. A vitrine not yet visible to customers says so first.
///
/// The storefront and its word; the icon alone when the room is small —
/// the width over the text scale under 360, as the help button
/// ([HelpButton.iconOnly]) — its word then in the tooltip and for a screen
/// reader. For the business's own people: not for a trainer's look-only
/// access (an observer), nor for Mara's admin in someone's business, whose
/// bar carries « Admin » already — both keep Plus's entry.
class VitrineButton extends StatelessWidget {
  const VitrineButton({super.key, required this.org, this.onChanged});

  final OrgSummary org;

  /// Called when the person comes back from what they picked in the sheet
  /// (the vitrine customised, articles added…): the home reads its path
  /// and its gates again, so the next step shows without a refresh.
  final Future<void> Function()? onChanged;

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
    // The vitrine's entry point (146): see it, customise it, share it,
    // put it forward — [VitrineSheet].
    Future<void> open() async {
      final session = AppScope.maybeOf(context)?.session;
      final picked = await VitrineSheet.open(context, org);
      if (picked == null || picked == VitrineAction.view) return;
      await session?.reloadFeatures(org.id);
      if (context.mounted) await onChanged?.call();
    }
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

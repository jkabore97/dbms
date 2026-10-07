import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/console/fiche_repository.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/theme/mara_mark.dart';

/// The pieces every tab of the fiche entreprise draws with: a heading, a
/// number first, the line that says Mara is the one changing things, and
/// the « Annuler » that follows every change.

/// A heading above a group: small capitals, graphite.
class FicheHeading extends StatelessWidget {
  const FicheHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One number, big, with what it counts under it. Tappable when it leads
/// somewhere.
class FicheFigure extends StatelessWidget {
  const FicheFigure({
    super.key,
    required this.value,
    required this.label,
    this.hint,
    this.colour,
    this.onTap,
    this.width = 172,
  });

  final String value;
  final String label;
  final String? hint;
  final Color? colour;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = colour ?? maraDeep;
    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: theme.textTheme.bodySmall),
                if (hint != null)
                  Text(hint!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: maraBrown)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// « Vous modifiez … en tant que Mara »: graphite, caramel, unmistakable —
/// above every place of the fiche that writes to the business itself.
class MaraAsBanner extends StatelessWidget {
  const MaraAsBanner({super.key, required this.title, required this.line});

  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('mara-as-banner'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: maraDeep,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.admin_panel_settings_outlined, color: maraCaramel),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: maraCaramel, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(line,
                    style: theme.textTheme.bodySmall?.copyWith(color: maraPaper)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// After a change: what was done, and « Annuler » for as long as the bar
/// shows. [actionId] null (nothing moved) says so instead.
void showUndoBar(
  BuildContext context, {
  required FicheRepository fiche,
  required String? actionId,
  required String done,
  VoidCallback? onUndone,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final undone = context.tr('Annulé.');
  final nothing = context.tr('Rien n\'a changé.');
  final undoLabel = context.tr('Annuler');
  messenger.hideCurrentSnackBar();
  if (actionId == null) {
    messenger.showSnackBar(SnackBar(content: Text(nothing)));
    return;
  }
  messenger.showSnackBar(SnackBar(
    content: Text(done),
    duration: const Duration(seconds: 8),
    action: SnackBarAction(
      key: const Key('undo-bar'),
      label: undoLabel,
      onPressed: () async {
        try {
          await fiche.undo(actionId);
          messenger.showSnackBar(SnackBar(content: Text(undone)));
          onUndone?.call();
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
        }
      },
    ),
  ));
}

/// « Active », « Silencieuse »… and its colour, as the console's rows say it.
({String label, Color colour}) healthOf(BuildContext context, String health) =>
    switch (health) {
      'healthy' => (label: context.tr('Active'), colour: const Color(0xFF0E7A63)),
      'slowing' => (label: context.tr('Ralentit'), colour: const Color(0xFFA96A0B)),
      'silent' => (label: context.tr('Silencieuse'), colour: const Color(0xFFB1541A)),
      'archived' => (label: context.tr('Archivée'), colour: maraGrey),
      _ => (label: context.tr('Jamais utilisée'), colour: const Color(0xFFB03B3B)),
    };

/// « aujourd'hui », « hier », « il y a 4 j », or the day.
String sinceLine(BuildContext context, DateTime? at) {
  if (at == null) return '—';
  final days = DateTime.now().difference(at.toLocal()).inDays;
  if (days <= 0) return context.tr('aujourd\'hui');
  if (days == 1) return context.tr('hier');
  if (days < 30) return context.tr('il y a {n} j', {'n': days});
  return DateFormat('d MMM y', context.trLanguage == 'en' ? 'en' : 'fr_FR')
      .format(at.toLocal());
}

String dayLine(BuildContext context, DateTime at) =>
    DateFormat('dd/MM/yyyy').format(at.toLocal());

/// The fiche's pages, kept to a readable width on a computer.
class FicheWidth extends StatelessWidget {
  const FicheWidth({super.key, required this.child, this.max = 1080});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: child,
        ),
      );
}

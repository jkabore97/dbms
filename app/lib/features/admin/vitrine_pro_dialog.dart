import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';

/// What a Basic business answered « Ces choix viennent avec Mara Pro »
/// with (146).
enum VitrineProAnswer { pro, save }

/// The Pro choices made, in one line: « Liste · 3 articles en tête ·
/// Épuisés masqués ». Empty when none is made.
String vitrineProChoicesLine(BuildContext context, StorefrontStyle style) {
  final parts = <String>[
    if (style.layout != VitrineLayout.grid) vitrineLayoutLabel(context, style.layout),
    if (style.pinned.length == 1) context.tr('1 article en tête'),
    if (style.pinned.length > 1)
      context.tr('{n} articles en tête', {'n': style.pinned.length}),
    if (style.hideOutOfStock) context.tr('Épuisés masqués'),
  ];
  return parts.join(' · ');
}

/// A layout's name, as the vitrine settings offer it.
String vitrineLayoutLabel(BuildContext context, VitrineLayout l) => switch (l) {
      VitrineLayout.grid => context.tr('Grille'),
      VitrineLayout.large => context.tr('Grandes photos'),
      VitrineLayout.list => context.tr('Liste'),
      VitrineLayout.menu => context.tr('Menu'),
    };

/// « Ces choix viennent avec Mara Pro » (146): what « Enregistrer la
/// vitrine » says first when a Basic business made Pro choices — the
/// choices, that the vitrine stays a grid without Pro, whether they are
/// kept, and two ways: « Passer à Pro » (the Pro sheet) and « Enregistrer
/// sans les options Pro ».
///
/// [canBuy]: the person may buy Pro — anybody else reads « Demandez au
/// propriétaire de passer à Pro », as batch 143's help pop-up. [sellsPro]:
/// the build sells Pro ([sellsProInApp]); in the iPhone app before the App
/// Store sells it, no Pro button and no invitation (Apple's rule, 125).
/// [kept]: the server keeps the choices (141) — said only then; before
/// 141 the dialog says plainly that they are not.
class VitrineProDialog extends StatelessWidget {
  const VitrineProDialog({
    super.key,
    required this.choices,
    required this.canBuy,
    required this.sellsPro,
    required this.kept,
  });

  final String choices;
  final bool canBuy;
  final bool sellsPro;
  final bool kept;

  static Future<VitrineProAnswer?> show(
    BuildContext context, {
    required String choices,
    required bool canBuy,
    required bool sellsPro,
    required bool kept,
  }) =>
      showDialog<VitrineProAnswer>(
        context: context,
        builder: (_) => VitrineProDialog(
          choices: choices,
          canBuy: canBuy,
          sellsPro: sellsPro,
          kept: kept,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return AlertDialog(
      key: const Key('vitrine-pro-dialog'),
      scrollable: true,
      icon: const Icon(Icons.workspace_premium, color: maraCaramel, size: 30),
      title: Text(
        context.tr('Ces choix viennent avec Marakaj Pro'),
        key: const Key('vitrine-pro-dialog-title'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('vitrine-pro-dialog-choices'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              choices,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            kept
                // The iPhone app before the App Store sells Pro (125): what
                // Pro includes is said, never an invitation to go to it.
                ? sellsPro
                    ? context.tr(
                        'Sans Pro, votre vitrine reste en grille. Vos choix sont gardés : ils s\'activent dès que vous passez à Pro.')
                    : context.tr(
                        'Sans Pro, votre vitrine reste en grille. Vos choix sont gardés : ils font partie de Marakaj Pro.')
                : context.tr(
                    'Sans Pro, votre vitrine reste en grille. Pour le moment, ces choix ne peuvent pas être gardés : il faudra les refaire une fois Pro activé.'),
            key: const Key('vitrine-pro-dialog-body'),
            textAlign: TextAlign.center,
            style: muted,
          ),
          if (sellsPro && !canBuy) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('Demandez au propriétaire de passer à Pro'),
              key: const Key('vitrine-pro-dialog-ask'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        if (sellsPro && canBuy)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('vitrine-pro-dialog-pro'),
              style: FilledButton.styleFrom(
                backgroundColor: maraCaramel,
                foregroundColor: maraDeep,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.of(context).pop(VitrineProAnswer.pro),
              icon: const Icon(Icons.workspace_premium),
              label: Text(
                context.tr('Passer à Pro'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('vitrine-pro-dialog-save'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).pop(VitrineProAnswer.save),
            child: Text(
              context.tr('Enregistrer sans les options Pro'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/theme/mara_mark.dart';

/// « Vous êtes ici pour… » (134): one question, right after sign-up — the
/// door to « Créer mon activité » for the person who never looks at the
/// buttons (mockup 1, screen 3).
///
/// Acheter → the market; Vendre ou gérer → the creation form itself
/// (Routes.createBusiness, not the join-or-create page); Livrer → the
/// courier's application; « Je choisirai plus tard » → the market. Asked
/// once per account (arrival_answer, 131) and never of somebody who
/// already has a business (arrival_pending says no, the market never
/// opens it).
class ArrivalScreen extends StatefulWidget {
  const ArrivalScreen({super.key, required this.shopper});

  final ShopperRepository shopper;

  @override
  State<ArrivalScreen> createState() => _ArrivalScreenState();
}

class _ArrivalScreenState extends State<ArrivalScreen> {
  String _choice = 'sell';
  bool _busy = false;

  /// Answered, by a button or by going back.
  bool _answered = false;

  Future<void> _go(String intent) async {
    if (_busy) return;
    _answered = true;
    setState(() => _busy = true);
    await widget.shopper.answerArrival(intent);
    if (!mounted) return;
    final to = switch (intent) {
      'sell' => Routes.createBusiness,
      'deliver' => Routes.becomeCourier,
      _ => Routes.directory,
    };
    // `go` from the question: back from the creation form is the market,
    // never the question again.
    context.go(to);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [
      (
        key: 'buy',
        icon: Icons.shopping_bag_outlined,
        title: context.tr('Acheter'),
        detail: context.tr('Les boutiques près de moi'),
      ),
      (
        key: 'sell',
        icon: Icons.storefront_outlined,
        title: context.tr('Vendre ou gérer'),
        detail: context.tr('Boutique, ferme, association'),
      ),
      (
        key: 'deliver',
        icon: Icons.sports_motorsports_outlined,
        title: context.tr('Livrer'),
        detail: context.tr('Devenir livreur'),
      ),
    ];
    // Back (the phone's button, a swipe) is « plus tard »: answered, so
    // the question is not put again at the next start (134's review).
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_answered) {
          _answered = true;
          widget.shopper.answerArrival('later');
        }
      },
      child: Scaffold(
        key: const Key('arrival'),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: MaraWordmark(height: 30),
                  ),
                  const SizedBox(height: 32),
                  Text(context.tr('Bienvenue !'),
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(context.tr('Vous êtes ici pour…'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  for (final o in options) ...[
                    _Option(
                      key: Key('arrival-${o.key}'),
                      icon: o.icon,
                      title: o.title,
                      detail: o.detail,
                      selected: _choice == o.key,
                      onTap: _busy ? null : () => setState(() => _choice = o.key),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('arrival-continue'),
                      onPressed: _busy ? null : () => _go(_choice),
                      style: FilledButton.styleFrom(
                        backgroundColor: maraDeep,
                        foregroundColor: maraPaper,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(context.tr('Continuer'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('arrival-later'),
                    onPressed: _busy ? null : () => _go('later'),
                    child: Text(context.tr('Je choisirai plus tard')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: selected ? maraDeep : scheme.outlineVariant,
              width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected ? maraDeep : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: selected ? maraPaper : scheme.onSurface),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(detail,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? maraDeep : scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

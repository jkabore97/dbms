import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/console/command_center.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/router.dart';
import '../../../core/theme/mara_sheet.dart';
import 'reports_sheet.dart';

/// « À vérifier » (146, batch 151): one place in « Aujourd'hui » for what
/// needs Mara's look against fraud — businesses with many blocked or
/// refused orders, couriers over the cash cap, large till gaps — and two
/// links to what already has its own place (the reports in Signalements,
/// the couriers waiting in Livreurs), never drawn twice.
class ReviewQueueSheet extends StatefulWidget {
  const ReviewQueueSheet({super.key, required this.center, required this.outer});

  final CommandCenterRepository center;

  /// The page under the sheet, where a business's fiche or Livreurs opens.
  final BuildContext outer;

  static Future<void> open(BuildContext context, CommandCenterRepository center) => showMaraSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ReviewQueueSheet(center: center, outer: context),
      );

  @override
  State<ReviewQueueSheet> createState() => _ReviewQueueSheetState();
}

class _ReviewQueueSheetState extends State<ReviewQueueSheet> {
  ReviewQueue? _q;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await widget.center.reviewQueue();
      if (mounted) setState(() => _q = q);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  void _go(String route) {
    Navigator.of(context).pop();
    widget.outer.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q;
    Widget head(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Text(text.toUpperCase(),
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        key: const Key('review-sheet'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(context.tr('À vérifier'),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text(context.tr('Ce que les protections contre la fraude ont relevé'),
              style: theme.textTheme.bodyMedium),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!))
          else if (q == null)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // The two that live elsewhere: links, counted.
            const SizedBox(height: 8),
            ListTile(
              key: const Key('review-reports'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: Text(context.tr('Signalements à lire · {n}', {'n': q.reportsOpen})),
              subtitle: Text(context.tr('vitrines, commandes, paiements signalés par les clients')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).pop();
                showReportsSheet(widget.outer, center: widget.center);
              },
            ),
            ListTile(
              key: const Key('review-couriers-pending'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sports_motorsports_outlined),
              title: Text(context.tr('Livreurs à valider · {n}', {'n': q.couriersPending})),
              subtitle: Text(context.tr('pièces à regarder, valider ou suspendre')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _go(Routes.consoleCouriers),
            ),
            head(context.tr('Activités : commandes bloquées ou refusées')),
            if (q.businesses.isEmpty)
              Text(context.tr('Aucune : moins de 3 clients bloqués en 30 jours et de 5 commandes refusées en 7 jours partout.'),
                  style: theme.textTheme.bodySmall)
            else
              for (final b in q.businesses)
                ListTile(
                  key: Key('review-business-${b.orgId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(b.name),
                  subtitle: Text([
                    b.blocks == 1
                        ? context.tr('1 client bloqué en 30 j')
                        : context.tr('{n} clients bloqués en 30 j', {'n': b.blocks}),
                    b.refused == 1
                        ? context.tr('1 commande refusée en 7 j')
                        : context.tr('{n} commandes refusées en 7 j', {'n': b.refused}),
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _go(Routes.consoleOrg(b.orgId)),
                ),
            head(context.tr('Livreurs au-delà du plafond d\'espèces')),
            if (q.couriers.isEmpty)
              Text(
                  q.cashCap == null || q.cashCap == 0
                      ? context.tr('Aucun plafond n\'est fixé (Réglages › Sécurité).')
                      : context.tr('Aucun : chaque livreur porte moins de {cap}.',
                          {'cap': moneyFormat('XOF').format(q.cashCap)}),
                  style: theme.textTheme.bodySmall)
            else
              for (final c in q.couriers)
                ListTile(
                  key: Key('review-courier-${c.userId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(c.name.isEmpty ? context.tr('Livreur') : c.name),
                  subtitle: Text(context.tr('{held} en main pour {cap} au plus', {
                    'held': moneyFormat(c.currency).format(c.held),
                    'cap': moneyFormat(c.currency).format(c.cap),
                  }) + ((c.phone ?? '').isEmpty ? '' : ' · ${c.phone}')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _go(Routes.consoleCouriers),
                ),
            head(context.tr('Écarts de caisse (7 jours)')),
            if (q.tills.isEmpty)
              Text(
                  q.tillGap == null || q.tillGap == 0
                      ? context.tr('Aucun seuil n\'est fixé (Réglages › Sécurité).')
                      : context.tr('Aucun écart de {gap} ou plus.',
                          {'gap': moneyFormat('XOF').format(q.tillGap)}),
                  style: theme.textTheme.bodySmall)
            else
              for (final t in q.tills)
                ListTile(
                  key: Key('review-till-${t.orgId}-${t.day}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.point_of_sale_outlined),
                  title: Text(t.name),
                  subtitle: Text([
                    if (t.day != null) DateFormat('d MMM', context.trLocale).format(t.day!),
                    t.gap < 0
                        ? context.tr('il manque {amount}', {'amount': moneyFormat(t.currency).format(-t.gap)})
                        : context.tr('{amount} en trop', {'amount': moneyFormat(t.currency).format(t.gap)}),
                    if ((t.closer ?? '').isNotEmpty) t.closer!,
                  ].join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _go(Routes.consoleOrg(t.orgId)),
                ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import 'cauri_icon.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The grey « PRO · 400 » on a tool a Basic business has not opened (085):
/// the plan's mark and its price in cauris, side by side.
class ProCostBadge extends StatelessWidget {
  const ProCostBadge({super.key, this.cost});

  final int? cost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('pro-cost-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(context.tr('PRO'),
              style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          if (cost != null) ...[
            const SizedBox(width: 6),
            CaurisAmount(cost!,
                iconSize: 12,
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

/// The door on a Pro tool (085): open it for 30 days with cauris, see how
/// to earn the rest, or go to Mara Pro.
class UnlockSheet extends StatefulWidget {
  const UnlockSheet({
    super.key,
    required this.org,
    required this.feature,
    required this.states,
    required this.admin,
    this.onUnlocked,
  });

  final OrgSummary org;
  final String feature;
  final FeatureStates states;
  final AdminRepository admin;
  final Future<void> Function()? onUnlocked;

  /// Opens the sheet when the business's cauris prices are known; the
  /// comparison page otherwise (offline, or a database before 085).
  static Future<void> open(
    BuildContext context, {
    required OrgSummary org,
    required String feature,
  }) async {
    final scope = AppScope.read(context);
    final states = scope?.session.featuresFor(org.id);
    final tool = states?.toolOf(feature);
    // An association earns no cauris (084) but spends what Mara gives it
    // (100): the sheet once it has some, the plans otherwise.
    if (scope == null || states == null || tool == null ||
        (org.isAssociation && states.balance <= 0)) {
      await GoRouter.of(context).push(Routes.inside(org.id, 'kaj-pro'));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => UnlockSheet(
        org: org,
        feature: feature,
        states: states,
        admin: scope.admin,
        onUnlocked: () => scope.session.reloadFeatures(org.id),
      ),
    );
  }

  @override
  State<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<UnlockSheet> {
  bool _busy = false;
  String? _error;
  DateTime? _until;

  ToolState get _tool => widget.states.toolOf(widget.feature)!;
  int get _missing => (_tool.cost - widget.states.balance).clamp(0, 1 << 30);

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final until = await widget.admin.spendCauris(widget.org.id, widget.feature);
      await widget.onUnlocked?.call();
      if (mounted) setState(() => _until = until);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tool = _tool;
    final label = widget.feature == 'pro_all'
        ? context.tr('Mara Pro complet : tous les outils, sans limite')
        : PlanTerms.labelOf(widget.feature);
    final canBuy = widget.org.isAdmin && _missing == 0 && tool.waitsDays == null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const ProCostBadge(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_until != null) ...[
              Container(
                key: const Key('unlocked'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: maraDeep,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Ouvert jusqu\'au ${DateFormat('d MMMM', 'fr_FR').format(_until!.toLocal())}. '
                  'Bravo, vous l\'avez gagné !',
                  style: theme.textTheme.bodyLarge?.copyWith(color: maraPaper),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('Continuer')),
              ),
            ] else ...[
              Row(
                children: [
                  Text(context.tr('Débloquer 30 jours : '), style: theme.textTheme.bodyLarge),
                  CaurisAmount(tool.cost,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(context.tr('Vous en avez '), style: theme.textTheme.bodyMedium),
                  CaurisAmount(widget.states.balance,
                      style: theme.textTheme.bodyMedium),
                  if (_missing > 0)
                    Text(
                        widget.org.isAssociation
                            ? context.tr(' — il en manque {_missing}', {'_missing': _missing})
                            : context.tr(' — encore {_missing} à gagner', {'_missing': _missing}),
                        key: const Key('unlock-missing'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              if (tool.waitsDays != null) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr('Cet outil s\'ouvre avec des cauris dans {waitsDays} jours : il faut un peu d\'activité pour qu\'il serve.', {'waitsDays': tool.waitsDays}),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (!widget.org.isAdmin) ...[
                const SizedBox(height: 6),
                Text(context.tr('Le propriétaire ou un administrateur peut le débloquer.'),
                    style: theme.textTheme.bodySmall),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('unlock-buy'),
                  onPressed: canBuy && !_busy ? _unlock : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const CauriIcon(size: 18),
                  label: Text(context.tr('Débloquer avec mes cauris'),
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
              if (widget.org.isAdmin && !widget.org.isAssociation)
                OutlinedButton(
                  key: const Key('unlock-earn'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(Routes.inside(widget.org.id, 'chemin'));
                  },
                  child: Text(context.tr('Comment gagner des cauris')),
                ),
              TextButton(
                key: const Key('unlock-pro'),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(Routes.inside(widget.org.id, 'kaj-pro'));
                },
                child: Text(context.tr('Ou passer à Mara Pro')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

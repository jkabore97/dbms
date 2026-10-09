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
    this.fresh,
  });

  final OrgSummary org;
  final String feature;
  final FeatureStates states;
  final AdminRepository admin;
  final Future<void> Function()? onUnlocked;

  /// The wallet as the server says it now (108): the session's copy can be
  /// minutes old — a step just paid on Mon chemin, a gift from Mara — and a
  /// stale balance said « il en manque » to somebody who had enough.
  final Future<FeatureStates?> Function()? fresh;

  /// Opens the sheet when the business's cauris prices are known; the
  /// comparison page otherwise (offline, or a database before 085).
  static Future<void> open(
    BuildContext context, {
    required OrgSummary org,
    required String feature,
  }) async {
    final scope = AppScope.read(context);
    final router = GoRouter.of(context);
    var states = scope?.session.featuresFor(org.id);
    // An association earns no cauris (084) but spends what Mara gives it
    // (100): the sheet once it has some, the plans otherwise. Before
    // sending anybody to the plans, the server is asked again (108): a
    // gift from Mara a minute ago is in the wallet, not yet in the copy.
    bool noDoor(FeatureStates? s) =>
        s == null || s.toolOf(feature) == null || (org.isAssociation && s.balance <= 0);
    if (scope != null && noDoor(states)) {
      await scope.session.reloadFeatures(org.id);
      states = scope.session.featuresFor(org.id);
    }
    if (!context.mounted) return;
    final door = states;
    if (scope == null || door == null || noDoor(door)) {
      await router.push(Routes.inside(org.id, 'kaj-pro'));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UnlockSheet(
        org: org,
        feature: feature,
        states: door,
        admin: scope.admin,
        onUnlocked: () => scope.session.reloadFeatures(org.id),
        fresh: () async {
          await scope.session.reloadFeatures(org.id);
          return scope.session.featuresFor(org.id);
        },
      ),
    );
  }

  /// « Disponible avec vos cauris dans 23 jours », and the day: the wait a
  /// new business has before cauris open a tool (085), never a silent grey
  /// button (108).
  static String waitWords(BuildContext context, int days) =>
      context.tr('Disponible avec vos cauris dans {n} jours', {'n': days});

  static String waitDay(BuildContext context, int days) => context.tr('Le {date}.', {
        'date': DateFormat('d MMMM y', context.trLanguage == 'en' ? 'en' : 'fr_FR')
            .format(DateTime.now().add(Duration(days: days))),
      });

  @override
  State<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<UnlockSheet> {
  bool _busy = false;
  String? _error;
  DateTime? _until;

  late FeatureStates _states = widget.states;

  /// Asking the server for the wallet as it is now.
  late bool _reading = widget.fresh != null;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final fresh = widget.fresh;
    if (fresh == null) return;
    FeatureStates? s;
    try {
      s = await fresh();
    } catch (_) {
      // No signal: the copy in hand stands; the server still decides.
    }
    if (!mounted) return;
    setState(() {
      if (s?.toolOf(widget.feature) != null) _states = s!;
      _reading = false;
    });
  }

  ToolState get _tool => _states.toolOf(widget.feature)!;
  int get _missing => (_tool.cost - _states.balance).clamp(0, 1 << 30);

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
    final waits = tool.waitsDays;
    final canBuy = widget.org.isAdmin && !_reading && _missing == 0 && waits == null;
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
                  context.tr('Ouvert jusqu\'au {date}. Bravo, vous l\'avez gagné !',
                      {'date': DateFormat('d MMMM', intlLocale()).format(_until!.toLocal())}),
                  style: theme.textTheme.bodyLarge?.copyWith(color: maraPaper),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('Continuer')),
              ),
            ] else ...[
              // Wraps rather than overflows on a narrow phone or in a long
              // language.
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.tr('Débloquer 30 jours : '), style: theme.textTheme.bodyLarge),
                  CaurisAmount(tool.cost,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.tr('Vous en avez '), style: theme.textTheme.bodyMedium),
                  CaurisAmount(_states.balance,
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
              // The wait, unmistakable (108): its days and its day, on the
              // page and on the button.
              if (waits != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('unlock-wait'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: maraCaramel.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_bottom, color: maraBrown),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${UnlockSheet.waitWords(context, waits)}. ${UnlockSheet.waitDay(context, waits)} '
                          '${context.tr('Il faut un peu d\'activité pour que cet outil serve.')}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
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
                  // Every reason it cannot be bought now, on the button
                  // itself (108).
                  label: Text(
                      waits != null
                          ? context.tr('Disponible dans {n} jours', {'n': waits})
                          : _reading
                              ? context.tr('Vos cauris…')
                              : _missing > 0
                                  ? context.tr('Il vous manque {n} cauris', {'n': _missing})
                                  : context.tr('Débloquer avec mes cauris'),
                      textAlign: TextAlign.center,
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

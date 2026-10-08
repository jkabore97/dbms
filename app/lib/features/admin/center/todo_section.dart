import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/admin/admin_repository.dart';
import '../../../core/console/command_center.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/router.dart';
import '../../../core/theme/mara_mark.dart';
import '../../auth/org_picker_screen.dart' show iconForProfile, kindColour, kindInk, kindPlural;
import '../console_today.dart';
import 'center_search.dart' show orderStatusLabel;

/// « À faire » (105): the center's first page. What waits on the platform
/// and what ends within seven days, as numbers to tap — each opens the
/// screen that acts on it, or the list of the businesses behind it — then
/// the month's money, the growth and the health (072's figures).
class TodoSection extends StatefulWidget {
  const TodoSection({super.key, required this.center, required this.admin});

  final CommandCenterRepository center;
  final AdminRepository admin;

  @override
  State<TodoSection> createState() => _TodoSectionState();
}

class _TodoSectionState extends State<TodoSection> {
  PlatformTodo? _todo;
  String? _error;
  bool _loading = true;
  final _today = GlobalKey<ConsoleTodayState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final todo = await widget.center.todo();
      if (!mounted) return;
      setState(() {
        _todo = todo;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _list(String key, String title) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => TodoListSheet(
          center: widget.center,
          listKey: key,
          title: title,
          outer: context,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _todo ?? const PlatformTodo({});
    final spots = t['spots_paid'] + t['spots_asked'];
    final waiting = <_Count>[
      _Count('applications', t['applications'], context.tr('Demandes d\'entreprise'),
          Icons.assignment_ind_outlined, () => context.go(Routes.applications)),
      _Count('pro_paid', t['pro_paid'], context.tr('« J\'ai payé » Mara Pro à confirmer'),
          Icons.workspace_premium_outlined, () => context.go(Routes.consolePro)),
      _Count('spots', spots, context.tr('Mises en avant à traiter'), Icons.campaign_outlined,
          () => context.go(Routes.consoleFeatured),
          hint: t['spots_paid'] > 0
              ? context.tr('dont {n} « J\'ai payé »', {'n': t['spots_paid']})
              : null),
      _Count('couriers', t['couriers'], context.tr('Livreurs à valider'),
          Icons.sports_motorsports_outlined, () => context.go(Routes.consoleCouriers)),
      _Count('orders_stuck', t['orders_stuck'], context.tr('Commandes bloquées'),
          Icons.timer_outlined,
          () => _list('orders_stuck', context.tr('Commandes bloquées')),
          hint: context.tr('en attente depuis 2 h, ou en route depuis 3 h')),
      _Count('payouts_failed', t['payouts_failed'], context.tr('Versements Wave échoués'),
          Icons.sync_problem_outlined, () => context.go(Routes.consoleWave),
          warn: true),
      // A Pro tool a rule hides, back to hidden when its payment ended (104):
      // its owner was told; Mara may want to call.
      _Count('features_lapsed', t['features_lapsed'],
          context.tr('Fonctions masquées après la fin d\'un paiement'),
          Icons.visibility_off_outlined,
          () => _list('features_lapsed',
              context.tr('Fonctions masquées après la fin d\'un paiement'))),
      _Count('silent_30', t['silent_30'], context.tr('Silencieuses depuis 30 jours'),
          Icons.bedtime_outlined,
          () => context.go('${Routes.consoleBusinesses}?activite=silent30'),
          hint: context.tr('à rappeler')),
    ];
    final ending = <_Count>[
      _Count('plans_ending', t['plans_ending'], context.tr('Mara Pro qui se termine'),
          Icons.event_busy_outlined,
          () => _list('plans_ending', context.tr('Mara Pro qui se termine'))),
      _Count('unlocks_ending', t['unlocks_ending'], context.tr('Outils ouverts qui se ferment'),
          Icons.lock_clock_outlined,
          () => _list('unlocks_ending', context.tr('Outils ouverts qui se ferment'))),
      _Count('promos_ending', t['promos_ending'], context.tr('Cauris offerts qui expirent'),
          Icons.hourglass_bottom_outlined,
          () => _list('promos_ending', context.tr('Cauris offerts qui expirent'))),
      _Count('spots_ending', t['spots_ending'], context.tr('Mises en avant qui finissent'),
          Icons.campaign_outlined,
          () => _list('spots_ending', context.tr('Mises en avant qui finissent'))),
      _Count('rules_ending', t['rules_ending'], context.tr('Réglages de fonctions qui expirent'),
          Icons.toggle_on_outlined,
          () => _list('rules_ending', context.tr('Réglages de fonctions qui expirent'))),
    ];
    final open = t.waiting;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('À faire')),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _loading
                ? null
                : () {
                    _today.currentState?.reload();
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_loading && _todo == null) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(_error!),
                  trailing: TextButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                ),
              ),
            _Heading(context.tr('À traiter'),
                trailing: open == 0 ? context.tr('rien n\'attend') : '$open'),
            _Grid(counts: waiting),
            const SizedBox(height: 20),
            _Heading(context.tr('Dans les 7 jours')),
            _Grid(counts: ending),
            const SizedBox(height: 24),
            ConsoleToday(key: _today, admin: widget.admin),
          ],
        ),
      ),
    );
  }
}

class _Count {
  const _Count(this.key, this.n, this.label, this.icon, this.onTap,
      {this.hint, this.warn = false});

  final String key;
  final int n;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? hint;
  final bool warn;
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (trailing != null)
            Text(trailing!,
                style: theme.textTheme.labelLarge?.copyWith(color: maraBrown)),
        ],
      ),
    );
  }
}

/// Numbers first: two to a row on a phone, four on a computer.
class _Grid extends StatelessWidget {
  const _Grid({required this.counts});

  final List<_Count> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final per = box.maxWidth >= 900 ? 4 : box.maxWidth >= 560 ? 3 : 2;
      final w = (box.maxWidth - (per - 1) * 10) / per;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in counts)
            SizedBox(
              width: w,
              child: Material(
                key: Key('todo-${c.key}'),
                color: c.n == 0
                    ? theme.colorScheme.surfaceContainerLow
                    : c.warn
                        ? theme.colorScheme.errorContainer
                        : maraPaper,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: c.n == 0 ? null : c.onTap,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 112),
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: c.n == 0
                            ? theme.colorScheme.outlineVariant
                            : c.warn
                                ? theme.colorScheme.error
                                : maraCaramel,
                        width: c.n == 0 ? 1 : 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${c.n}',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: c.n == 0 ? theme.colorScheme.onSurfaceVariant : maraBlack,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const Spacer(),
                            Icon(c.icon,
                                color: c.n == 0 ? theme.colorScheme.onSurfaceVariant : maraBrown),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(c.label,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: c.n == 0 ? theme.colorScheme.onSurfaceVariant : null)),
                        if (c.hint != null && c.n > 0)
                          Text(c.hint!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: maraBrown)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// A feature's name, short: the switchboard's (104) and the Pro tools'.
String featureName(BuildContext context, String key) => switch (key) {
      'invoices' => context.tr('Factures'),
      'credits' => context.tr('Carnet de crédit'),
      'corrections' => context.tr('Corrections'),
      'production' => context.tr('Production'),
      'tontines' => context.tr('Tontines'),
      'payroll' => context.tr('Paie et journées'),
      'analytics' => context.tr('Analyses'),
      'accounting' => context.tr('Comptabilité'),
      'team_access' => context.tr('Accès de l\'équipe'),
      'currencies' => context.tr('Devises'),
      'vitrine_plus' => context.tr('Vitrine personnalisée'),
      'delivery' => context.tr('Livraison'),
      'online_payment' => context.tr('Paiement en ligne'),
      'pro_all' => context.tr('Mara Pro complet'),
      _ => key,
    };

/// The businesses behind one count (platform_todo_list): each opens its
/// fiche; a kind's rule opens the types of business.
class TodoListSheet extends StatefulWidget {
  const TodoListSheet({
    super.key,
    required this.center,
    required this.listKey,
    required this.title,
    required this.outer,
  });

  final CommandCenterRepository center;
  final String listKey;
  final String title;
  final BuildContext outer;

  @override
  State<TodoListSheet> createState() => _TodoListSheetState();
}

class _TodoListSheetState extends State<TodoListSheet> {
  List<TodoRow>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.center.todoList(widget.listKey).then((r) {
      if (mounted) setState(() => _rows = r);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = describeError(e));
    });
  }

  String _line(BuildContext context, TodoRow r) {
    final day = r.at == null ? '' : DateFormat('dd/MM').format(r.at!);
    return switch (widget.listKey) {
      'plans_ending' => context.tr('Mara Pro jusqu\'au {date}', {'date': day}),
      'unlocks_ending' => context.tr('{tool} jusqu\'au {date}{gift}', {
          'tool': featureName(context, r.feature ?? ''),
          'date': day,
          'gift': r.gift ? context.tr(' · offert par Mara') : '',
        }),
      'promos_ending' =>
        context.tr('{n} cauris à utiliser avant le {date}', {'n': r.points ?? 0, 'date': day}),
      'spots_ending' => r.spot == 'article'
          ? context.tr('Un article à la une jusqu\'au {date}', {'date': day})
          : context.tr('La boutique à la une jusqu\'au {date}', {'date': day}),
      'rules_ending' => context.tr('{feature} : {state} jusqu\'au {date}', {
          'feature': featureName(context, r.feature ?? ''),
          'state': r.state == 'hidden' ? context.tr('masquée') : context.tr('visible'),
          'date': day,
        }),
      'orders_stuck' => [
          ?r.customer,
          orderStatusLabel(context, r.status ?? ''),
          if (r.amount != null) moneyFormat(r.currency ?? 'XOF').format(r.amount),
          if (r.at != null) DateFormat('dd/MM HH:mm').format(r.at!),
        ].join(' · '),
      'payouts_failed' => [
          if (r.amount != null) moneyFormat(r.currency ?? 'XOF').format(r.amount),
          ?r.error,
        ].join(' · '),
      'silent_30' => context.tr('Rien depuis le {date}', {'date': day}),
      'features_lapsed' => context.tr('{tool} n\'est plus visible depuis le {date}', {
          'tool': featureName(context, r.feature ?? ''),
          'date': day,
        }),
      _ => day,
    };
  }

  void _open(TodoRow r) {
    Navigator.of(context).pop();
    final org = r.orgId;
    if (org == null) {
      widget.outer.go(Routes.consoleKinds);
    } else if (widget.listKey == 'features_lapsed') {
      // Straight to the business's switches.
      widget.outer.push('${Routes.consoleOrg(org)}?onglet=fonctions');
    } else {
      widget.outer.push(Routes.consoleOrg(org));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (rows == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(context.tr('Plus rien ici.')),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final r in rows)
                      ListTile(
                        minVerticalPadding: 12,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: kindColour(r.profile ?? r.kind ?? ''),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(iconForProfile(r.profile ?? r.kind ?? ''),
                              color: kindInk(r.profile ?? r.kind ?? '')),
                        ),
                        title: Text(
                          r.orgName ?? context.tr('Toutes les {kind}', {
                            'kind': kindPlural(context, r.kind ?? '').toLowerCase(),
                          }),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(_line(context, r)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(r),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
import 'reports_sheet.dart';
import 'review_sheet.dart';
import '../../../core/notify/bell_room.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';

/// « Aujourd'hui » (105, folded in 135): « Qu'est-ce qui m'attend ? ».
/// A greeting, four numbers (a tap: the analyses), then « VOUS ATTEND »:
/// only the counters that are not zero, the most urgent first, each
/// opening what acts on it or the list of the businesses behind it. The
/// counters at zero fold into one green line that opens on a tap. The
/// month's figures (072) are folded at the foot.
class TodoSection extends StatefulWidget {
  const TodoSection({super.key, required this.center, required this.admin, this.name});

  final CommandCenterRepository center;
  final AdminRepository admin;

  /// The admin's name, for « Bonjour … »: its first word.
  final String? name;

  @override
  State<TodoSection> createState() => _TodoSectionState();
}

class _TodoSectionState extends State<TodoSection> {
  PlatformTodo? _todo;
  PlatformToday? _today;
  PlatformOverview? _overview;
  TodayCounts? _counts132;
  String? _error;
  bool _loading = true;
  bool _zerosOpen = false;
  final _figures = GlobalKey<ConsoleTodayState>();

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
    // The four numbers: what the server has, never a number made up.
    if (!widget.center.isConfigured) return;
    try {
      final today = await widget.center.today();
      if (mounted) setState(() => _today = today);
    } catch (_) {}
    try {
      final overview = await widget.center.overview();
      if (mounted) setState(() => _overview = overview);
    } catch (_) {}
    // The new accounts and today's orders (132); without 132, null: the
    // new businesses and the seven days' orders stand in their place.
    try {
      final counts = await widget.center.todayCounts();
      if (mounted) setState(() => _counts132 = counts);
    } catch (_) {}
  }

  Future<void> _list(String key, String title) => showMaraSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => TodoListSheet(
          center: widget.center,
          listKey: key,
          title: title,
          outer: context,
        ),
      );

  /// Each of the fourteen counters (sixteen with 133's two help ones): its
  /// words and what a tap opens — the
  /// same as « À faire » opened before (105).
  Map<String, _Count> _counts(BuildContext context, PlatformTodo t) {
    final list = <_Count>[
      _Count('orders_stuck', context.tr('Commandes bloquées'), Icons.timer_outlined,
          () => _list('orders_stuck', context.tr('Commandes bloquées')),
          hint: context.tr('en attente depuis 2 h, ou en route depuis 3 h'), urgent: true),
      // 136: a Pro business waiting for a trainer for 30 open minutes.
      _Count('help_late', context.tr('Demandes d\'aide sans réponse'), Icons.support,
          () => context.go(Routes.consoleHelp),
          hint: context.tr('aucun formateur ne l\'a prise, dans les heures d\'aide'), urgent: true),
      // « Signaler un problème » from the shopper's page (113).
      _Count('reports_open', context.tr('Signalements'), Icons.flag_outlined, () async {
        await showReportsSheet(context, center: widget.center);
        if (mounted) await _load();
      }, hint: context.tr('des clients, à lire'), urgent: true),
      // 146 (batch 151): what the fraud guards raised.
      _Count('review', context.tr('À vérifier : fraude'), Icons.policy_outlined, () async {
        await ReviewQueueSheet.open(context, widget.center);
        if (mounted) await _load();
      }, hint: context.tr('blocages, livreurs au plafond, écarts de caisse'), urgent: true),
      _Count('payouts_failed', context.tr('Versements Wave échoués'), Icons.sync_problem_outlined,
          () => context.go(Routes.consoleWave),
          hint: context.tr('à relancer dans Paiements'), urgent: true),
      _Count('pro_paid', context.tr('« J\'ai payé » Marakaj Pro à confirmer'),
          Icons.workspace_premium_outlined, () => context.go(Routes.consolePro),
          hint: context.tr('à vérifier sur Wave'), urgent: true),
      _Count('spots', context.tr('Mises en avant à traiter'), Icons.campaign_outlined,
          () => context.go(Routes.consoleFeatured),
          hint: t['spots_paid'] > 0
              ? context.tr('dont {n} « J\'ai payé »', {'n': t['spots_paid']})
              : context.tr('demandées par les boutiques'),
          urgent: true),
      // 139: a store payment of a spot that programmed nothing.
      _Count('spot_refunds', context.tr('Paiements de mise en avant à rembourser'),
          Icons.currency_exchange, () async {
        await showMaraSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => SpotRefundsSheet(center: widget.center),
        );
        if (mounted) await _load();
      }, hint: context.tr('dans Play Console ou auprès d\'Apple'), urgent: true),
      // 136: the other open help requests — taken, or not late yet.
      _Count('help_open', context.tr('Demandes d\'aide ouvertes'), Icons.support_agent_outlined,
          () => context.go(Routes.consoleHelp),
          hint: context.tr('l\'équipe de formation s\'en occupe')),
      _Count('couriers', context.tr('Livreurs à valider'), Icons.sports_motorsports_outlined,
          () => context.go(Routes.consoleCouriers),
          hint: context.tr('pièces envoyées')),
      // Businesses people created themselves, or Mara did (111): no
      // request waits for approval any more — the new ones to welcome.
      _Count('new_7', context.tr('Nouvelles activités (7 j)'), Icons.add_business_outlined,
          () => _list('new_7', context.tr('Nouvelles activités (7 j)')),
          hint: context.tr('à accueillir')),
      _Count('silent_30', context.tr('Silencieuses depuis 30 jours'), Icons.bedtime_outlined,
          () => context.go('${Routes.consoleBusinesses}?activite=silent30'),
          hint: context.tr('à rappeler')),
      // A Pro tool a rule hides, back to hidden when its payment ended (104):
      // its owner was told; Mara may want to call.
      _Count('features_lapsed', context.tr('Fonctions masquées après la fin d\'un paiement'),
          Icons.visibility_off_outlined,
          () => _list('features_lapsed',
              context.tr('Fonctions masquées après la fin d\'un paiement')),
          hint: context.tr('le propriétaire est prévenu')),
      _Count('plans_ending', context.tr('Marakaj Pro qui se termine'), Icons.event_busy_outlined,
          () => _list('plans_ending', context.tr('Marakaj Pro qui se termine')),
          hint: context.tr('dans les 7 jours')),
      _Count('unlocks_ending', context.tr('Outils ouverts qui se ferment'),
          Icons.lock_clock_outlined,
          () => _list('unlocks_ending', context.tr('Outils ouverts qui se ferment')),
          hint: context.tr('dans les 7 jours')),
      _Count('promos_ending', context.tr('Cauris offerts qui expirent'),
          Icons.hourglass_bottom_outlined,
          () => _list('promos_ending', context.tr('Cauris offerts qui expirent')),
          hint: context.tr('dans les 7 jours')),
      _Count('spots_ending', context.tr('Mises en avant qui finissent'), Icons.campaign_outlined,
          () => _list('spots_ending', context.tr('Mises en avant qui finissent')),
          hint: context.tr('dans les 7 jours')),
      _Count('rules_ending', context.tr('Réglages de fonctions qui expirent'),
          Icons.toggle_on_outlined,
          () => _list('rules_ending', context.tr('Réglages de fonctions qui expirent')),
          hint: context.tr('dans les 7 jours')),
    ];
    return {for (final c in list) c.key: c};
  }

  String _hello(BuildContext context) {
    final first = (widget.name ?? '').trim().split(RegExp(r'\s+')).first;
    return first.isEmpty
        ? context.tr('Bonjour')
        : context.tr('Bonjour {name}', {'name': first});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _todo ?? const PlatformTodo({});
    final counts = _counts(context, t);
    final waiting = t.waitingOrder;
    final zeros = t.zeroKeys;

    return Scaffold(
      appBar: AppBar(
        title: Text(_hello(context), key: const Key('today-hello')),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _loading
                ? null
                : () {
                    _figures.currentState?.reload();
                    _load();
                  },
            icon: const Icon(Icons.refresh),
          ),
          bellRoom,
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
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
            _Numbers(
              today: _today,
              overview: _overview,
              counts: _counts132,
              newThisWeek: _overview?.newThisWeek ?? t['new_7'],
              onTap: () => context.go(Routes.platformAnalytics),
            ),
            const SizedBox(height: 18),
            _Label(
              context.tr('Vous attend · {n}', {'n': waiting.length}),
              trailing: waiting.isEmpty ? null : context.tr('par urgence'),
            ),
            if (_todo != null && waiting.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(context.tr('Rien ne vous attend.'),
                    key: const Key('today-nothing'),
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
            if (waiting.isNotEmpty)
              _Lines(children: [
                for (final k in waiting) _Line(count: counts[k]!, n: t.count(k)),
              ]),
            const SizedBox(height: 12),
            if (_todo != null && zeros.isNotEmpty) ...[
              Material(
                key: const Key('todo-all-good'),
                color: const Color(0xFFE6F2E8),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _zerosOpen = !_zerosOpen),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D4F)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            zeros.length > 1
                                ? context.tr('Tout le reste va bien · {n} contrôles à zéro',
                                    {'n': zeros.length})
                                : context.tr('Tout le reste va bien · {n} contrôle à zéro',
                                    {'n': zeros.length}),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF1E5E3A), fontWeight: FontWeight.w700),
                          ),
                        ),
                        Icon(_zerosOpen ? Icons.expand_less : Icons.expand_more,
                            color: const Color(0xFF2E7D4F)),
                      ],
                    ),
                  ),
                ),
              ),
              if (_zerosOpen) ...[
                const SizedBox(height: 8),
                _Lines(children: [
                  for (final k in zeros) _Line(count: counts[k]!, n: 0),
                ]),
              ],
            ],
            const SizedBox(height: 12),
            // The month's figures (072): folded, there for whoever wants
            // them — and « Écrire aux boutiques ».
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('today-figures'),
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                childrenPadding: EdgeInsets.zero,
                title: Text(context.tr('Les chiffres du mois'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                subtitle: Text(context.tr('Ce mois, croissance, santé, écrire aux boutiques')),
                children: [ConsoleToday(key: _figures, admin: widget.admin)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The spot payments to refund by hand (139): what, whose, how much, why,
/// and « Remboursé » once done in Play Console or by Apple.
class SpotRefundsSheet extends StatefulWidget {
  const SpotRefundsSheet({super.key, required this.center});

  final CommandCenterRepository center;

  @override
  State<SpotRefundsSheet> createState() => _SpotRefundsSheetState();
}

class _SpotRefundsSheetState extends State<SpotRefundsSheet> {
  List<SpotRefundRow>? _rows;
  String? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.center.spotRefunds();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _done(SpotRefundRow r) async {
    if (_busy.contains(r.id)) return;
    setState(() => _busy.add(r.id));
    try {
      await widget.center.spotRefundDone(r.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  String _why(BuildContext context, String? reason) => switch (reason) {
        'no spot' => context.tr('la mise en avant n\'existe plus'),
        'refused' => context.tr('mise en avant refusée'),
        'vitrine' => context.tr('vitrine fermée'),
        'feature' => context.tr('fonction masquée pour l\'activité'),
        'article' => context.tr('article plus prêt (photo, prix, stock)'),
        _ => context.tr('autre produit'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        key: const Key('spot-refunds-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Paiements de mise en avant à rembourser'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(context.tr('Payés dans une boutique, ils n\'ont rien programmé. Remboursez-les dans Play Console (Commandes) ou demandez-le à Apple, puis touchez « Remboursé ».'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          if (rows == null && _error == null) const Center(child: CircularProgressIndicator()),
          if (rows != null && rows.isEmpty) Text(context.tr('Rien à rembourser.')),
          if (rows != null)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in rows)
                    ListTile(
                      key: Key('spot-refund-${r.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r.orgName ?? '—'} · ${r.channel == 'apple' ? 'App Store' : r.channel == 'google' ? 'Google Play' : context.tr('carte')}'),
                      subtitle: Text([
                        if (r.amount != null) '${r.amount!.toStringAsFixed(r.amount! == r.amount!.roundToDouble() ? 0 : 2)} ${r.currency ?? ''}',
                        _why(context, r.reason),
                        if (r.externalId != null) r.externalId!,
                      ].join(' · '), maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: TextButton(
                        onPressed: _busy.contains(r.id) ? null : () => _done(r),
                        child: Text(context.tr('Remboursé')),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Count {
  const _Count(this.key, this.label, this.icon, this.onTap, {this.hint, this.urgent = false});

  final String key;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? hint;
  final bool urgent;
}

/// The center's small uppercase words over a list.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium
        ?.copyWith(letterSpacing: 0.9, color: maraBrown, fontWeight: FontWeight.w800);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), key: const Key('today-waiting'), style: style)),
          if (trailing != null) Text(trailing!, style: style?.copyWith(letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

/// Lines in one rounded card.
class _Lines extends StatelessWidget {
  const _Lines({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.colorScheme.outlineVariant),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One counter: its number, its words, its hint; a tap opens it. At zero
/// it is drawn (the green line opened) and is no button.
class _Line extends StatelessWidget {
  const _Line({required this.count, required this.n});

  final _Count count;
  final int n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = count;
    final zero = n == 0;
    final tone = zero
        ? theme.colorScheme.surfaceContainerLow
        : c.urgent
            ? theme.colorScheme.errorContainer
            : const Color(0xFFF6EBDD);
    final ink = zero
        ? theme.colorScheme.onSurfaceVariant
        : c.urgent
            ? theme.colorScheme.onErrorContainer
            : maraBrown;
    return Material(
      key: Key('todo-${c.key}'),
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: zero ? null : c.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(10)),
                child: Text('$n',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: zero ? theme.colorScheme.onSurfaceVariant : null)),
                    if (c.hint != null && !zero)
                      Text(c.hint!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (!zero) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four numbers at the top (135): the new accounts of the week against
/// the week before and today's orders against the same day last week (132,
/// the owner's two), the businesses, the ones on Pro. A server without 132
/// counts neither: the new businesses of the week and the seven days'
/// orders stand in, each saying what it counts — never drawn as if they
/// were the others. A tap: the analyses.
class _Numbers extends StatelessWidget {
  const _Numbers({
    required this.today,
    required this.overview,
    required this.newThisWeek,
    required this.onTap,
    this.counts,
  });

  final PlatformToday? today;
  final PlatformOverview? overview;
  final TodayCounts? counts;
  final int newThisWeek;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = NumberFormat.decimalPattern('fr_FR');
    final t = today;
    final o = overview;
    String? change(int now, int before) {
      if (before <= 0) return now > 0 ? '+${f.format(now)}' : null;
      // Against the seven days before: « +12 % », as the mockup says it.
      final pct = ((now - before) * 100 / before).round();
      return pct == 0 ? context.tr('stable') : '${pct > 0 ? '+' : ''}$pct %';
    }

    final week = t?.count(t.growth, 'orders_week');
    final last = t?.count(t.growth, 'orders_last_week');
    final businesses = t?.count(t.growth, 'businesses') ?? o?.active;
    final monthNew = t?.count(t.growth, 'new_month');
    final c = counts;
    // « mardi dernier » / « last Tuesday »: the day the orders are set against.
    final weekday = DateFormat.EEEE(context.trLocale).format(DateTime.now());
    String? against(String? delta, String words) =>
        delta == null ? null : context.tr(words, {'change': delta, 'day': weekday});
    final tiles = [
      if (c != null) ...[
        _Number('today-accounts', context.tr('Nouveaux comptes · 7 j'), f.format(c.accountsWeek),
            against(change(c.accountsWeek, c.accountsLastWeek), '{change} vs semaine passée')),
        _Number('today-orders', context.tr('Commandes aujourd\'hui'), f.format(c.ordersToday),
            against(change(c.ordersToday, c.ordersLastWeek), '{change} vs {day} dernier')),
      ] else ...[
        _Number('today-new', context.tr('Nouvelles activités'), f.format(newThisWeek),
            context.tr('cette semaine')),
        _Number('today-orders', context.tr('Commandes · 7 j'), week == null ? '—' : f.format(week),
            week == null || last == null ? null : change(week, last)),
      ],
      _Number('today-businesses', context.tr('Activités'),
          businesses == null ? '—' : f.format(businesses),
          monthNew == null || monthNew == 0
              ? null
              : context.tr('+{n} ce mois', {'n': monthNew})),
      _Number('today-pro', context.tr('Abonnés Pro'), o == null ? '—' : f.format(o.pro), null),
    ];
    return LayoutBuilder(builder: (context, box) {
      final per = box.maxWidth >= 720 ? 4 : 2;
      final w = (box.maxWidth - (per - 1) * 10) / per;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final n in tiles) SizedBox(width: w, child: _NumberTile(n: n, onTap: onTap)),
        ],
      );
    });
  }
}

class _Number {
  const _Number(this.key, this.label, this.value, this.note);

  final String key;
  final String label;
  final String value;
  final String? note;
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({required this.n, required this.onTap});

  final _Number n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: Key(n.key),
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Two lines at large text on a small phone, never cut (135 review).
              Text(n.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(n.value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              if (n.note != null)
                Text(n.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF2E7D4F), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
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
      'pro_all' => context.tr('Marakaj Pro complet'),
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
      'plans_ending' => context.tr('Marakaj Pro jusqu\'au {date}', {'date': day}),
      'unlocks_ending' => context.tr('{tool} jusqu\'au {date}{gift}', {
          'tool': featureName(context, r.feature ?? ''),
          'date': day,
          'gift': r.gift ? context.tr(' · offert par Marakaj') : '',
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
      'new_7' => [
          r.byPerson
              ? context.tr('Créée le {date} par la personne', {'date': day})
              : context.tr('Créée le {date} par Marakaj', {'date': day}),
          ?r.owner,
          ?r.city,
        ].join(' · '),
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

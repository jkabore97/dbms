import 'dart:async';

import '../../core/theme/kaj_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/console/command_center.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';
import '../../core/errors.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/mara_mark.dart';
import '../auth/org_picker_screen.dart' show kindPlural, kindSingular;
import 'admin_pill.dart';
import 'businesses_screen.dart' show DeleteBusinessDialog, EditBusinessSheet;
import 'center/bulk_sheet.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The console for somebody running a platform with thousands of businesses
/// on it.
///
/// What it replaced was a single `ListView` of cards fed by `all_orgs()` —
/// every business on the platform, in alphabetical order, with two correlated
/// subqueries run per row. That is a fine screen for the three businesses it
/// was written against and an unusable one at a thousand: slow to load,
/// impossible to search, and — worse — it answered a question nobody has.
/// Nobody running a platform wants page one of an alphabetical list. They want
/// to know what is *wrong* today.
///
/// So this screen is built around three ideas.
///
/// **Health before inventory.** The top of the screen is the shape of the
/// platform: how many are live, how many have gone quiet, how many were
/// onboarded and never used. Those tiles are also the filters — tapping
/// "silent 30 days" is how you get the list of businesses to telephone, which
/// is the actual job.
///
/// **Rows, not cards.** Somebody comparing forty businesses reads a table.
/// Fixed columns, tabular figures, one line each, and status carried by a
/// coloured pill so the eye finds the exceptions without reading every name.
///
/// **The server does the work.** Search, filter, sort and paging are all
/// server-side; the client holds one page. See `search_orgs()` in 021.
///
/// The command center's « Entreprises » (104): today's figures moved to
/// « À faire » and the row of tools to the center's rail. Several rows can
/// be ticked and given one act at once — cauris, a tool until a date, a
/// message, an archive (105's platform_bulk) — each business its own line
/// in the Journal.
class PlatformConsoleScreen extends StatefulWidget {
  const PlatformConsoleScreen({
    super.key,
    required this.console,
    required this.admin,
    this.center,
    this.cauris,
    this.onOpen,
    this.initialActivity,
  });

  final ConsoleRepository console;
  final AdminRepository admin;

  /// The several-at-once acts (105); none offered without it.
  final CommandCenterRepository? center;

  /// The tools that can be opened, for « Ouvrir un outil ».
  final CaurisRepository? cauris;

  /// Opening a business's fiche, when the caller supports it.
  final void Function(OrgRow org)? onOpen;

  /// A filter to open on: 'silent30' from « À faire », say.
  final String? initialActivity;

  @override
  State<PlatformConsoleScreen> createState() => _PlatformConsoleScreenState();
}

class _PlatformConsoleScreenState extends State<PlatformConsoleScreen> {
  static const _pageSize = 50;

  final _searchController = TextEditingController();
  Timer? _debounce;

  PlatformOverview _overview = const PlatformOverview();
  List<OrgRow> _rows = const [];
  int _total = 0;
  int _page = 0;

  String? _profile;
  String _status = 'active';
  late String? _activity = widget.initialActivity;
  String _sort = 'activity';

  /// The ticked businesses, kept across pages and filters.
  final Map<String, OrgRow> _selected = {};

  bool _loading = true;
  String? _error;

  /// True when the console is running against `all_orgs()` because the
  /// database has not been migrated to 021 yet. Filtering and paging then
  /// happen on the client, which is what 021 exists to stop — so the screen
  /// says so rather than pretending.
  bool _legacy = false;

  final _number = NumberFormat.decimalPattern('fr_FR');
  final _date = DateFormat('d MMM y', 'fr_FR');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Typing is debounced: a search that fires on every keystroke is a search
  /// that runs eight queries to answer one question.
  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 0;
      _load();
    });
  }

  Future<void> _load() async {
    if (!widget.console.isConfigured) {
      setState(() {
        _loading = false;
        _error = context.tr('Cette version de l\'application a été compilée sans serveur.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await widget.console.overview();
      final page = await widget.console.searchOrgs(
        query: _searchController.text,
        profile: _profile,
        status: _status,
        activity: _activity,
        sort: _sort,
        limit: _pageSize,
        offset: _page * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _rows = page.rows;
        _total = page.total;
        _legacy = false;
        _loading = false;
      });
    } catch (error) {
      // The database has not run 021 yet — the app arrived before its
      // migration. `all_orgs()` from 014 is still there, so the console keeps
      // working on the old data path instead of showing an error, and says so.
      if (isSchemaOutOfDate(error)) {
        await _loadLegacy();
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  /// The pre-021 path. Loads every business, as the old screen did, and does
  /// the filtering here. Correct but not scalable, which is the point of the
  /// banner it turns on.
  Future<void> _loadLegacy() async {
    try {
      final all = await widget.admin.allOrgs();
      final q = _searchController.text.trim().toLowerCase();
      final rows = all
          .where((o) => _status == 'all'
              ? true
              : _status == 'archived'
                  ? o.isArchived
                  : !o.isArchived)
          .where((o) =>
              _profile == null ||
              o.profile == _profile ||
              (_profile == 'association' && o.profile == 'church'))
          .where((o) =>
              q.isEmpty ||
              o.name.toLowerCase().contains(q) ||
              o.slug.toLowerCase().contains(q))
          .map((o) => OrgRow(
                id: o.id,
                name: o.name,
                slug: o.slug,
                profile: o.profile,
                currency: o.currency,
                memberCount: o.memberCount,
                archivedAt: o.archivedAt,
                createdAt: o.createdAt,
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _legacy = true;
        _overview = PlatformOverview(
          total: all.length,
          active: all.where((o) => !o.isArchived).length,
          archived: all.where((o) => o.isArchived).length,
          farms: all.where((o) => o.profile == 'farm').length,
          shops: all.where((o) => o.profile == 'retail').length,
          churches: all.where((o) => o.profile == 'church' || o.profile == 'association').length,
          otherProfiles: all
              .where((o) => !['farm', 'retail', 'church', 'association'].contains(o.profile))
              .length,
        );
        // Paged here rather than server-side, which is exactly what 021 is for.
        _rows = rows.skip(_page * _pageSize).take(_pageSize).toList();
        _total = rows.length;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  void _applyFilter({
    String? profile,
    String? status,
    String? activity,
    bool clear = false,
  }) {
    setState(() {
      if (clear) {
        _profile = null;
        _activity = null;
        _status = 'active';
        _searchController.clear();
      } else {
        if (profile != null) _profile = _profile == profile ? null : profile;
        if (status != null) _status = status;
        if (activity != null) {
          _activity = _activity == activity ? null : activity;
        }
      }
      _page = 0;
    });
    _load();
  }

  bool get _isFiltered =>
      _profile != null ||
      _activity != null ||
      _status != 'active' ||
      _searchController.text.trim().isNotEmpty;

  int get _pageCount => _total == 0 ? 1 : ((_total - 1) ~/ _pageSize) + 1;

  Future<void> _create() async {
    final id = await context.push<String>(Routes.newBusiness);
    if (id != null && mounted) await _load();
  }

  Future<void> _edit(OrgRow org) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          EditBusinessSheet(admin: widget.admin, org: org.toPlatformOrg()),
    );
    if (changed == true && mounted) await _load();
  }

  void _tick(OrgRow org) => setState(() {
        if (_selected.remove(org.id) == null) _selected[org.id] = org;
      });

  Future<void> _bulk(BulkAction action) async {
    final center = widget.center;
    if (center == null || _selected.isEmpty) return;
    var tools = const <String>[];
    if (action == BulkAction.unlock) {
      try {
        tools = [
          for (final t in await (widget.cauris?.costs() ?? Future.value(const [])))
            if (t.feature != 'photo_slot') t.feature,
        ];
      } catch (_) {}
    }
    if (!mounted) return;
    final result = await showBulkSheet(context,
        action: action, orgs: _selected.values.toList(), center: center, tools: tools);
    if (result != null && mounted) {
      setState(_selected.clear);
      await _load();
    }
  }

  Future<void> _rowAction(OrgRow org, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case 'edit':
          await _edit(org);
          return;
        case 'open':
          AdminTrail.openBusiness(context, org.id);
          return;
        case 'archive':
          await widget.admin.archiveOrg(org.id);
        case 'restore':
          await widget.admin.restoreOrg(org.id);
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => DeleteBusinessDialog(org: org.toPlatformOrg()),
          );
          if (confirmed != true) return;
          await widget.admin.deleteOrg(orgId: org.id, confirmName: org.name);
      }
      if (mounted) await _load();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.of(context).size.width >= 760;

    final ticking = widget.center != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Entreprises')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('Actualiser'),
          ),
        ],
      ),
      floatingActionButton: _selected.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_business_outlined),
              label: Text(context.tr('Nouvelle entreprise')),
            ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : _BulkBar(
              count: _selected.length,
              onAct: _bulk,
              onClear: () => setState(_selected.clear),
            ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _StatStrip(
                  overview: _overview,
                  number: _number,
                  activity: _activity,
                  status: _status,
                  onSelect: (activity, status) => _applyFilter(
                    activity: activity,
                    status: status,
                  ),
                ),
                const SizedBox(height: 16),
                _controls(theme),
                const SizedBox(height: 8),
                if (_legacy)
                  KajCard(
                    color: theme.colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(context.tr('Base de données à mettre à jour')),
                      subtitle: Text(
                        context.tr('La console fonctionne en mode réduit : recherche et filtres sont appliqués sur cet appareil. Appliquez la migration 021 pour la recherche côté serveur.'),
                      ),
                    ),
                  ),
                if (_error != null)
                  KajCard(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_error!),
                      trailing: TextButton(
                        onPressed: _load,
                        child: Text(context.tr('Réessayer')),
                      ),
                    ),
                  )
                else if (_rows.isEmpty && !_loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 56),
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            _isFiltered
                                ? context.tr('Aucune entreprise ne correspond.')
                                : context.tr('Aucune entreprise pour le moment.'),
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (_isFiltered) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => _applyFilter(clear: true),
                              child: Text(context.tr('Effacer les filtres')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else ...[
                  _resultLine(theme),
                  const SizedBox(height: 6),
                  if (wide) _TableHeader(theme: theme, ticking: ticking),
                  for (final org in _rows)
                    _OrgRowTile(
                      org: org,
                      wide: wide,
                      date: _date,
                      onOpen: widget.onOpen == null
                          ? null
                          : () => widget.onOpen!(org),
                      onAction: (a) => _rowAction(org, a),
                      selected: ticking ? _selected.containsKey(org.id) : null,
                      onTick: ticking ? () => _tick(org) : null,
                    ),
                  if (_pageCount > 1) _pager(theme),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onQueryChanged,
          decoration: InputDecoration(
            hintText: context.tr('Rechercher par nom ou identifiant…'),
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr('Effacer'),
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      _page = 0;
                      _load();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // One « Associations »: the server's filter finds the legacy
            // churches with them (105's search_orgs).
            for (final kind in const ['farm', 'retail', 'association'])
              FilterChip(
                key: Key('console-kind-$kind'),
                label: Text(kindPlural(context, kind)),
                selected: _profile == kind,
                onSelected: (_) => _applyFilter(profile: kind),
              ),
            const SizedBox(width: 4),
            // Sorting is a menu rather than more chips: it is one choice among
            // three, and chips would imply it combines with the filters.
            PopupMenuButton<String>(
              initialValue: _sort,
              onSelected: (v) {
                setState(() {
                  _sort = v;
                  _page = 0;
                });
                _load();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'activity', child: Text(context.tr('Activité récente'))),
                PopupMenuItem(value: 'name', child: Text(context.tr('Nom'))),
                PopupMenuItem(value: 'newest', child: Text(context.tr('Plus récentes'))),
              ],
              child: Chip(
                avatar: const Icon(Icons.sort, size: 18),
                label: Text(switch (_sort) {
                  'name' => 'Nom',
                  'newest' => 'Plus récentes',
                  _ => 'Activité',
                }),
              ),
            ),
            if (_isFiltered)
              TextButton.icon(
                onPressed: () => _applyFilter(clear: true),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: Text(context.tr('Tout effacer')),
              ),
          ],
        ),
      ],
    );
  }

  Widget _resultLine(ThemeData theme) {
    final from = _page * _pageSize + 1;
    final to = (_page * _pageSize + _rows.length);
    return Text(
      _total <= _pageSize
          ? '${_number.format(_total)} entreprise${_total > 1 ? 's' : ''}'
          : '${_number.format(from)}–${_number.format(to)} sur '
              '${_number.format(_total)}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _pager(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _page == 0
                ? null
                : () {
                    setState(() => _page -= 1);
                    _load();
                  },
            icon: const Icon(Icons.chevron_left),
            tooltip: context.tr('Page précédente'),
          ),
          Text('${_page + 1} / $_pageCount', style: theme.textTheme.bodyMedium),
          IconButton(
            onPressed: _page + 1 >= _pageCount
                ? null
                : () {
                    setState(() => _page += 1);
                    _load();
                  },
            icon: const Icon(Icons.chevron_right),
            tooltip: context.tr('Page suivante'),
          ),
        ],
      ),
    );
  }
}

/// The shape of the platform, and the fastest way to filter it.
///
/// Each tile is a question the person running the platform actually asks, and
/// tapping one answers it with a list. "Silent for 30 days" is the important
/// one: it is the churn signal, and it arrives weeks before the customer goes.
class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.overview,
    required this.number,
    required this.activity,
    required this.status,
    required this.onSelect,
  });

  final PlatformOverview overview;
  final NumberFormat number;
  final String? activity;
  final String status;
  final void Function(String? activity, String? status) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = KajTheme.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatTile(
          label: context.tr('Entreprises'),
          value: number.format(overview.active),
          hint: overview.newThisWeek > 0
              ? context.tr('+{newThisWeek} cette semaine', {'newThisWeek': overview.newThisWeek})
              : null,
          colour: palette.tint(0),
          selected: activity == null && status == 'active',
          onTap: () => onSelect(null, 'active'),
        ),
        _StatTile(
          label: context.tr('Actives (7 j)'),
          value: number.format(overview.active7d),
          colour: palette.tint(2),
          selected: activity == 'active7',
          onTap: () => onSelect('active7', 'active'),
        ),
        _StatTile(
          label: context.tr('Silencieuses (30 j)'),
          value: number.format(overview.silent30d),
          hint: overview.silent30d > 0 ? context.tr('à rappeler') : null,
          colour: const Color(0xFFB1541A),
          selected: activity == 'silent30',
          onTap: () => onSelect('silent30', 'active'),
        ),
        _StatTile(
          label: context.tr('Jamais utilisées'),
          value: number.format(overview.neverActive),
          colour: const Color(0xFFB03B3B),
          selected: activity == 'never',
          onTap: () => onSelect('never', 'active'),
        ),
        // The first revenue number (065). Tapping it lists the businesses
        // behind it, the way every other tile does.
        _StatTile(
          label: context.tr('Mara Pro'),
          value: number.format(overview.pro),
          hint: overview.pro == 0 ? context.tr('aucune encore') : 'payantes',
          colour: const Color(0xFF2E7D5B),
          selected: activity == 'pro',
          onTap: () => onSelect('pro', 'active'),
        ),
        _StatTile(
          label: context.tr('Archivées'),
          value: number.format(overview.archived),
          colour: Theme.of(context).colorScheme.outline,
          selected: status == 'archived',
          onTap: () =>
              onSelect(null, status == 'archived' ? 'active' : 'archived'),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.colour,
    required this.selected,
    required this.onTap,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 168,
      child: Material(
        color: colour.withValues(alpha: selected ? 0.18 : 0.07),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? colour : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colour,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(label, style: theme.textTheme.bodySmall),
                if (hint != null)
                  Text(
                    hint!,
                    style: theme.textTheme.labelSmall?.copyWith(color: colour),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.theme, this.ticking = false});
  final ThemeData theme;

  /// A first column for the ticks.
  final bool ticking;

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.6,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          if (ticking) const SizedBox(width: 44),
          Expanded(flex: 5, child: Text(context.tr('ENTREPRISE'), style: style)),
          Expanded(flex: 2, child: Text(context.tr('TYPE'), style: style)),
          Expanded(
              flex: 2,
              child: Text(context.tr('MEMBRES'), style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 3,
              child: Text(context.tr('DERNIÈRE ACTIVITÉ'),
                  style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// One business, one line.
class _OrgRowTile extends StatelessWidget {
  const _OrgRowTile({
    required this.org,
    required this.wide,
    required this.date,
    required this.onAction,
    this.onOpen,
    this.selected,
    this.onTick,
  });

  final OrgRow org;
  final bool wide;
  final DateFormat date;
  final void Function(String action) onAction;
  final VoidCallback? onOpen;

  /// Ticked for an act on several at once; null draws no box.
  final bool? selected;
  final VoidCallback? onTick;

  ({String label, Color colour}) _health(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (org.health) {
      OrgHealth.healthy => (label: context.tr('Active'), colour: const Color(0xFF0E7A63)),
      OrgHealth.slowing => (label: context.tr('Ralentit'), colour: const Color(0xFFA96A0B)),
      OrgHealth.silent => (
          label: context.tr('Silencieuse'),
          colour: const Color(0xFFB1541A)
        ),
      OrgHealth.neverStarted => (
          label: context.tr('Jamais utilisée'),
          colour: const Color(0xFFB03B3B)
        ),
      OrgHealth.archived => (label: context.tr('Archivée'), colour: scheme.outline),
    };
  }

  String _lastActivity() {
    if (org.lastActivityAt == null) return '—';
    final days = org.daysSinceActivity!;
    if (days == 0) return 'aujourd\'hui';
    if (days == 1) return 'hier';
    if (days < 30) return 'il y a $days j';
    return date.format(org.lastActivityAt!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = _health(context);

    final menu = PopupMenuButton<String>(
      onSelected: onAction,
      itemBuilder: (_) => [
        if (!org.isArchived)
          PopupMenuItem(value: 'open', child: Text(context.tr('Ouvrir l\'activité'))),
        PopupMenuItem(value: 'edit', child: Text(context.tr('Modifier'))),
        if (org.isArchived)
          PopupMenuItem(value: 'restore', child: Text(context.tr('Restaurer')))
        else
          PopupMenuItem(value: 'archive', child: Text(context.tr('Archiver'))),
        if (org.isArchived)
          PopupMenuItem(value: 'delete', child: Text(context.tr('Supprimer…'))),
      ],
    );

    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          org.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            decoration: org.isArchived ? TextDecoration.lineThrough : null,
          ),
        ),
        Text(
          org.slug,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: health.colour.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        health.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: health.colour,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final tick = selected == null
        ? null
        : SizedBox(
            width: 44,
            child: Checkbox(
              key: Key('tick-${org.id}'),
              value: selected,
              onChanged: (_) => onTick?.call(),
            ),
          );

    return KajCard(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 0,
      color: selected == true
          ? maraCaramel.withValues(alpha: 0.16)
          : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        onLongPress: onTick,
        child: Padding(
          padding: EdgeInsets.fromLTRB(tick == null ? 12 : 2, 10, 6, 10),
          child: wide
              ? Row(
                  children: [
                    ?tick,
                    Expanded(flex: 5, child: name),
                    Expanded(
                      flex: 2,
                      child: Text(kindSingular(context, org.profile),
                          style: theme.textTheme.bodySmall),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        context.tr('{memberCount}', {'memberCount': org.memberCount}),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(_lastActivity(),
                              style: theme.textTheme.bodySmall),
                          const SizedBox(width: 10),
                          pill,
                        ],
                      ),
                    ),
                    menu,
                  ],
                )
              // Narrow: the same information, stacked. A table that scrolls
              // sideways on a phone is a table nobody reads.
              : Row(
                  children: [
                    ?tick,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          name,
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              pill,
                              const SizedBox(width: 8),
                              // Flexible: on a phone, with a tick in front,
                              // the line ran off the card.
                              Flexible(
                                child: Text(
                                  '${kindSingular(context, org.profile)} · '
                                  '${org.memberCount} membre'
                                  '${org.memberCount > 1 ? 's' : ''} · '
                                  '${_lastActivity()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    menu,
                  ],
                ),
        ),
      ),
    );
  }
}

/// The ticked businesses' act, along the foot of the list.
class _BulkBar extends StatelessWidget {
  const _BulkBar({required this.count, required this.onAct, required this.onClear});

  final int count;
  final void Function(BulkAction action) onAct;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Widget act(BulkAction a, IconData icon, String label) => FilledButton.tonalIcon(
          key: Key('bulk-${a.name}'),
          style: FilledButton.styleFrom(
            backgroundColor: maraPaper,
            foregroundColor: maraBlack,
            minimumSize: const Size(48, 44),
          ),
          onPressed: () => onAct(a),
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    // Every act in sight: they wrap, never slide off the edge — on a phone
    // (under 480) under the count, on a computer beside it.
    final acts = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        act(BulkAction.cauris, Icons.redeem_outlined, context.tr('Cauris')),
        act(BulkAction.unlock, Icons.lock_open_outlined, context.tr('Outil')),
        act(BulkAction.message, Icons.campaign_outlined, context.tr('Message')),
        act(BulkAction.archive, Icons.archive_outlined, context.tr('Archiver')),
      ],
    );
    final head = [
      IconButton(
        tooltip: context.tr('Tout décocher'),
        onPressed: onClear,
        icon: const Icon(Icons.close, color: maraPaper),
      ),
      Text(
        context.tr('{n} cochée(s)', {'n': count}),
        style: const TextStyle(color: maraCaramel, fontWeight: FontWeight.w800),
      ),
    ];
    final narrow = MediaQuery.sizeOf(context).width < 480;
    return Material(
      key: const Key('bulk-bar'),
      color: maraDeep,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: narrow
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: head),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                      child: acts,
                    ),
                  ],
                )
              : Row(
                  children: [
                    ...head,
                    const SizedBox(width: 12),
                    Expanded(child: acts),
                  ],
                ),
        ),
      ),
    );
  }
}

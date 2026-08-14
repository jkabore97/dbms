import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';
import '../../core/errors.dart';
import '../../core/theme/kaj_theme.dart';
import 'businesses_screen.dart' show DeleteBusinessDialog, EditBusinessSheet;
import 'create_business_screen.dart';

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
class PlatformConsoleScreen extends StatefulWidget {
  const PlatformConsoleScreen({
    super.key,
    required this.console,
    required this.admin,
    this.onOpen,
  });

  final ConsoleRepository console;
  final AdminRepository admin;

  /// Opening a business as the platform admin, when the caller supports it.
  final void Function(OrgRow org)? onOpen;

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
  String? _activity;
  String _sort = 'activity';

  bool _loading = true;
  String? _error;

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
        _error = "Cette version de l'application a été compilée sans serveur.";
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
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CreateBusinessScreen(admin: widget.admin)),
    );
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

  Future<void> _rowAction(OrgRow org, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case 'edit':
          await _edit(org);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Console'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nouvelle entreprise'),
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

                if (_error != null)
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_error!),
                      trailing: TextButton(
                        onPressed: _load,
                        child: const Text('Réessayer'),
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
                                ? 'Aucune entreprise ne correspond.'
                                : 'Aucune entreprise pour le moment.',
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (_isFiltered) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => _applyFilter(clear: true),
                              child: const Text('Effacer les filtres'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else ...[
                  _resultLine(theme),
                  const SizedBox(height: 6),
                  if (wide) _TableHeader(theme: theme),
                  for (final org in _rows)
                    _OrgRowTile(
                      org: org,
                      wide: wide,
                      date: _date,
                      onOpen: widget.onOpen == null
                          ? null
                          : () => widget.onOpen!(org),
                      onAction: (a) => _rowAction(org, a),
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
            hintText: 'Rechercher par nom ou identifiant…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
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
            for (final entry in const {
              'farm': 'Fermes',
              'retail': 'Boutiques',
              'church': 'Associations',
            }.entries)
              FilterChip(
                label: Text(entry.value),
                selected: _profile == entry.key,
                onSelected: (_) => _applyFilter(profile: entry.key),
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
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'activity', child: Text('Activité récente')),
                PopupMenuItem(value: 'name', child: Text('Nom')),
                PopupMenuItem(value: 'newest', child: Text('Plus récentes')),
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
                label: const Text('Tout effacer'),
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
            tooltip: 'Page précédente',
          ),
          Text('${_page + 1} / $_pageCount',
              style: theme.textTheme.bodyMedium),
          IconButton(
            onPressed: _page + 1 >= _pageCount
                ? null
                : () {
                    setState(() => _page += 1);
                    _load();
                  },
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Page suivante',
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
          label: 'Entreprises',
          value: number.format(overview.active),
          hint: overview.newThisWeek > 0
              ? '+${overview.newThisWeek} cette semaine'
              : null,
          colour: palette.tint(0),
          selected: activity == null && status == 'active',
          onTap: () => onSelect(null, 'active'),
        ),
        _StatTile(
          label: 'Actives (7 j)',
          value: number.format(overview.active7d),
          colour: palette.tint(2),
          selected: activity == 'active7',
          onTap: () => onSelect('active7', 'active'),
        ),
        _StatTile(
          label: 'Silencieuses (30 j)',
          value: number.format(overview.silent30d),
          hint: overview.silent30d > 0 ? 'à rappeler' : null,
          colour: const Color(0xFFB1541A),
          selected: activity == 'silent30',
          onTap: () => onSelect('silent30', 'active'),
        ),
        _StatTile(
          label: 'Jamais utilisées',
          value: number.format(overview.neverActive),
          colour: const Color(0xFFB03B3B),
          selected: activity == 'never',
          onTap: () => onSelect('never', 'active'),
        ),
        _StatTile(
          label: 'Archivées',
          value: number.format(overview.archived),
          colour: Theme.of(context).colorScheme.outline,
          selected: status == 'archived',
          onTap: () => onSelect(null, status == 'archived' ? 'active' : 'archived'),
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
  const _TableHeader({required this.theme});
  final ThemeData theme;

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
          Expanded(flex: 5, child: Text('ENTREPRISE', style: style)),
          Expanded(flex: 2, child: Text('TYPE', style: style)),
          Expanded(
              flex: 2,
              child: Text('MEMBRES', style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 3,
              child:
                  Text('DERNIÈRE ACTIVITÉ', style: style, textAlign: TextAlign.right)),
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
  });

  final OrgRow org;
  final bool wide;
  final DateFormat date;
  final void Function(String action) onAction;
  final VoidCallback? onOpen;

  static const _profiles = {
    'farm': 'Ferme',
    'retail': 'Boutique',
    'church': 'Association',
  };

  ({String label, Color colour}) _health(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (org.health) {
      OrgHealth.healthy => (label: 'Active', colour: const Color(0xFF0E7A63)),
      OrgHealth.slowing => (label: 'Ralentit', colour: const Color(0xFFA96A0B)),
      OrgHealth.silent => (label: 'Silencieuse', colour: const Color(0xFFB1541A)),
      OrgHealth.neverStarted =>
        (label: 'Jamais utilisée', colour: const Color(0xFFB03B3B)),
      OrgHealth.archived => (label: 'Archivée', colour: scheme.outline),
    };
  }

  String _lastActivity() {
    if (org.lastActivityAt == null) return '—';
    final days = org.daysSinceActivity!;
    if (days == 0) return "aujourd'hui";
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
        const PopupMenuItem(value: 'edit', child: Text('Modifier')),
        if (org.isArchived)
          const PopupMenuItem(value: 'restore', child: Text('Restaurer'))
        else
          const PopupMenuItem(value: 'archive', child: Text('Archiver')),
        if (org.isArchived)
          const PopupMenuItem(value: 'delete', child: Text('Supprimer…')),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: wide
              ? Row(
                  children: [
                    Expanded(flex: 5, child: name),
                    Expanded(
                      flex: 2,
                      child: Text(_profiles[org.profile] ?? org.profile,
                          style: theme.textTheme.bodySmall),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${org.memberCount}',
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
                              Text(
                                '${_profiles[org.profile] ?? org.profile} · '
                                '${org.memberCount} membre'
                                '${org.memberCount > 1 ? 's' : ''} · '
                                '${_lastActivity()}',
                                style: theme.textTheme.bodySmall,
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

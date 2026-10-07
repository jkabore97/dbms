import 'package:flutter/material.dart';

import '../../core/console/command_center.dart';
import '../../core/console/fiche_repository.dart' show FeatureBoardRow;
import '../../core/console/kind_models_repository.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/storefront/storefront_repository.dart' show StorefrontStyle;
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_mark.dart';
import 'vitrine_plus_card.dart';

/// « Types d'activité » in the command center (107): one tab per kind —
/// shops, farms, associations (a legacy church is an association) — and in
/// each what every business of that kind is shown and starts with:
///
///  * Fonctions: 104's switchboard at the kind's level, the impact said
///    before anything is saved (« Ce changement touche 12 boutiques ; 2 ont
///    leur propre réglage ; 1 l'a payée »).
///  * Réglages par type: the free numbers that differ by kind; « Par
///    défaut » is the platform's.
///  * Vitrine par défaut: for the vitrines never dressed.
///  * Mise en route: the optional walkthrough steps, on or off.
///
/// Every change is the server's to allow (platform admins only), and each
/// one comes back with « Annuler » — the journal's undo.
class KindModelsScreen extends StatelessWidget {
  const KindModelsScreen({super.key, this.repository, this.undo});

  /// Stands in for the server in a test; the app's own otherwise.
  final KindModelsRepository? repository;

  /// « Annuler »: the journal's undo (104); the command center's otherwise.
  final Future<void> Function(String actionId)? undo;

  static const kinds = ['retail', 'farm', 'association'];

  @override
  Widget build(BuildContext context) {
    final client = AppScope.maybeOf(context)?.auth.client;
    final repo = repository ?? KindModelsRepository(client);
    final undoIt = undo ?? CommandCenterRepository(client).undo;
    return DefaultTabController(
      length: kinds.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Types d\'activité')),
          bottom: TabBar(
            key: const Key('kinds-tabs'),
            tabs: [
              Tab(icon: const Icon(Icons.storefront_outlined), text: context.tr('Boutiques')),
              Tab(icon: const Icon(Icons.agriculture_outlined), text: context.tr('Fermes')),
              Tab(icon: const Icon(Icons.groups_outlined), text: context.tr('Associations')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final k in kinds) _KindTab(kind: k, repository: repo, undo: undoIt),
          ],
        ),
      ),
    );
  }
}

/// « 12 boutiques », in the kind's own word.
String kindCount(BuildContext context, String kind, int n) => switch (kind) {
      'farm' => context.tr('{n} ferme(s)', {'n': n}),
      'association' => context.tr('{n} association(s)', {'n': n}),
      _ => context.tr('{n} boutique(s)', {'n': n}),
    };

/// The impact line, before a kind's switch is saved.
String impactLine(BuildContext context, String kind, FeatureImpact i) => [
      context.tr('Ce changement touche {orgs}', {'orgs': kindCount(context, kind, i.orgs)}),
      if (i.overridden > 0)
        context.tr('{n} ont leur propre réglage', {'n': i.overridden}),
      if (i.paid > 0) context.tr('{n} l\'ont payée et la gardent', {'n': i.paid}),
    ].join(' ; ');

class _KindTab extends StatefulWidget {
  const _KindTab({required this.kind, required this.repository, required this.undo});

  final String kind;
  final KindModelsRepository repository;
  final Future<void> Function(String actionId) undo;

  @override
  State<_KindTab> createState() => _KindTabState();
}

class _KindTabState extends State<_KindTab> with AutomaticKeepAliveClientMixin {
  KindModels? _models;
  List<FeatureBoardRow> _board = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // The vitrine default being chosen, before it is saved.
  String _layout = 'grid';
  String? _accent;
  String _cover = 'none';

  @override
  bool get wantKeepAlive => true;

  String get _kind => widget.kind;

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
      final results = await Future.wait([
        widget.repository.models(_kind),
        widget.repository.board(_kind),
      ]);
      if (!mounted) return;
      final models = results[0] as KindModels;
      setState(() {
        _models = models;
        _board = results[1] as List<FeatureBoardRow>;
        _layout = models.vitrineDefault?.layout ?? 'grid';
        _accent = models.vitrineDefault?.accent;
        _cover = models.vitrineDefault?.cover ?? 'none';
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

  /// Runs a save; « Enregistré » with « Annuler » when the journal has a
  /// line for it, and the tab read again.
  Future<void> _save(Future<String?> Function() act) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('Enregistré. Le journal le garde.');
    final same = context.tr('Rien n\'a changé.');
    final undoLabel = context.tr('Annuler');
    final undone = context.tr('Annulé.');
    setState(() => _busy = true);
    try {
      final id = await act();
      messenger.showSnackBar(SnackBar(
        content: Text(id == null ? same : done),
        action: id == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () async {
                  try {
                    await widget.undo(id);
                    messenger.showSnackBar(SnackBar(content: Text(undone)));
                  } catch (error) {
                    messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
                  }
                  if (mounted) await _load();
                },
              ),
      ));
      await _load();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Fonctions ----

  Future<void> _setFeature(FeatureBoardRow row, String state) async {
    if (state == row.state) return;
    FeatureImpact impact;
    try {
      impact = await widget.repository.impact(_kind, row.key, state);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(error))));
      }
      return;
    }
    if (!mounted) return;
    final label = context.tr(row.label);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switch (state) {
          'hidden' => context.tr('Masquer « {label} » ?', {'label': label}),
          'visible' => context.tr('Rendre « {label} » visible ?', {'label': label}),
          _ => context.tr('Remettre « {label} » par défaut ?', {'label': label}),
        }),
        content: Text(impactLine(context, _kind, impact),
            key: const Key('kinds-impact')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            key: const Key('kinds-impact-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Confirmer')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save(() => widget.repository.setFeature(_kind, row.key, state));
  }

  // ---- Réglages par type ----

  String _settingLabel(KindSettingRow r) => switch (r.key) {
        'free_photo_items' => context.tr('Articles en photo (formule gratuite)'),
        'free_max_staff' => context.tr('Personnes offertes en plus du propriétaire'),
        'free_max_invoices_month' => context.tr('Factures par mois (formule gratuite)'),
        'vitrine_min_items' => context.tr('Articles en vente pour ouvrir la vitrine'),
        'vitrine_min_items_association' => context.tr('Services pour ouvrir la vitrine'),
        _ => context.tr(r.label),
      };

  /// Whom a number touches: the free plan's businesses for a free limit,
  /// every business of the kind for what opens a vitrine.
  String _settingImpact(KindSettingRow r) {
    final m = _models!;
    return r.key.startsWith('vitrine_min')
        ? context.tr('Touche {orgs}.', {'orgs': kindCount(context, _kind, m.orgs)})
        : context.tr('Touche {orgs} en formule gratuite.', {'orgs': kindCount(context, _kind, m.free)});
  }

  Future<void> _editSetting(KindSettingRow r) async {
    final result = await showDialog<({bool clear, int? value})>(
      context: context,
      builder: (_) => _SettingDialog(
          row: r, label: _settingLabel(r), impact: _settingImpact(r)),
    );
    if (result == null) return;
    await _save(() => widget.repository.setSetting(
        _kind, r.key, result.clear ? null : result.value));
  }

  // ---- Vitrine par défaut ----

  VitrineDefault get _chosen =>
      VitrineDefault(layout: _layout, accent: _accent, cover: _cover);

  bool get _vitrineChanged {
    final saved = _models?.vitrineDefault ?? const VitrineDefault();
    return saved.layout != _layout || saved.accent != _accent || saved.cover != _cover;
  }

  Future<void> _saveVitrine({bool clear = false}) => _save(() => widget.repository
      .setSetting(_kind, 'vitrine_default', clear || _chosen.isEmpty ? null : _chosen.toJson()));

  // ---- Mise en route ----

  Future<void> _toggleStep(SetupStepRow step, bool on) {
    final off = {..._models!.stepsOff};
    on ? off.remove(step.key) : off.add(step.key);
    final ordered = [
      for (final s in _models!.setup)
        if (off.contains(s.key)) s.key,
    ];
    return _save(() => widget.repository
        .setSetting(_kind, 'setup_off', ordered.isEmpty ? null : ordered));
  }

  String _stepLabel(SetupStepRow s) => switch (s.key) {
        'identity' => _kind == 'association'
            ? context.tr('Le nom et ce qu\'elle est')
            : context.tr('Le nom'),
        'article' => context.tr('Le premier article'),
        'members' => context.tr('Les premiers membres'),
        'vitrine' => context.tr('La vitrine'),
        'position' => context.tr('La position sur la carte'),
        _ => context.tr(s.label),
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final m = _models;
    if (_loading && m == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (m == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_error ?? '', style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('Réessayer')),
            ),
          ),
        ],
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final functions = _section(
      key: const Key('kinds-functions'),
      icon: Icons.tune,
      title: context.tr('Fonctions'),
      line: context.tr('Ce que voit chaque {kind}. « Par défaut » : comme aujourd\'hui. Une fonction payée reste à qui l\'a payée.',
          {'kind': _singular}),
      children: _functions(theme),
    );
    final side = [
      _section(
        key: const Key('kinds-settings'),
        icon: Icons.pin_outlined,
        title: context.tr('Réglages par type'),
        line: context.tr('Les nombres de la formule gratuite pour ce genre. « Par défaut » : ceux de la plateforme.'),
        children: [for (final r in m.settings) _settingRow(theme, r)],
      ),
      _section(
        key: const Key('kinds-vitrine'),
        icon: Icons.storefront_outlined,
        title: context.tr('Vitrine par défaut'),
        line: context.tr('Pour les {n} vitrines jamais habillées (sur {orgs}), gratuites comme Pro. Une vitrine que son commerçant habille garde la sienne.',
            {'n': m.neverDressed, 'orgs': m.orgs}),
        children: _vitrine(theme),
      ),
      _section(
        key: const Key('kinds-setup'),
        icon: Icons.flag_outlined,
        title: context.tr('Mise en route'),
        line: context.tr('Les étapes facultatives de la première mise en route. Les étapes obligatoires restent.'),
        children: [for (final s in m.setup) _stepRow(theme, s)],
      ),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy || _loading) const LinearProgressIndicator(),
                  _numbers(theme, m),
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: functions),
                        const SizedBox(width: 16),
                        Expanded(child: Column(children: side)),
                      ],
                    )
                  else ...[
                    functions,
                    ...side,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _singular => switch (_kind) {
        'farm' => context.tr('ferme'),
        'association' => context.tr('association'),
        _ => context.tr('boutique'),
      };

  Widget _numbers(ThemeData theme, KindModels m) {
    Widget tile(String n, String label, Key key) => Expanded(
          child: Container(
            key: key,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: maraDeep,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(color: maraCaramel, fontWeight: FontWeight.w800)),
                Text(label,
                    maxLines: 2,
                    style: theme.textTheme.bodySmall?.copyWith(color: maraPaper)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('${m.orgs}', switch (_kind) {
          'farm' => context.tr('fermes'),
          'association' => context.tr('associations'),
          _ => context.tr('boutiques'),
        }, const Key('kinds-count')),
        const SizedBox(width: 8),
        tile('${m.free}', context.tr('en formule gratuite'), const Key('kinds-free')),
        const SizedBox(width: 8),
        tile('${m.neverDressed}', context.tr('vitrines jamais habillées'), const Key('kinds-undressed')),
      ],
    );
  }

  Widget _section({
    required Key key,
    required IconData icon,
    required String title,
    required String line,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return KajCard(
      key: key,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: maraBrown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(line,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _functions(ThemeData theme) {
    if (_board.isEmpty) {
      return [Text(context.tr('Aucune fonction à régler pour ce genre.'))];
    }
    final out = <Widget>[];
    String? group;
    for (final row in _board) {
      if (row.group != group) {
        group = row.group;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(context.tr(row.group).toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: maraBrown, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
        ));
      }
      final hidden = row.effective == 'hidden';
      out.add(Padding(
        key: Key('kinds-feature-${row.key}'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18, color: hidden ? theme.colorScheme.error : maraGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr(row.label),
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (row.proTool != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(context.tr('Pro'),
                        style: theme.textTheme.labelSmall?.copyWith(color: maraBrown)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                key: Key('kinds-switch-${row.key}'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'default', label: Text(context.tr('Par défaut'))),
                  ButtonSegment(value: 'visible', label: Text(context.tr('Visible'))),
                  ButtonSegment(value: 'hidden', label: Text(context.tr('Masquée'))),
                ],
                selected: {row.state},
                onSelectionChanged:
                    _busy ? null : (s) => _setFeature(row, s.first),
              ),
            ),
          ],
        ),
      ));
    }
    return out;
  }

  Widget _settingRow(ThemeData theme, KindSettingRow r) {
    final own = r.value != null;
    return ListTile(
      key: Key('kinds-setting-${r.key}'),
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 10,
      title: Text(_settingLabel(r)),
      subtitle: Text(own
          ? context.tr('Propre à ce genre — par défaut : {global}', {'global': r.global})
          : context.tr('Par défaut')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${r.effective}',
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800, color: own ? maraBrown : null)),
          const SizedBox(width: 4),
          const Icon(Icons.edit_outlined, size: 18),
        ],
      ),
      onTap: _busy ? null : () => _editSetting(r),
    );
  }

  List<Widget> _vitrine(ThemeData theme) {
    final layouts = [
      ('grid', context.tr('Grille'), Icons.grid_view),
      ('large', context.tr('Grandes photos'), Icons.crop_landscape),
      ('list', context.tr('Liste'), Icons.view_list),
      ('menu', context.tr('Menu'), Icons.restaurant_menu),
    ];
    final label = theme.textTheme.labelLarge;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('Présentation'), style: label),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (key, name, icon) in layouts)
                      ChoiceChip(
                        key: Key('kinds-layout-$key'),
                        avatar: Icon(icon, size: 18),
                        label: Text(name),
                        selected: _layout == key,
                        selectedColor: maraCaramel,
                        onSelected: _busy ? null : (_) => setState(() => _layout = key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(context.tr('Couleur'), style: label),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const Key('kinds-accent-none'),
                      label: Text(context.tr('Aucune')),
                      selected: _accent == null,
                      selectedColor: maraCaramel,
                      onSelected: _busy ? null : (_) => setState(() => _accent = null),
                    ),
                    for (final c in VitrinePlusCard.accents)
                      _Swatch(
                        color: c,
                        selected: _accent == StorefrontStyle.hexOf(c),
                        onTap: _busy
                            ? null
                            : () => setState(() => _accent = StorefrontStyle.hexOf(c)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(context.tr('Couverture'), style: label),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      key: const Key('kinds-cover-none'),
                      label: Text(context.tr('Aucune')),
                      selected: _cover == 'none',
                      selectedColor: maraCaramel,
                      onSelected: _busy ? null : (_) => setState(() => _cover = 'none'),
                    ),
                    ChoiceChip(
                      key: const Key('kinds-cover-first_photo'),
                      label: Text(context.tr('La première photo')),
                      selected: _cover == 'first_photo',
                      selectedColor: maraCaramel,
                      onSelected: _busy ? null : (_) => setState(() => _cover = 'first_photo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _VitrinePreview(layout: _layout, accent: _accent, cover: _cover),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          if (_models?.vitrineDefault != null)
            TextButton(
              key: const Key('kinds-vitrine-default'),
              onPressed: _busy ? null : () => _saveVitrine(clear: true),
              child: Text(context.tr('Par défaut')),
            ),
          FilledButton.icon(
            key: const Key('kinds-vitrine-save'),
            onPressed: _busy || !_vitrineChanged ? null : _saveVitrine,
            icon: const Icon(Icons.check),
            label: Text(context.tr('Enregistrer')),
          ),
        ],
      ),
    ];
  }

  Widget _stepRow(ThemeData theme, SetupStepRow s) => SwitchListTile(
        key: Key('kinds-step-${s.key}'),
        contentPadding: EdgeInsets.zero,
        title: Text(_stepLabel(s)),
        subtitle: Text(s.required
            ? context.tr('Obligatoire')
            : s.key == 'vitrine' && !s.on
                ? context.tr('Retirée : la vitrine s\'ouvre plus tard, dans les réglages.')
                : s.on
                    ? context.tr('Facultative — proposée')
                    : context.tr('Facultative — retirée')),
        secondary: Icon(s.required ? Icons.lock_outline : Icons.flag_outlined,
            color: s.required ? maraGrey : maraBrown),
        value: s.required || s.on,
        onChanged: s.required || _busy ? null : (v) => _toggleStep(s, v),
      );
}

/// One number for the kind: typed within its bounds, or « Par défaut ».
/// Pops (clear, value); the field is the dialog's own.
class _SettingDialog extends StatefulWidget {
  const _SettingDialog({required this.row, required this.label, required this.impact});

  final KindSettingRow row;
  final String label;
  final String impact;

  @override
  State<_SettingDialog> createState() => _SettingDialogState();
}

class _SettingDialogState extends State<_SettingDialog> {
  late final _field = TextEditingController(text: '${widget.row.effective}');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final n = int.tryParse(_field.text.trim());
    final valid = n != null && n >= r.min && n <= r.max;
    return AlertDialog(
      title: Text(widget.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('kinds-setting-field'),
            controller: _field,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: context.tr('Entre {min} et {max}. Par défaut : {global}.',
                  {'min': r.min, 'max': r.max, 'global': r.global}),
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.impact, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        if (r.value != null)
          TextButton(
            key: const Key('kinds-setting-default'),
            onPressed: () => Navigator.of(context).pop((clear: true, value: null)),
            child: Text(context.tr('Par défaut')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          key: const Key('kinds-setting-save'),
          onPressed: valid ? () => Navigator.of(context).pop((clear: false, value: n)) : null,
          child: Text(context.tr('Enregistrer')),
        ),
      ],
    );
  }
}

/// One of the six colours.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: StorefrontStyle.hexOf(color),
        child: InkWell(
          key: Key('kinds-accent-${StorefrontStyle.hexOf(color)}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? maraDeep : Colors.transparent, width: 3),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
          ),
        ),
      );
}

/// The vitrine default, drawn small: the cover band, the button's colour,
/// the shelf's shape.
class _VitrinePreview extends StatelessWidget {
  const _VitrinePreview({required this.layout, required this.accent, required this.cover});

  final String layout;
  final String? accent;
  final String cover;

  @override
  Widget build(BuildContext context) {
    final button = StorefrontStyle.colorFromHex(accent) ?? maraDeep;
    Widget block({double? w, double h = 14}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: maraGrey.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(4),
          ),
        );
    final shelf = switch (layout) {
      'list' || 'menu' => Column(
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  if (layout == 'list') ...[block(w: 16, h: 16), const SizedBox(width: 5)],
                  Expanded(child: block(h: 8)),
                ]),
              ),
          ],
        ),
      'large' => Column(children: [block(h: 40), const SizedBox(height: 5), block(h: 40)]),
      _ => GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (var i = 0; i < 4; i++) block()],
        ),
    };
    return Container(
      key: const Key('kinds-vitrine-preview'),
      width: 108,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: maraPaper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: maraDeep.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 34,
            decoration: BoxDecoration(
              color: cover == 'first_photo' ? maraBrown.withValues(alpha: 0.55) : maraGrey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: cover == 'first_photo'
                ? const Icon(Icons.photo_outlined, color: maraPaper, size: 18)
                : null,
          ),
          const SizedBox(height: 6),
          block(w: 60, h: 8),
          const SizedBox(height: 6),
          Container(
            height: 14,
            decoration: BoxDecoration(color: button, borderRadius: BorderRadius.circular(7)),
          ),
          const SizedBox(height: 8),
          shelf,
        ],
      ),
    );
  }
}

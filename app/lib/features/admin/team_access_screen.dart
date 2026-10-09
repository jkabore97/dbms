import 'package:flutter/material.dart';

import '../../core/theme/kaj_card.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// The owner's dial: per tool, per tier, who sees and who edits.
///
/// One card per tool, two rows inside — Employés and Superviseurs — each a
/// three-way choice: Caché, Voir, Modifier. Reports offers two, because its
/// screens were always read-only. Everything starts at today's behaviour
/// (all Modifier, reports Voir), so opening the screen and saving without
/// touching anything changes nothing.
///
/// The server is the contract: prices, credit and production refuse at the
/// database whatever the buttons say. This screen writes the rules; the
/// tools redraw themselves the next time the business opens.
class TeamAccessScreen extends StatefulWidget {
  const TeamAccessScreen(
      {super.key, required this.admin, required this.orgId, this.canSave = true});

  final AdminRepository admin;
  final String orgId;

  /// The dial is the owner's (and the platform's) since 103: anybody else
  /// reads it and cannot save it — the server refuses the same.
  final bool canSave;

  @override
  State<TeamAccessScreen> createState() => _TeamAccessScreenState();
}

/// One tool of the dial (also read by « Ajouter une personne », 115, to say
/// what each responsibility sees).
class TeamDialFeature {
  const TeamDialFeature(this.key, this.icon, this.title, this.subtitle,
      {this.editable = true});
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;

  /// False for tools that never had an edit mode to give.
  final bool editable;
}

const teamDialFeatures = [
  TeamDialFeature('products', Icons.inventory_2_outlined, 'Articles',
      'Les prix, les noms, les entrées de stock'),
  TeamDialFeature('production', Icons.precision_manufacturing_outlined, 'Production',
      'Transformer des ingrédients en produits'),
  TeamDialFeature('credits', Icons.handshake_outlined, 'Carnet de crédit',
      'Vendre à crédit et encaisser les remboursements'),
  TeamDialFeature('tontines', Icons.group_outlined, 'Tontines',
      'Les tours, les cotisations, la caisse'),
  TeamDialFeature('invoices', Icons.receipt_long_outlined, 'Factures',
      'Créer et partager des factures'),
  TeamDialFeature('photos', Icons.photo_library_outlined, 'Photos',
      'Photographier et classer les documents'),
  TeamDialFeature('reports', Icons.menu_book_outlined, 'Comptabilité et rapports',
      'Journal, résultat, bilan', editable: false),
  TeamDialFeature('staff', Icons.groups_outlined, 'Personnel',
      'Les fiches, les pointages'),
];

class _TeamAccessScreenState extends State<TeamAccessScreen> {
  // {tier: {feature: access}} — always fully populated once loaded, so the
  // save writes exactly what the screen shows.
  final Map<String, Map<String, String>> _rules = {
    'employee': {},
    'supervisor': {},
  };
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The dial's tools, less those Mara's switchboard hid here (104): a
  /// hidden tool has no dial, and its rule is kept as it was and saved
  /// back unchanged.
  List<TeamDialFeature> get _shownFeatures {
    final access = AppScope.maybeOf(context)?.session.accessFor(widget.orgId);
    return [
      for (final f in teamDialFeatures)
        if (!(access?.isHidden(f.key) ?? false)) f,
    ];
  }

  String _defaultFor(String feature) =>
      feature == 'reports' ? 'view' : 'edit';

  Future<void> _load() async {
    try {
      final stored = await widget.admin.featureRules(widget.orgId);
      if (!mounted) return;
      setState(() {
        for (final tier in ['employee', 'supervisor']) {
          for (final f in teamDialFeatures) {
            _rules[tier]![f.key] =
                stored[tier]?[f.key] ?? _defaultFor(f.key);
          }
        }
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

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.saveFeatureRules(widget.orgId, _rules);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('Enregistré. Les écrans de l’équipe suivront à leur prochaine ouverture.'))));
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  Widget _tierRow(String tier, String label, TeamDialFeature feature) {
    final value = _rules[tier]![feature.key]!;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(context.tr(label),
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              segments: [
                ButtonSegment(value: 'hidden', label: Text(context.tr('Caché'))),
                ButtonSegment(value: 'view', label: Text(context.tr('Voir'))),
                if (feature.editable)
                  ButtonSegment(value: 'edit', label: Text(context.tr('Modifier'))),
              ],
              selected: {value},
              onSelectionChanged: _busy || !widget.canSave
                  ? null
                  : (s) =>
                      setState(() => _rules[tier]![feature.key] = s.first),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Accès de l\'équipe'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  context.tr('Ce que chaque niveau voit et peut modifier. Les propriétaires et administrateurs gardent toujours tout. Les prix, le crédit et la production sont aussi refusés par le serveur — pas seulement cachés.'),
                  style: theme.textTheme.bodyMedium,
                ),
                if (!widget.canSave) ...[
                  const SizedBox(height: 12),
                  Row(
                    key: const Key('team-access-owner-only'),
                    children: [
                      const Icon(Icons.lock_outline, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('Réservé au propriétaire'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                for (final f in _shownFeatures)
                  KajCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(f.icon, size: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(context.tr(f.title),
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600)),
                                    Text(context.tr(f.subtitle),
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          _tierRow('employee', 'Employés', f),
                          _tierRow('supervisor', 'Superviseurs', f),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
              ],
            ),
      floatingActionButton: _loading || !widget.canSave
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(context.tr('Enregistrer')),
            ),
    );
  }
}

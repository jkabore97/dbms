import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';

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
  const TeamAccessScreen({super.key, required this.admin, required this.orgId});

  final AdminRepository admin;
  final String orgId;

  @override
  State<TeamAccessScreen> createState() => _TeamAccessScreenState();
}

class _Feature {
  const _Feature(this.key, this.icon, this.title, this.subtitle,
      {this.editable = true});
  final String key;
  final IconData icon;
  final String title;
  final String subtitle;

  /// False for tools that never had an edit mode to give.
  final bool editable;
}

const _features = [
  _Feature('products', Icons.inventory_2_outlined, 'Articles',
      'Les prix, les noms, les entrées de stock'),
  _Feature('production', Icons.soup_kitchen_outlined, 'Production',
      'Transformer des ingrédients en produits'),
  _Feature('credits', Icons.handshake_outlined, 'Carnet de crédit',
      'Vendre à crédit et encaisser les remboursements'),
  _Feature('tontines', Icons.group_outlined, 'Tontines',
      'Les tours, les cotisations, la caisse'),
  _Feature('invoices', Icons.receipt_long_outlined, 'Factures',
      'Créer et partager des factures'),
  _Feature('photos', Icons.photo_library_outlined, 'Photos',
      'Photographier et classer les documents'),
  _Feature('reports', Icons.menu_book_outlined, 'Comptabilité et rapports',
      'Journal, résultat, bilan', editable: false),
  _Feature('staff', Icons.groups_outlined, 'Personnel',
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

  String _defaultFor(String feature) =>
      feature == 'reports' ? 'view' : 'edit';

  Future<void> _load() async {
    try {
      final stored = await widget.admin.featureRules(widget.orgId);
      if (!mounted) return;
      setState(() {
        for (final tier in ['employee', 'supervisor']) {
          for (final f in _features) {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enregistré. Les écrans de l’équipe suivront à '
              'leur prochaine ouverture.')));
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  Widget _tierRow(String tier, String label, _Feature feature) {
    final value = _rules[tier]![feature.key]!;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              segments: [
                const ButtonSegment(value: 'hidden', label: Text('Caché')),
                const ButtonSegment(value: 'view', label: Text('Voir')),
                if (feature.editable)
                  const ButtonSegment(value: 'edit', label: Text('Modifier')),
              ],
              selected: {value},
              onSelectionChanged: _busy
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
      appBar: AppBar(title: const Text("Accès de l'équipe")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Ce que chaque niveau voit et peut modifier. Les '
                  'propriétaires et administrateurs gardent toujours tout. '
                  'Les prix, le crédit et la production sont aussi refusés '
                  'par le serveur — pas seulement cachés.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final f in _features)
                  Card(
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
                                    Text(f.title,
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600)),
                                    Text(f.subtitle,
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
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
    );
  }
}

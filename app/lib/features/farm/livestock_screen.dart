import 'package:flutter/material.dart';
import 'farm_corrections.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/models.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../../core/errors.dart';

/// Animals that are not chickens, and things that grow in the ground.
///
/// 009 built one farm — Ignace's, which is poultry — and every other farm in
/// the country was half-served by it. A herd of goats had no table and a
/// field of onions had no table, so a farmer with both was expected to record
/// their animals as a flock with a batch code and their harvest as "other
/// income".
///
/// Two tabs rather than two screens because a mixed farm is the normal case
/// here, and switching between the two halves of one farm should not be
/// navigation.
///
/// The thing this screen refuses to do: turn a harvest into money. Bringing a
/// crop in is not earning — it is earning later, or eating it — so recording
/// one moves a number on this screen and nothing in the books. Selling is a
/// separate act, and always was.
class LivestockScreen extends StatefulWidget {
  const LivestockScreen({
    super.key,
    required this.org,
    required this.farm,
    this.initialTab = 0,
  });

  final OrgSummary org;
  final FarmRepository farm;
  final int initialTab;

  @override
  State<LivestockScreen> createState() => _LivestockScreenState();
}

class _LivestockScreenState extends State<LivestockScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  List<Herd> _herds = const [];
  List<CropCycle> _crops = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final herds = await widget.farm.herds(widget.org.id);
      final crops = await widget.farm.cropCycles(widget.org.id);
      if (!mounted) return;
      setState(() {
        _herds = herds;
        _crops = crops;
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

  Future<void> _openHerd() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewHerdSheet(org: widget.org, farm: widget.farm),
    );
    if (added == true) await _load();
  }

  Future<void> _openCrop() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewCropSheet(org: widget.org, farm: widget.farm),
    );
    if (added == true) await _load();
  }

  Future<void> _herdEvent(Herd herd, String kind, String title) async {
    final quantity = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuantitySheet(
        title: title,
        subtitle: '${herd.label} — ${herd.headCount} têtes',
        label: kind == 'weight' ? 'Poids (kg)' : 'Nombre',
      ),
    );
    if (quantity == null) return;

    await _run(() => widget.farm.recordHerdEvent(
          orgId: widget.org.id,
          herdId: herd.id,
          kind: kind,
          quantity: quantity,
          clientUuid: const Uuid().v4(),
        ));
  }

  Future<void> _harvest(CropCycle cycle) async {
    final quantity = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuantitySheet(
        title: 'Récolte',
        subtitle:
            '${cycle.crop}${cycle.plotName == null ? '' : ' — ${cycle.plotName}'}',
        label: 'Quantité (${cycle.unit})',
      ),
    );
    if (quantity == null) return;

    await _run(() => widget.farm.recordHarvest(
          orgId: widget.org.id,
          cropCycleId: cycle.id,
          quantity: quantity,
          clientUuid: const Uuid().v4(),
        ));
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      await _load();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Élevage et cultures'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Animaux', icon: Icon(Icons.pets)),
            Tab(text: 'Cultures', icon: Icon(Icons.grass)),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: _tabs.index == 0 ? _openHerd : _openCrop,
          icon: const Icon(Icons.add),
          label: Text(_tabs.index == 0 ? 'Groupe' : 'Culture'),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _herdList(theme),
          _cropList(theme),
        ],
      ),
    );
  }

  Widget _herdList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _errorBox(theme),
          for (final herd in _herds)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(herd.label,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                        Text('${herd.headCount}',
                            style: theme.textTheme.headlineSmall),
                      ],
                    ),
                    Text(
                      [
                        herd.species,
                        herd.breed,
                        herd.purpose,
                      ]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (herd.losses > 0 || herd.births > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${herd.births.toStringAsFixed(0)} naissances · '
                        '${herd.losses.toStringAsFixed(0)} pertes',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              _herdEvent(herd, 'birth', 'Naissances'),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Naissance'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _herdEvent(herd, 'mortality', 'Pertes'),
                          icon:
                              const Icon(Icons.remove_circle_outline, size: 18),
                          label: const Text('Perte'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _herdEvent(herd, 'vaccination', 'Vaccination'),
                          icon: const Icon(Icons.vaccines_outlined, size: 18),
                          label: const Text('Vaccin'),
                        ),
                        if (!widget.org.isObserverOnly)
                          TextButton.icon(
                            onPressed: () => showFarmCorrections(
                              context,
                              title: herd.label,
                              farm: widget.farm,
                              kind: FarmEntryKind.herd,
                              subjectId: herd.id,
                              canWrite: true,
                            ),
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('Corriger'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && _herds.isEmpty && _error == null)
            _empty(
                theme,
                Icons.pets,
                'Aucun groupe d’animaux.',
                'Chèvres, bovins, pintades — tout ce qui n’est pas une bande '
                    'de volailles suivie séparément.'),
        ],
      ),
    );
  }

  Widget _cropList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) _errorBox(theme),
          for (final cycle in _crops)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              // A crop that should have been lifted a fortnight ago is the
              // one thing on this screen worth interrupting somebody for.
              color:
                  cycle.isOverdue ? theme.colorScheme.tertiaryContainer : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [cycle.crop, cycle.variety]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' — '),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      [
                        cycle.plotName,
                        if (cycle.plantedOn != null)
                          'semé le ${DateFormat('d MMM y', 'fr_FR').format(cycle.plantedOn!)}',
                      ].whereType<String>().join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cycle.harvested > 0
                          ? '${cycle.harvested.toStringAsFixed(0)} ${cycle.unit} récoltés'
                              '${cycle.expectedYield == null ? '' : ' sur ${cycle.expectedYield!.toStringAsFixed(0)} attendus'}'
                          : cycle.expectedYield == null
                              ? 'Rien récolté pour l’instant'
                              : '${cycle.expectedYield!.toStringAsFixed(0)} ${cycle.unit} attendus',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (cycle.daysToHarvest != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        cycle.isOverdue
                            ? 'À récolter depuis ${-cycle.daysToHarvest!} jours'
                            : 'Récolte dans ${cycle.daysToHarvest} jours',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: cycle.isOverdue
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _harvest(cycle),
                          icon:
                              const Icon(Icons.agriculture_outlined, size: 18),
                          label: const Text('Enregistrer une récolte'),
                        ),
                        if (!widget.org.isObserverOnly && cycle.harvested > 0)
                          TextButton.icon(
                            onPressed: () => showFarmCorrections(
                              context,
                              title: cycle.crop,
                              farm: widget.farm,
                              kind: FarmEntryKind.harvest,
                              subjectId: cycle.id,
                              canWrite: true,
                            ),
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('Corriger'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (!_loading && _crops.isEmpty && _error == null)
            _empty(
                theme,
                Icons.grass,
                'Aucune culture en cours.',
                'Une culture, c’est ce qui est semé sur une parcelle et à '
                    'quelle date. La parcelle est créée à partir de son nom.'),
        ],
      ),
    );
  }

  Widget _errorBox(ThemeData theme) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_error!),
      );

  Widget _empty(ThemeData theme, IconData icon, String title, String body) =>
      Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          children: [
            Icon(icon, size: 48, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      );
}

class _NewHerdSheet extends StatefulWidget {
  const _NewHerdSheet({required this.org, required this.farm});

  final OrgSummary org;
  final FarmRepository farm;

  @override
  State<_NewHerdSheet> createState() => _NewHerdSheetState();
}

class _NewHerdSheetState extends State<_NewHerdSheet> {
  final _label = TextEditingController();
  final _species = TextEditingController();
  final _breed = TextEditingController();
  final _purpose = TextEditingController();
  final _count = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_label, _species, _count]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_label, _species, _breed, _purpose, _count]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _headCount => int.tryParse(_count.text.trim());

  bool get _ready =>
      !_busy &&
      _label.text.trim().isNotEmpty &&
      _species.text.trim().isNotEmpty &&
      (_headCount ?? 0) > 0;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.farm.openHerd(
        orgId: widget.org.id,
        species: _species.text.trim(),
        label: _label.text.trim(),
        headCount: _headCount!,
        breed: _breed.text.trim(),
        purpose: _purpose.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveau groupe', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Nom du groupe',
                helperText: 'Troupeau A, Chèvres du bas-fond…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _species,
              decoration: const InputDecoration(
                labelText: 'Espèce',
                // Free text on purpose: a compiled list is wrong for the
                // first farmer with guinea fowl.
                helperText: 'Caprin, bovin, ovin, porcin, pintade…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nombre de têtes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _breed,
              decoration: const InputDecoration(
                labelText: 'Race (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _purpose,
              decoration: const InputDecoration(
                labelText: 'Destination (facultatif)',
                helperText: 'Lait, engraissement, reproduction…',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _ready ? _save : null,
              child: const Text('Créer le groupe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewCropSheet extends StatefulWidget {
  const _NewCropSheet({required this.org, required this.farm});

  final OrgSummary org;
  final FarmRepository farm;

  @override
  State<_NewCropSheet> createState() => _NewCropSheetState();
}

class _NewCropSheetState extends State<_NewCropSheet> {
  final _crop = TextEditingController();
  final _variety = TextEditingController();
  final _plot = TextEditingController();
  final _yield = TextEditingController();
  DateTime _planted = DateTime.now();
  DateTime? _expected;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _crop.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_crop, _variety, _plot, _yield]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.farm.openCropCycle(
        orgId: widget.org.id,
        crop: _crop.text.trim(),
        plotName: _plot.text.trim(),
        variety: _variety.text.trim(),
        plantedOn: _planted,
        expectedOn: _expected,
        expectedYield: double.tryParse(_yield.text.trim().replaceAll(',', '.')),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouvelle culture', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _crop,
              decoration: const InputDecoration(
                labelText: 'Culture',
                helperText: 'Oignon, maïs, tomate…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _variety,
              decoration: const InputDecoration(
                labelText: 'Variété (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _plot,
              decoration: const InputDecoration(
                labelText: 'Parcelle',
                // Created from its name if it does not exist, so nobody has
                // to define a field before planting in it.
                helperText: 'Créée automatiquement si elle est nouvelle.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _yield,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Rendement attendu en kg (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _planted,
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime(DateTime.now().year + 2),
                  helpText: 'Date de semis',
                );
                if (picked != null) setState(() => _planted = picked);
              },
              icon: const Icon(Icons.event),
              label: Text(
                  'Semé le ${DateFormat('d MMM y', 'fr_FR').format(_planted)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      _expected ?? DateTime.now().add(const Duration(days: 90)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(DateTime.now().year + 3),
                  helpText: 'Récolte prévue',
                );
                if (picked != null) setState(() => _expected = picked);
              },
              icon: const Icon(Icons.event_available),
              label: Text(_expected == null
                  ? 'Récolte prévue (facultatif)'
                  : 'Récolte prévue le ${DateFormat('d MMM y', 'fr_FR').format(_expected!)}'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy || _crop.text.trim().isEmpty ? null : _save,
              child: const Text('Enregistrer la culture'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One number, asked for once. Used for a birth, a loss, a weighing and a
/// harvest, because all four are "how many" and a separate screen for each
/// would be four screens saying the same thing.
class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet({
    required this.title,
    required this.subtitle,
    required this.label,
  });

  final String title;
  final String subtitle;
  final String label;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  final _value = TextEditingController();

  @override
  void initState() {
    super.initState();
    _value.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  double? get _number =>
      double.tryParse(_value.text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(widget.subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_number ?? 0) > 0
                ? () => Navigator.of(context).pop(_number)
                : null,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

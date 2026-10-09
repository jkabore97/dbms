import 'package:flutter/material.dart';

import '../../core/theme/kaj_card.dart';
import '../../core/nav/url_tabs.dart';
import 'farm_animal_flows.dart';
import 'farm_corrections.dart';
import 'farm_crop_flows.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../../core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

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
    required this.db,
    this.retail,
    this.initialTab = 0,
  });

  final OrgSummary org;
  final FarmRepository farm;

  /// What an animal cost is booked through (the outbox), one entry at a
  /// time (115).
  final LocalDb db;

  /// The farm's « À vendre » articles, which a harvest kept for sale is
  /// counted onto (119). Null offers only « Pour la maison ».
  final RetailRepository? retail;
  final int initialTab;

  @override
  State<LivestockScreen> createState() => _LivestockScreenState();
}

class _LivestockScreenState extends State<LivestockScreen>
    with SingleTickerProviderStateMixin, UrlTabsMixin {
  @override
  List<String> get tabSlugs => const ['animaux', 'cultures'];


  List<Herd> _herds = const [];
  List<CropCycle> _crops = const [];
  bool _loading = true;
  String? _error;

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

  // One entry at a time (115): « Ajouter des animaux », « Ajouter une
  // culture », what happens to a group, and a harvest.
  Future<void> _after(Future<bool?> flow) async {
    if (await flow == true && mounted) await _load();
  }

  Future<void> _openHerd() => _after(FarmAnimalFlow.add(context,
      db: widget.db, org: widget.org, farm: widget.farm));

  Future<void> _openCrop() =>
      _after(FarmCropFlow.add(context, org: widget.org, farm: widget.farm));

  Future<void> _herdEvent(Herd herd, String kind) => _after(
      FarmAnimalFlow.herdEvent(context,
          db: widget.db,
          org: widget.org,
          farm: widget.farm,
          herd: herd,
          kind: kind));

  Future<void> _harvest(CropCycle cycle) => _after(FarmCropFlow.harvest(context,
      org: widget.org,
      farm: widget.farm,
      retail: widget.retail,
      cropId: cycle.id));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [bellRoom],
        title: Text(context.tr('Élevage et cultures')),
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: 'Animaux', icon: Icon(Icons.pets)),
            Tab(text: 'Cultures', icon: Icon(Icons.grass)),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: tabs,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: tabs.index == 0 ? _openHerd : _openCrop,
          icon: const Icon(Icons.add),
          label: Text(tabs.index == 0 ? context.tr('Groupe') : context.tr('Culture')),
        ),
      ),
      body: TabBarView(
        controller: tabs,
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
            KajCard(
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
                        Text(context.tr('{headCount}', {'headCount': herd.headCount}),
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
                              _herdEvent(herd, 'birth'),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: Text(context.tr('Naissance')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _herdEvent(herd, 'mortality'),
                          icon:
                              const Icon(Icons.remove_circle_outline, size: 18),
                          label: Text(context.tr('Perte')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _herdEvent(herd, 'vaccination'),
                          icon: const Icon(Icons.vaccines_outlined, size: 18),
                          label: Text(context.tr('Vaccin')),
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
                            label: Text(context.tr('Corriger')),
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
            KajCard(
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
                              ? context.tr('Rien récolté pour l’instant')
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
                          label: Text(context.tr('Enregistrer une récolte')),
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
                            label: Text(context.tr('Corriger')),
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

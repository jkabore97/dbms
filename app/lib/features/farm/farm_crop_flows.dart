import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../common/step_flow.dart';
import 'farm_flows.dart';

/// What grows, one entry at a time (115): « Ajouter une culture » and
/// « Récolte ».
///
/// Both need the network, as they did: a planting is a row every phone of
/// the farm has to see (019), and a harvest is written against it on the
/// server. They say so on the summary instead of failing at the field gate.
///
/// A harvest is still not money (019). What 119 adds is where it goes: kept
/// for sale or sold now, it is counted onto the farm's « À vendre » article
/// of that crop — the shelf every sale and every vitrine order takes from,
/// and which since 101 never goes below zero — in the same transaction;
/// « Pour la maison » moves nothing, as every harvest did before.
class FarmCropFlow {
  FarmCropFlow._();

  /// « Ajouter une culture ». True once a planting was opened.
  static Future<bool?> add(
    BuildContext context, {
    required OrgSummary org,
    required FarmRepository farm,
  }) =>
      StepFlow.push(context, _AddCropFlow(org: org, farm: farm));

  /// « Récolte ». [retail] reads the farm's articles (to count the harvest
  /// in the unit an article is sold by); null offers only « Pour la
  /// maison ». [onSell] is the farm's « Vente », opened after a harvest
  /// sold on the spot. [cropId] picks the planting (« Élevage et cultures »).
  static Future<bool?> harvest(
    BuildContext context, {
    required OrgSummary org,
    FarmRepository? farm,
    RetailRepository? retail,
    VoidCallback? onSell,
    String? cropId,
  }) =>
      StepFlow.push(
          context,
          _HarvestFlow(
              org: org, farm: farm, retail: retail, onSell: onSell, cropId: cropId));
}

const _units = ['kg', 'sac', 'panier', 'plateau', 'botte', 'litre', 'pièce'];
const _newOne = '__new__';

// ----------------------------------------------------------------
// Ajouter une culture
// ----------------------------------------------------------------

class _AddCropFlow extends StatefulWidget {
  const _AddCropFlow({required this.org, required this.farm});
  final OrgSummary org;
  final FarmRepository farm;

  @override
  State<_AddCropFlow> createState() => _AddCropFlowState();
}

class _AddCropFlowState extends State<_AddCropFlow> {
  final _flow = StepFlowController();
  final _other = TextEditingController();
  final _newPlot = TextEditingController();
  final _area = TextEditingController();

  String? _crop;
  String? _plot;
  String _areaUnit = 'ha';
  DateTime _sown = DateUtils.dateOnly(DateTime.now());
  String _unit = 'kg';

  /// null: not said. Otherwise months from sowing, or 0 for a date picked.
  int? _expectIn;
  DateTime? _expected;

  List<String> _plots = const [];

  /// The area could not be written (the planting is, all the same).
  bool _areaFailed = false;

  @override
  void initState() {
    super.initState();
    _loadPlots();
  }

  Future<void> _loadPlots() async {
    try {
      final cycles = await widget.farm.cropCycles(widget.org.id, includeClosed: true);
      final names = <String>{
        for (final c in cycles)
          if ((c.plotName ?? '').trim().isNotEmpty) c.plotName!.trim(),
      }.toList()
        ..sort();
      if (mounted) setState(() => _plots = names);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_other, _newPlot, _area]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _common => [
        context.tr('Tomate'),
        context.tr('Oignon'),
        context.tr('Maïs'),
        context.tr('Gombo'),
        context.tr('Piment'),
        context.tr('Chou'),
        context.tr('Salade'),
        context.tr('Arachide'),
        context.tr('Riz'),
        context.tr('Sorgho'),
      ];

  String get _cropName => (_crop == _newOne ? _other.text : (_crop ?? '')).trim();
  String get _plotName => (_plot == _newOne ? _newPlot.text : (_plot ?? '')).trim();
  double get _areaValue => FlowNumberField.read(_area) ?? 0;

  DateTime? get _expectedOn => switch (_expectIn) {
        null => null,
        0 => _expected,
        final m => DateTime(_sown.year, _sown.month + m, _sown.day),
      };

  String _day(DateTime d) =>
      DateFormat('d MMMM y', Localizations.localeOf(context).toString()).format(d);

  Map<String, Object?> _save() => {
        'crop': _crop,
        'other': _other.text,
        'plot': _plot,
        'new_plot': _newPlot.text,
        'area': _area.text,
        'area_unit': _areaUnit,
        'sown': _sown.toIso8601String(),
        'unit': _unit,
        'expect_in': _expectIn,
        'expected': _expected?.toIso8601String(),
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _crop = a['crop'] as String?;
        _other.text = (a['other'] as String?) ?? '';
        _plot = a['plot'] as String?;
        _newPlot.text = (a['new_plot'] as String?) ?? '';
        _area.text = (a['area'] as String?) ?? '';
        _areaUnit = (a['area_unit'] as String?) ?? 'ha';
        _sown = DateTime.tryParse((a['sown'] as String?) ?? '') ??
            DateUtils.dateOnly(DateTime.now());
        _unit = (a['unit'] as String?) ?? 'kg';
        _expectIn = (a['expect_in'] as num?)?.toInt();
        _expected = DateTime.tryParse((a['expected'] as String?) ?? '');
      });

  Future<bool> _record() async {
    if (!widget.farm.isConfigured) {
      throw StateError(context.tr('Impossible pour le moment. Cela demande le réseau.'));
    }
    final id = await widget.farm.openCropCycle(
      orgId: widget.org.id,
      crop: _cropName,
      plotName: _plotName,
      plantedOn: _sown,
      expectedOn: _expectedOn,
      unit: _unit,
    );
    _areaFailed = false;
    if (_plotName.isNotEmpty && _areaValue > 0) {
      // After the planting, and never a reason to redo it: a retry would
      // open the same crop twice.
      try {
        await widget.farm.setPlotArea(
            cropCycleId: id, area: _areaValue, unit: _areaUnit);
      } catch (_) {
        _areaFailed = true;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final areaUnits = {'ha': context.tr('hectares'), 'm2': context.tr('m²')};
    return StepFlow(
      title: context.tr('Ajouter une culture'),
      controller: _flow,
      draft: FlowDraft(
          key: 'farm_crop:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'crop',
          title: context.tr('Quelle culture ?'),
          isValid: () => _cropName.isNotEmpty,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  for (final c in _common) FlowOption(c, c, icon: Icons.grass),
                  FlowOption(_newOne, context.tr('Une autre culture'), icon: Icons.add),
                ],
                value: _crop,
                onChanged: (v) => setState(() => _crop = v),
              ),
              if (_crop == _newOne)
                TextField(
                  key: const Key('farm-crop-other'),
                  controller: _other,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: context.tr('Laquelle ?'),
                    hintText: context.tr('Aubergine, haricot, sésame…'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ),
        ),
        FlowStep(
          id: 'plot',
          title: context.tr('Sur quelle parcelle ?'),
          help: context.tr('Une nouvelle est créée à partir de son nom.'),
          optional: true,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  for (final p in _plots) FlowOption(p, p, icon: Icons.crop_square),
                  FlowOption(_newOne, context.tr('Une nouvelle parcelle'),
                      icon: Icons.add),
                ],
                value: _plot,
                onChanged: (v) => setState(() => _plot = _plot == v ? null : v),
              ),
              if (_plot == _newOne)
                TextField(
                  key: const Key('farm-plot-new'),
                  controller: _newPlot,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    hintText: context.tr('Derrière la maison, bas-fond 2…'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ),
        ),
        FlowStep(
          id: 'area',
          title: context.tr('Quelle surface ?'),
          optional: true,
          shown: () => _plotName.isNotEmpty,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('farm-area'),
                controller: _area,
                suffix: areaUnits[_areaUnit],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  for (final e in areaUnits.entries)
                    ChoiceChip(
                      key: Key('farm-area-${e.key}'),
                      label: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        child: Text(e.value, style: const TextStyle(fontSize: 17)),
                      ),
                      selected: _areaUnit == e.key,
                      onSelected: (_) => setState(() => _areaUnit = e.key),
                    ),
                ],
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'sown',
          title: context.tr('Semée quand ?'),
          builder: (_) => FarmDayChoice(
            value: _sown,
            helpText: context.tr('Date de semis'),
            onChanged: (d) => setState(() => _sown = d),
          ),
        ),
        FlowStep(
          id: 'unit',
          title: context.tr('Vous la récoltez en…'),
          builder: (_) => FarmUnitChips(
            units: _units,
            value: _unit,
            onChanged: (u) => setState(() => _unit = u),
          ),
        ),
        FlowStep(
          id: 'expected',
          title: context.tr('Récolte prévue ?'),
          optional: true,
          builder: (_) => FlowChoice<int>(
            options: [
              FlowOption(1, context.tr('Dans 1 mois')),
              FlowOption(2, context.tr('Dans 2 mois')),
              FlowOption(3, context.tr('Dans 3 mois')),
              FlowOption(0, context.tr('Un autre jour'),
                  icon: Icons.event,
                  detail: _expectIn == 0 && _expected != null ? _day(_expected!) : null),
            ],
            value: _expectIn,
            onChanged: (v) async {
              if (v == _expectIn && v != 0) {
                return setState(() => _expectIn = null);
              }
              setState(() => _expectIn = v);
              if (v != 0) return;
              final picked = await showDatePicker(
                context: context,
                initialDate: _expected ?? _sown.add(const Duration(days: 90)),
                firstDate: _sown,
                lastDate: DateTime(_sown.year + 3),
                helpText: context.tr('Récolte prévue'),
              );
              if (!mounted) return;
              setState(() {
                if (picked != null) {
                  _expected = picked;
                } else if (_expected == null) {
                  _expectIn = null;
                }
              });
            },
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Culture'), _cropName, step: 'crop', bold: true),
          FlowSummaryRow(context.tr('Parcelle'),
              _plotName.isEmpty ? context.tr('Non précisée') : _plotName,
              step: 'plot'),
          if (_plotName.isNotEmpty && _areaValue > 0)
            FlowSummaryRow(context.tr('Surface'),
                '${trimQuantity(_areaValue)} ${areaUnits[_areaUnit]}',
                step: 'area'),
          FlowSummaryRow(context.tr('Semée le'), _day(_sown), step: 'sown'),
          FlowSummaryRow(context.tr('Récoltée en'), _unit, step: 'unit'),
          if (_expectedOn != null)
            FlowSummaryRow(context.tr('Récolte prévue'), _day(_expectedOn!),
                step: 'expected'),
        ],
        footer: Row(
          children: [
            const Icon(Icons.wifi, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.tr('Demande le réseau.'),
                  style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
      onSave: _record,
      done: (_) => FlowDone(
        message: _plotName.isEmpty
            ? context.tr('{crop} ajoutée', {'crop': _cropName})
            : context.tr('{crop} ajoutée · {plot}', {'crop': _cropName, 'plot': _plotName}),
        details: _areaFailed
            ? Text(context.tr('La surface n\'a pas pu être enregistrée.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error))
            : null,
        actions: [
          FlowAction(
            key: const Key('farm-again'),
            label: context.tr('Ajouter une autre culture'),
            icon: Icons.add,
            primary: true,
            onPressed: () {
              _restore(const {});
              _flow.restart();
              _loadPlots();
            },
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Récolte
// ----------------------------------------------------------------

class _HarvestFlow extends StatefulWidget {
  const _HarvestFlow({
    required this.org,
    this.farm,
    this.retail,
    this.onSell,
    this.cropId,
  });
  final OrgSummary org;
  final FarmRepository? farm;
  final RetailRepository? retail;
  final VoidCallback? onSell;
  final String? cropId;

  @override
  State<_HarvestFlow> createState() => _HarvestFlowState();
}

class _HarvestFlowState extends State<_HarvestFlow> {
  final _flow = StepFlowController();
  final _quantity = TextEditingController();
  final _converted = TextEditingController();

  List<CropCycle> _crops = const [];
  bool _loaded = false;
  List<Product> _articles = const [];
  String? _cropId;
  String _grade = 'first';

  /// 'stock' | 'sold' | 'home'
  String? _dest;
  String _clientUuid = const Uuid().v4();

  /// The server before 119: the harvest is counted, the shelf is not.
  bool _stockSkipped = false;

  bool get _online => widget.farm?.isConfigured ?? false;

  @override
  void initState() {
    super.initState();
    _cropId = widget.cropId;
    _load();
  }

  /// Best-effort and never blocking: with no signal the flow says there is
  /// nothing it can list rather than showing an error.
  Future<void> _load({String? select}) async {
    final farm = widget.farm;
    if (farm != null && farm.isConfigured) {
      try {
        final before = {for (final c in _crops) c.id};
        final crops = (await farm.cropCycles(widget.org.id))
            .where((c) => c.isOpen)
            .toList();
        if (!mounted) return;
        setState(() {
          _crops = crops;
          if (select == _newOne) {
            final fresh = crops.where((c) => !before.contains(c.id));
            if (fresh.isNotEmpty) _cropId = fresh.first.id;
          }
          // One planting in the ground: nothing to choose.
          if (_cropId == null && crops.length == 1) _cropId = crops.first.id;
        });
      } catch (_) {}
    }
    if (mounted) setState(() => _loaded = true);
    final retail = widget.retail;
    if (retail == null) return;
    try {
      final articles = await retail.products(widget.org.id);
      if (mounted) {
        setState(() => _articles = [for (final p in articles) if (!p.isService) p]);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _quantity.dispose();
    _converted.dispose();
    super.dispose();
  }

  /// The second line of a planting: which variety, which plot.
  static String? _detail(CropCycle c) {
    final parts = [c.variety, c.plotName]
        .where((p) => p != null && p.isNotEmpty)
        .join(' · ');
    return parts.isEmpty ? null : parts;
  }

  CropCycle? get _crop {
    for (final c in _crops) {
      if (c.id == _cropId) return c;
    }
    return null;
  }

  double get _qty => FlowNumberField.read(_quantity) ?? 0;
  bool get _toStock => _dest == 'stock' || _dest == 'sold';

  /// The farm's article of this crop's name, if it has one.
  Product? get _article {
    final name = _crop?.crop.trim().toLowerCase();
    if (name == null) return null;
    for (final p in _articles) {
      if (p.name.trim().toLowerCase() == name) return p;
    }
    return null;
  }

  /// The article is sold by another unit than the crop is counted in: the
  /// harvest going onto its shelf is asked in the article's unit (119
  /// refuses kilos added to trays).
  String? get _otherUnit {
    final unit = _article?.unit?.trim();
    final crop = _crop;
    if (!_toStock || unit == null || unit.isEmpty || crop == null) return null;
    return unit.toLowerCase() == crop.unit.toLowerCase() ? null : unit;
  }

  double get _shelfQty =>
      _otherUnit == null ? _qty : (FlowNumberField.read(_converted) ?? 0);
  String get _shelfUnit => _otherUnit ?? _crop?.unit ?? 'kg';

  Map<String, String> get _grades => {
        for (final e in harvestGrades.entries) e.key: context.tr(e.value),
      };

  Map<String, Object?> _save() => {
        'crop': _cropId,
        'quantity': _quantity.text,
        'converted': _converted.text,
        'grade': _grade,
        'dest': _dest,
        'uuid': _clientUuid,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _cropId = (a['crop'] as String?) ??
            widget.cropId ??
            (_crops.length == 1 ? _crops.first.id : null);
        _quantity.text = (a['quantity'] as String?) ?? '';
        _converted.text = (a['converted'] as String?) ?? '';
        _grade = (a['grade'] as String?) ?? 'first';
        _dest = a['dest'] as String?;
        _clientUuid = (a['uuid'] as String?) ?? const Uuid().v4();
      });

  Future<bool> _record() async {
    final farm = widget.farm;
    final crop = _crop;
    if (farm == null || !farm.isConfigured || crop == null) {
      throw StateError(context.tr('Enregistrement impossible. La récolte d\'une culture demande le réseau.'));
    }
    Future<void> write({required bool toStock}) => farm.recordHarvest(
          orgId: widget.org.id,
          cropCycleId: crop.id,
          quantity: _shelfQty,
          unit: _shelfUnit,
          grade: _grade,
          clientUuid: _clientUuid,
          toStock: toStock,
        );
    _stockSkipped = false;
    try {
      await write(toStock: _toStock);
    } catch (error) {
      // The app ahead of its database (119 not applied yet): the harvest is
      // counted as before, and the screen says the shelf did not move.
      if (!_toStock || !isSchemaOutOfDate(error)) rethrow;
      await write(toStock: false);
      _stockSkipped = true;
    }
    return true;
  }

  Future<void> _addCrop() async {
    final farm = widget.farm;
    if (farm == null) return;
    final added = await FarmCropFlow.add(context, org: widget.org, farm: farm);
    if (added == true && mounted) await _load(select: _newOne);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crop = _crop;
    final article = _article;
    final destLabels = {
      'stock': context.tr('Gardée pour vendre'),
      'sold': context.tr('Vendue tout de suite'),
      'home': context.tr('Pour la maison'),
    };
    return StepFlow(
      title: context.tr('Récolte'),
      controller: _flow,
      draft: FlowDraft(
          key: 'farm_harvest:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'crop',
          title: context.tr('Que récoltez-vous ?'),
          isValid: () => crop != null,
          builder: (_) {
            if (!_loaded) return const LinearProgressIndicator();
            final add = SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                key: const Key('farm-harvest-add-crop'),
                onPressed: _addCrop,
                icon: const Icon(Icons.add),
                label: Text(context.tr('Ajouter une culture')),
              ),
            );
            if (_crops.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _online
                        ? context.tr('Aucune culture en cours. Ajoutez celle que vous récoltez.')
                        : context.tr('Rien à récolter pour l\'instant. Ouvrez une culture dans « Élevage et cultures » — cela demande le réseau.'),
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (_online) ...[const SizedBox(height: 16), add],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FlowChoice<String>(
                  options: [
                    for (final c in _crops)
                      FlowOption(c.id, c.crop,
                          icon: Icons.grass, detail: _detail(c)),
                  ],
                  value: _cropId,
                  onChanged: (v) => setState(() => _cropId = v),
                ),
                add,
              ],
            );
          },
        ),
        FlowStep(
          id: 'quantity',
          title: context.tr('Combien ?'),
          isValid: () => _qty > 0,
          builder: (_) => FlowNumberField(
            key: const Key('farm-quantity'),
            controller: _quantity,
            suffix: crop?.unit,
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'grade',
          title: context.tr('Quelle qualité ?'),
          help: context.tr('Comptée à part : elle ne se vend pas au même prix.'),
          builder: (_) => FlowChoice<String>(
            options: [
              for (final e in _grades.entries) FlowOption(e.key, e.value),
            ],
            value: _grade,
            onChanged: (v) => setState(() => _grade = v),
          ),
        ),
        FlowStep(
          id: 'dest',
          title: context.tr('Où va la récolte ?'),
          isValid: () => _dest != null && (_otherUnit == null || _shelfQty > 0),
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  if (widget.retail != null) ...[
                    FlowOption('stock', destLabels['stock']!,
                        icon: Icons.inventory_2_outlined,
                        detail: context.tr('Ajoutée à « À vendre »')),
                    FlowOption('sold', destLabels['sold']!,
                        icon: Icons.point_of_sale_outlined,
                        detail: context.tr('Ajoutée à « À vendre », puis la vente')),
                  ],
                  FlowOption('home', destLabels['home']!,
                      icon: Icons.home_outlined,
                      detail: context.tr('Mangée, donnée : le stock ne change pas')),
                ],
                value: _dest,
                onChanged: (v) => setState(() => _dest = v),
              ),
              if (_otherUnit != null) ...[
                Text(
                  context.tr('« {name} » se vend par {unit}. En {unit}, cela fait combien ?',
                      {'name': article!.name, 'unit': _otherUnit}),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                FlowNumberField(
                  key: const Key('farm-converted'),
                  controller: _converted,
                  suffix: _otherUnit,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Culture'), crop?.crop ?? '', step: 'crop'),
          FlowSummaryRow(
              context.tr('Quantité'),
              _otherUnit == null
                  ? '${trimQuantity(_qty)} ${crop?.unit ?? ''}'
                  // Counted as the article is sold: the harvest is written so.
                  : '${trimQuantity(_shelfQty)} $_shelfUnit (${trimQuantity(_qty)} ${crop?.unit ?? ''})',
              step: 'quantity', bold: true),
          FlowSummaryRow(context.tr('Qualité'), _grades[_grade] ?? '', step: 'grade'),
          FlowSummaryRow(context.tr('Où'), destLabels[_dest] ?? '', step: 'dest'),
          if (_toStock)
            FlowSummaryRow(
                context.tr('En stock'),
                article == null
                    ? context.tr('Nouvel article « {name} », hors vitrine',
                        {'name': crop?.crop ?? ''})
                    : context.tr('+{q} {unit} sur « {name} »', {
                        'q': trimQuantity(_shelfQty),
                        'unit': _shelfUnit,
                        'name': article.name,
                      })),
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Production, pas recette : l\'argent vient à la vente.'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.wifi, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('Demande le réseau.'),
                      style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ],
        ),
      ),
      onSave: _record,
      done: (_) {
        final unpriced = _toStock && !_stockSkipped && (article == null || article.salePrice == 0);
        final router = GoRouter.maybeOf(context);
        return FlowDone(
          message: context.tr('{crop} : {q} {unit} récoltés', {
            'q': trimQuantity(_shelfQty),
            'unit': _shelfUnit,
            'crop': crop?.crop ?? '',
          }),
          details: Text(
            _stockSkipped
                ? context.tr('Le stock de « À vendre » n\'a pas changé : mettez-le à jour dans À vendre.')
                : !_toStock
                    ? context.tr('Le stock ne change pas.')
                    : unpriced
                        ? context.tr('Ajoutés à « {name} » dans À vendre. Mettez-lui un prix pour la vendre.',
                            {'name': article?.name ?? crop?.crop ?? ''})
                        : context.tr('Ajoutés à « {name} » dans À vendre.',
                            {'name': article?.name ?? crop?.crop ?? ''}),
            textAlign: TextAlign.center,
          ),
          actions: [
            if (_dest == 'sold' && widget.onSell != null)
              FlowAction(
                key: const Key('farm-harvest-sell'),
                label: context.tr('Enregistrer la vente'),
                icon: Icons.point_of_sale_outlined,
                primary: true,
                onPressed: () {
                  final sell = widget.onSell!;
                  Navigator.of(context).pop(true);
                  sell();
                },
              ),
            if (unpriced && router != null)
              FlowAction(
                key: const Key('farm-harvest-price'),
                label: context.tr('Mettre un prix'),
                icon: Icons.sell_outlined,
                primary: _dest != 'sold',
                onPressed: () {
                  Navigator.of(context).pop(true);
                  router.push(Routes.inside(widget.org.id, 'a-vendre'));
                },
              ),
            FlowAction(
              key: const Key('farm-again'),
              label: context.tr('Une autre récolte'),
              icon: Icons.add,
              primary: _dest != 'sold' && !unpriced,
              onPressed: () {
                _restore(const {});
                _flow.restart();
                _load();
              },
            ),
          ],
        );
      },
    );
  }
}

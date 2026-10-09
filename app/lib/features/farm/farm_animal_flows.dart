import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../common/step_flow.dart';

/// The farm's animals, one entry at a time (115): « Ajouter des animaux »
/// and « Mortalité » (with the rest of what happens to a batch: a weighing,
/// a vaccination, animals sold alive, a birth in a herd).
///
/// Two kinds of group, as since 019: a poultry batch is a *flock* (009 —
/// counted from this phone, offline, through the outbox), any other animal
/// a *herd* (019 — recorded on the server). Opening either needs the
/// network, as before: a name two phones invent offline would split one
/// batch's history in two. A flock's events stay offline; a herd's need
/// the network, as they did.
class FarmAnimalFlow {
  FarmAnimalFlow._();

  /// « Ajouter des animaux ». True once a group was opened.
  static Future<bool?> add(
    BuildContext context, {
    required LocalDb db,
    required OrgSummary org,
    required FarmRepository farm,
  }) =>
      StepFlow.push(context, _AddAnimalsFlow(db: db, org: org, farm: farm));

  /// « Mortalité » from the farm's home: which batch, how many, why. [kind]
  /// null asks what happened too.
  static Future<bool?> event(
    BuildContext context, {
    required LocalDb db,
    required OrgSummary org,
    FarmRepository? farm,
    String? kind = 'mortality',
  }) =>
      StepFlow.push(
          context, _EventFlow(db: db, org: org, farm: farm, kind: kind));

  /// What happened to one flock (« Bandes »): the batch is known, the event
  /// is asked.
  static Future<bool?> flockEvent(
    BuildContext context, {
    required LocalDb db,
    required OrgSummary org,
    required Flock flock,
  }) =>
      StepFlow.push(
          context,
          _EventFlow(
            db: db,
            org: org,
            kind: null,
            preset: _Group(flock.id, flock.batchCode, true, flock.alive),
          ));

  /// What happened to one herd (« Élevage et cultures »): its button says
  /// which event.
  static Future<bool?> herdEvent(
    BuildContext context, {
    required LocalDb db,
    required OrgSummary org,
    required FarmRepository farm,
    required Herd herd,
    required String kind,
  }) =>
      StepFlow.push(
          context,
          _EventFlow(
            db: db,
            org: org,
            farm: farm,
            kind: kind,
            preset: _Group(herd.id, herd.label, false, herd.headCount),
          ));
}

/// A batch of birds or a group of other animals.
class _Group {
  const _Group(this.id, this.label, this.isFlock, this.alive);
  final String id;
  final String label;
  final bool isFlock;

  /// As last heard: for a flock, maybe days old (warned, never refused —
  /// 009 makes the real check); for a herd, read just now.
  final int? alive;
}

// ----------------------------------------------------------------
// Ajouter des animaux
// ----------------------------------------------------------------

class _Species {
  const _Species(this.value, this.label, this.icon, {this.poultry = false});
  final String value;
  final String label;
  final IconData icon;

  /// Kept as a flock (009): counted offline, eggs and lay rate.
  final bool poultry;
}

class _AddAnimalsFlow extends StatefulWidget {
  const _AddAnimalsFlow({required this.db, required this.org, required this.farm});
  final LocalDb db;
  final OrgSummary org;
  final FarmRepository farm;

  @override
  State<_AddAnimalsFlow> createState() => _AddAnimalsFlowState();
}

class _AddAnimalsFlowState extends State<_AddAnimalsFlow> {
  final _flow = StepFlowController();
  final _other = TextEditingController();
  final _name = TextEditingController();
  final _count = TextEditingController();
  final _age = TextEditingController();
  final _cost = TextEditingController();

  String? _species;

  /// 'today' | 'date' | 'age'
  String? _when;
  DateTime? _arrived;
  String _ageUnit = 'semaines';

  /// The name filled in for the person, replaced if they change species and
  /// have not typed their own.
  String _suggested = '';

  List<_Species> get _all => [
        _Species('pondeuses', context.tr('Poules pondeuses'), Icons.egg_outlined, poultry: true),
        _Species('chair', context.tr('Poulets de chair'), Icons.set_meal_outlined, poultry: true),
        _Species('pintades', context.tr('Pintades'), Icons.flutter_dash, poultry: true),
        _Species('canards', context.tr('Canards'), Icons.water_outlined, poultry: true),
        _Species('caprin', context.tr('Chèvres'), Icons.pets),
        _Species('ovin', context.tr('Moutons'), Icons.pets),
        _Species('bovin', context.tr('Bœufs'), Icons.pets),
        _Species('porcin', context.tr('Porcs'), Icons.pets),
        _Species('lapin', context.tr('Lapins'), Icons.cruelty_free_outlined),
        _Species('autre', context.tr('Autres animaux'), Icons.add),
      ];

  _Species? get _chosen {
    for (final s in _all) {
      if (s.value == _species) return s;
    }
    return null;
  }

  bool get _poultry => _chosen?.poultry ?? false;
  String get _speciesLabel =>
      _species == 'autre' ? _other.text.trim() : (_chosen?.label ?? '');
  int get _heads => int.tryParse(_count.text.trim()) ?? 0;
  double get _price => FlowNumberField.read(_cost) ?? 0;
  NumberFormat get _money => moneyFormat(widget.org.currency);

  /// The day the group's age is counted from: 009's flock age and 019's
  /// herd are read from it. Given an age, it is that many weeks or months
  /// back — so « 8 semaines » reads 8 weeks old on the batch's card.
  DateTime? get _arrivedOn {
    final today = DateUtils.dateOnly(DateTime.now());
    switch (_when) {
      case 'today':
        return today;
      case 'date':
        return _arrived;
      case 'age':
        final n = int.tryParse(_age.text.trim()) ?? 0;
        if (n <= 0) return null;
        return _ageUnit == 'mois'
            ? DateTime(today.year, today.month - n, today.day)
            : today.subtract(Duration(days: 7 * n));
    }
    return null;
  }

  void _pickSpecies(String value) {
    setState(() {
      _species = value;
      final now = DateTime.now();
      final suggestion = (_chosen?.poultry ?? false)
          ? 'B-${now.year}-${now.month.toString().padLeft(2, '0')}'
          : (value == 'autre' ? '' : (_chosen?.label ?? ''));
      if (_name.text.trim().isEmpty || _name.text == _suggested) {
        _name.text = suggestion;
      }
      _suggested = suggestion;
    });
  }

  Map<String, Object?> _save() => {
        'species': _species,
        'other': _other.text,
        'name': _name.text,
        'suggested': _suggested,
        'count': _count.text,
        'when': _when,
        'arrived': _arrived?.toIso8601String(),
        'age': _age.text,
        'age_unit': _ageUnit,
        'cost': _cost.text,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _species = a['species'] as String?;
        _other.text = (a['other'] as String?) ?? '';
        _name.text = (a['name'] as String?) ?? '';
        _suggested = (a['suggested'] as String?) ?? '';
        _count.text = (a['count'] as String?) ?? '';
        _when = a['when'] as String?;
        _arrived = DateTime.tryParse((a['arrived'] as String?) ?? '');
        _age.text = (a['age'] as String?) ?? '';
        _ageUnit = (a['age_unit'] as String?) ?? 'semaines';
        _cost.text = (a['cost'] as String?) ?? '';
      });

  @override
  void dispose() {
    for (final c in [_other, _name, _count, _age, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _record() async {
    if (!widget.farm.isConfigured) {
      throw StateError(context.tr('Ajouter des animaux demande le réseau.'));
    }
    final name = _name.text.trim();
    final paid = context.tr('Achat d\'animaux — {name}', {'name': name});
    if (_poultry) {
      await widget.farm.openFlock(
        orgId: widget.org.id,
        batchCode: name,
        birdCount: _heads,
        breed: _speciesLabel,
        arrivedOn: _arrivedOn,
      );
      // The new batch offered at once by « Mortalité », even with no signal
      // later today.
      try {
        final flocks = await widget.farm.flocks(widget.org.id);
        await widget.db.cacheFlocks(
            widget.org.id, flocks.map((f) => f.toCache()).toList());
      } catch (_) {}
    } else {
      await widget.farm.openHerd(
        orgId: widget.org.id,
        species: _species == 'autre' ? _speciesLabel : _species!,
        label: name,
        headCount: _heads,
        arrivedOn: _arrivedOn,
      );
    }
    // What they cost: an expense like any other, through the outbox — the
    // group is open on the server already, the money follows when it can.
    if (_price > 0) {
      await widget.db.recordEntry(
        orgId: widget.org.id,
        amount: _price,
        direction: 'out',
        label: paid,
        category: 'Achat d\'animaux',
        details: {'animaux': '$_heads', 'groupe': name},
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrived = _arrivedOn;
    final format = DateFormat('d MMMM y', Localizations.localeOf(context).toString());
    return StepFlow(
      title: context.tr('Ajouter des animaux'),
      controller: _flow,
      draft: FlowDraft(
          key: 'farm_animals:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'species',
          title: context.tr('Quels animaux ?'),
          isValid: () => _speciesLabel.isNotEmpty,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  for (final s in _all) FlowOption(s.value, s.label, icon: s.icon),
                ],
                value: _species,
                onChanged: _pickSpecies,
              ),
              if (_species == 'autre')
                TextField(
                  key: const Key('farm-species-other'),
                  controller: _other,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    labelText: context.tr('Lesquels ?'),
                    hintText: context.tr('Dindes, ânes, escargots…'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ),
        ),
        FlowStep(
          id: 'name',
          title: _poultry
              ? context.tr('Quel nom pour cette bande ?')
              : context.tr('Quel nom pour ce groupe ?'),
          help: context.tr('Un nom à vous, pour les retrouver. Deux lots ne portent pas le même.'),
          isValid: () => _name.text.trim().isNotEmpty,
          builder: (_) => TextField(
            key: const Key('farm-group-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: _poultry ? 'B-2026-01' : context.tr('Chèvres du bas-fond'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'count',
          title: context.tr('Combien ?'),
          isValid: () => _heads > 0,
          builder: (_) => FlowNumberField(
            key: const Key('farm-count'),
            controller: _count,
            decimal: false,
            suffix: _speciesLabel,
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'when',
          title: context.tr('Depuis quand ?'),
          help: context.tr('Leur âge se compte à partir de là.'),
          isValid: () => _arrivedOn != null,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  FlowOption('today', context.tr('Ils arrivent aujourd\'hui'),
                      icon: Icons.today),
                  FlowOption('date', context.tr('Ils sont arrivés un autre jour'),
                      icon: Icons.event,
                      detail: _when == 'date' && _arrived != null
                          ? format.format(_arrived!)
                          : null),
                  FlowOption('age', context.tr('Je connais leur âge'),
                      icon: Icons.cake_outlined),
                ],
                value: _when,
                onChanged: (v) async {
                  setState(() => _when = v);
                  if (v != 'date') return;
                  final today = DateUtils.dateOnly(DateTime.now());
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _arrived ?? today,
                    firstDate: DateTime(today.year - 10),
                    lastDate: today,
                    helpText: context.tr('Arrivés le'),
                  );
                  if (picked != null && mounted) setState(() => _arrived = picked);
                },
              ),
              if (_when == 'age') ...[
                FlowNumberField(
                  key: const Key('farm-age'),
                  controller: _age,
                  decimal: false,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final u in const ['semaines', 'mois'])
                      ChoiceChip(
                        key: Key('farm-age-$u'),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 8),
                          child: Text(u == 'mois'
                              ? context.tr('mois')
                              : context.tr('semaines'),
                              style: const TextStyle(fontSize: 17)),
                        ),
                        selected: _ageUnit == u,
                        onSelected: (_) => setState(() => _ageUnit = u),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'cost',
          title: context.tr('Combien les avez-vous payés ?'),
          help: context.tr('Le total. Laissez vide s\'ils sont nés chez vous ou donnés.'),
          optional: true,
          builder: (_) => FlowNumberField(
            key: const Key('farm-cost'),
            controller: _cost,
            decimal: false,
            suffix: widget.org.currency,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Animaux'), _speciesLabel, step: 'species'),
          FlowSummaryRow(_poultry ? context.tr('Bande') : context.tr('Groupe'),
              _name.text.trim(),
              step: 'name'),
          FlowSummaryRow(context.tr('Nombre'), '$_heads', step: 'count', bold: true),
          FlowSummaryRow(
              _when == 'age' ? context.tr('Âge') : context.tr('Arrivés le'),
              _when == 'age'
                  ? '${_age.text.trim()} ${_ageUnit == 'mois' ? context.tr('mois') : context.tr('semaines')}'
                  : (arrived == null ? '' : format.format(arrived)),
              step: 'when'),
          FlowSummaryRow(context.tr('Coût'),
              _price > 0 ? _money.format(_price) : context.tr('Rien payé'),
              step: 'cost'),
        ],
        footer: Row(
          children: [
            const Icon(Icons.wifi, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('Demande le réseau : le nom doit être unique dans toute l\'activité.'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{n} {species} ajoutés · {name}', {
          'n': _heads,
          'species': _speciesLabel,
          'name': _name.text.trim(),
        }),
        details: _price > 0
            ? Text(
                context.tr('{amount} comptés en dépense « Achat d\'animaux ».',
                    {'amount': _money.format(_price)}),
                textAlign: TextAlign.center,
              )
            : null,
        actions: [
          FlowAction(
            key: const Key('farm-again'),
            label: context.tr('Ajouter d\'autres animaux'),
            icon: Icons.add,
            primary: true,
            onPressed: () {
              _restore(const {});
              _flow.restart();
            },
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------
// Mortalité (and what else happens to a batch)
// ----------------------------------------------------------------

class _EventFlow extends StatefulWidget {
  const _EventFlow({
    required this.db,
    required this.org,
    this.farm,
    this.kind,
    this.preset,
  });
  final LocalDb db;
  final OrgSummary org;
  final FarmRepository? farm;
  final String? kind;
  final _Group? preset;

  @override
  State<_EventFlow> createState() => _EventFlowState();
}

class _EventFlowState extends State<_EventFlow> {
  final _flow = StepFlowController();
  final _count = TextEditingController();
  final _note = TextEditingController();

  List<_Group> _groups = const [];
  bool _loaded = false;
  String? _groupId;
  late String? _kind = widget.kind;
  String? _cause;

  /// One per entry: a herd's event is a server call, and a retry after a
  /// stalled answer must not count the same deaths twice (019).
  String _clientUuid = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    if (preset != null) {
      _groups = [preset];
      _groupId = preset.id;
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final flocks = await widget.db.cachedFlocks(widget.org.id);
    if (!mounted) return;
    setState(() {
      _groups = [
        for (final f in flocks)
          _Group(f['flock_id'] as String, f['batch_code'] as String, true,
              f['alive'] as int?),
      ];
      // One batch is the common case and needs no choosing.
      if (_groups.length == 1) _groupId ??= _groups.first.id;
    });
    final farm = widget.farm;
    if (farm != null && farm.isConfigured) {
      try {
        final herds = await farm.herds(widget.org.id);
        if (mounted && herds.isNotEmpty) {
          setState(() {
            _groups = [
              ..._groups,
              for (final h in herds) _Group(h.id, h.label, false, h.headCount),
            ];
            if (_groups.length > 1 &&
                _groupId != null &&
                !_groupPicked) {
              _groupId = null;
            }
          });
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loaded = true);
  }

  /// Picked by the person, not by « only one ».
  bool _groupPicked = false;

  _Group? get _group {
    for (final g in _groups) {
      if (g.id == _groupId) return g;
    }
    return null;
  }

  bool get _isFlock => _group?.isFlock ?? true;

  Map<String, String> get _kinds => _isFlock
      ? {
          'mortality': context.tr('Mortalité'),
          'weight': context.tr('Pesée'),
          'vaccination': context.tr('Vaccination'),
          'sold': context.tr('Vendus vivants'),
        }
      : {
          'mortality': context.tr('Mortalité'),
          'birth': context.tr('Naissance'),
          'weight': context.tr('Pesée'),
          'vaccination': context.tr('Vaccination'),
          'treatment': context.tr('Traitement'),
          'sold': context.tr('Vendus vivants'),
        };

  String get _unit => switch (_kind) {
        'weight' => _isFlock ? context.tr('grammes') : 'kg',
        'vaccination' when _isFlock => context.tr('doses'),
        _ => _isFlock ? context.tr('oiseaux') : context.tr('têtes'),
      };

  bool get _counts => _kind == 'mortality' || _kind == 'sold' || _kind == 'birth';
  double get _qty => FlowNumberField.read(_count) ?? 0;

  /// More gone than were there: warned for a flock (this phone's count may
  /// be days behind, 009 checks), refused for a herd (read just now, and 019
  /// refuses it).
  bool get _tooMany {
    final alive = _group?.alive;
    return alive != null &&
        (_kind == 'mortality' || _kind == 'sold') &&
        _qty > alive;
  }

  List<String> get _causes => _kind == 'mortality'
      ? [
          context.tr('Maladie'),
          context.tr('Chaleur'),
          context.tr('Prédateur'),
          context.tr('Accident'),
          context.tr('Je ne sais pas'),
        ]
      : const [];

  String? get _memo {
    final parts = [
      ?_cause,
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Map<String, Object?> _save() => {
        'group': _groupId,
        'picked': _groupPicked,
        'kind': _kind,
        'count': _count.text,
        'cause': _cause,
        'note': _note.text,
        'uuid': _clientUuid,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        if (widget.preset == null) {
          _groupId = a['group'] as String?;
          _groupPicked = a['picked'] == true;
          if (_groupId == null && _groups.length == 1) _groupId = _groups.first.id;
        }
        _kind = widget.kind ?? a['kind'] as String?;
        _count.text = (a['count'] as String?) ?? '';
        _cause = a['cause'] as String?;
        _note.text = (a['note'] as String?) ?? '';
        _clientUuid = (a['uuid'] as String?) ?? const Uuid().v4();
      });

  @override
  void dispose() {
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<bool> _record() async {
    final group = _group!;
    if (group.isFlock) {
      await widget.db.recordFlockEvent(
        orgId: widget.org.id,
        flockId: group.id,
        batchCode: group.label,
        kind: _kind!,
        quantity: _qty,
        note: _memo,
      );
    } else {
      final farm = widget.farm;
      if (farm == null || !farm.isConfigured) {
        throw StateError(context.tr('Un groupe d\'animaux demande le réseau.'));
      }
      await farm.recordHerdEvent(
        orgId: widget.org.id,
        herdId: group.id,
        kind: _kind!,
        quantity: _qty,
        note: _memo,
        clientUuid: _clientUuid,
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = _group;
    return StepFlow(
      title: widget.kind == 'mortality'
          ? context.tr('Mortalité')
          : (widget.preset?.label ?? context.tr('Animaux')),
      controller: _flow,
      draft: FlowDraft(
          key: 'farm_event:${widget.org.id}:${widget.preset?.id ?? widget.kind ?? ''}',
          save: _save,
          restore: _restore),
      steps: [
        FlowStep(
          id: 'group',
          title: context.tr('Quels animaux ?'),
          shown: () => widget.preset == null && !(_groups.length == 1 && _loaded),
          isValid: () => group != null,
          builder: (_) => _groups.isEmpty
              ? (_loaded
                  ? Text(
                      context.tr('Aucune bande enregistrée. Ouvrez-en une avec « Ajouter des animaux » — cela demande le réseau.'),
                      style: theme.textTheme.bodyLarge,
                    )
                  : const LinearProgressIndicator())
              : FlowChoice<String>(
                  options: [
                    for (final g in _groups)
                      FlowOption(g.id, g.label,
                          icon: g.isFlock ? Icons.egg_outlined : Icons.pets,
                          detail: g.alive == null
                              ? null
                              : (g.isFlock
                                  ? context.tr('{n} oiseaux', {'n': g.alive})
                                  : context.tr('{n} têtes', {'n': g.alive}))),
                  ],
                  value: _groupId,
                  onChanged: (v) => setState(() {
                    _groupId = v;
                    _groupPicked = true;
                    if (_kind != null && !_kinds.containsKey(_kind)) _kind = null;
                  }),
                ),
        ),
        FlowStep(
          id: 'kind',
          title: context.tr('Que s\'est-il passé ?'),
          shown: () => widget.kind == null,
          isValid: () => _kind != null,
          builder: (_) => FlowChoice<String>(
            options: [
              for (final e in _kinds.entries) FlowOption(e.key, e.value),
            ],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
        ),
        FlowStep(
          id: 'count',
          title: switch (_kind) {
            'mortality' => context.tr('Combien sont morts ?'),
            'weight' => context.tr('Quel poids ?'),
            'birth' => context.tr('Combien sont nés ?'),
            'sold' => context.tr('Combien sont vendus ?'),
            _ => context.tr('Combien ?'),
          },
          help: group?.alive == null || !_counts
              ? null
              : (group!.isFlock
                  ? context.tr('{n} oiseaux au dernier point', {'n': group.alive})
                  : context.tr('{n} têtes aujourd\'hui', {'n': group.alive})),
          isValid: () => _qty > 0 && !(_tooMany && !_isFlock),
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('farm-count'),
                controller: _count,
                decimal: _kind == 'weight',
                suffix: _unit,
                onChanged: (_) => setState(() {}),
              ),
              if (_tooMany) ...[
                const SizedBox(height: 12),
                Text(
                  _isFlock
                      ? context.tr('Plus que le dernier effectif connu ({alive}). Vérifiez le chiffre — le serveur refusera si la bande est plus petite.', {'alive': group?.alive})
                      : context.tr('Il n\'y a que {n} têtes dans ce groupe.', {'n': group?.alive}),
                  key: const Key('farm-too-many'),
                  style: TextStyle(
                      color: theme.colorScheme.error, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
        FlowStep(
          id: 'cause',
          title: _kind == 'mortality' ? context.tr('De quoi ?') : context.tr('Une note ?'),
          optional: true,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_causes.isNotEmpty) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _causes)
                      ChoiceChip(
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(c, style: const TextStyle(fontSize: 16)),
                        ),
                        selected: _cause == c,
                        onSelected: (on) => setState(() => _cause = on ? c : null),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                key: const Key('farm-note'),
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.tr('Chaleur, Newcastle, poulailler 2…'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(
              group?.isFlock ?? true ? context.tr('Bande') : context.tr('Groupe'),
              group?.label ?? '',
              step: widget.preset == null && _groups.length > 1 ? 'group' : null),
          FlowSummaryRow(context.tr('Quoi'), _kinds[_kind] ?? '',
              step: widget.kind == null ? 'kind' : null),
          FlowSummaryRow(context.tr('Nombre'), '${trimQuantity(_qty)} $_unit',
              step: 'count', bold: true),
          if (_memo != null) FlowSummaryRow(context.tr('Note'), _memo!, step: 'cause'),
        ],
        footer: Row(
          children: [
            Icon(_isFlock ? Icons.cloud_off_outlined : Icons.wifi, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isFlock
                    ? context.tr('Fonctionne sans connexion : envoyé dès que le réseau revient.')
                    : context.tr('Un groupe d\'animaux demande le réseau.'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{kind} : {n} {unit} · {group}', {
          'kind': _kinds[_kind] ?? '',
          'n': trimQuantity(_qty),
          'unit': _unit,
          'group': group?.label ?? '',
        }),
        actions: [
          FlowAction(
            key: const Key('farm-again'),
            label: context.tr('Enregistrer autre chose'),
            icon: Icons.add,
            primary: true,
            onPressed: () {
              _restore(const {});
              _flow.restart();
            },
          ),
        ],
      ),
    );
  }
}

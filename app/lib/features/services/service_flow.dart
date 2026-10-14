import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/retail/duration.dart';
import '../../core/retail/retail_repository.dart';
import '../capture/capture_action.dart';
import '../common/step_flow.dart';
import '../retail/item_details.dart';
import '../retail/photo_quota.dart';

/// « Service », one entry at a time (115) — the shop's, the farm's and the
/// association's (098's « Mes services »): a photo (taken, chosen, or
/// « Choisir dans Photos », 114) → the name → the price, or « à partir
/// de » → how long it takes (optional) → « Décrivez-le en quelques mots »
/// (optional, 136) → on the vitrine or not → the summary → « Enregistrer »
/// → « C'est fait », « Ajouter un autre service ».
///
/// A service is a product row with `is_service` (098), written as the
/// sheet it replaces wrote it: ensure_product() as a service (the server
/// refuses a name an article holds), then its price, « à partir de »,
/// unit and vitrine. The duration is its own column since 136
/// (duration_minutes, « Durée : 1 h » on the vitrine); before 136 it opens
/// the description as it always did (« Durée : 1 h », then the words).
/// Online, as the sheet was.
class ServiceFlow extends StatefulWidget {
  const ServiceFlow({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
    this.store,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final CaptureRepository? capture;
  final FlowStore? store;

  @override
  State<ServiceFlow> createState() => _ServiceFlowState();
}

class _ServiceFlowState extends State<ServiceFlow> {
  final _flow = StepFlowController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  String _unit = '';
  bool _from = false;
  int? _minutes;
  bool _published = true;
  PickedPhoto? _photo;
  String _savedName = '';
  bool _photoWaits = false;

  /// The description or the duration refused while the rest was saved.
  bool _descriptionLost = false;

  /// The words' room: before 136 (or not yet known) « Durée : 1 h » and its
  /// line break open the same 300 characters.
  int get _describeMax => widget.retail.descriptionMax -
      (widget.retail.itemPhotosLive ? 0 : RetailRepository.legacyDurationPrefix(_minutes));

  /// What a service is counted by, one tap each (as the sheet's).
  static const _units = ['heure', 'séance', 'personne', 'jour', 'mois'];

  NumberFormat get _money => moneyFormat(widget.org.currency);
  double? get _priceValue => FlowNumberField.readAmount(_price, widget.org.currency);

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    super.dispose();
  }

  void _reset() {
    _name.clear();
    _price.clear();
    _description.clear();
    _unit = '';
    _from = false;
    _minutes = null;
    _published = true;
    _photo = null;
  }

  Map<String, Object?> _save() => {
        'name': _name.text,
        'price': _price.text,
        'unit': _unit,
        'from': _from,
        'minutes': _minutes,
        'description': _description.text,
        'published': _published,
      };

  void _restore(Map<String, Object?> a) {
    setState(() {
      _reset();
      _name.text = '${a['name'] ?? ''}';
      _price.text = '${a['price'] ?? ''}';
      _unit = '${a['unit'] ?? ''}';
      _from = a['from'] == true;
      final m = a['minutes'];
      // A draft from before 136 kept the words (« 1 h », « Autre » typed).
      _minutes = m is int
          ? m
          : durationMinutesOf(a['duration'] == 'other' ? '${a['other'] ?? ''}' : '${a['duration'] ?? ''}');
      _description.text = '${a['description'] ?? ''}';
      _published = a['published'] != false;
    });
  }

  Future<void> _pickPhoto() async {
    final capture = widget.capture;
    if (capture == null) return;
    if (!await photoAllowed(context, widget.org, hasPhoto: false) || !mounted) return;
    final picked =
        await CaptureAction.pick(context, orgId: widget.org.id, photos: capture);
    if (picked == null || !mounted) return;
    setState(() => _photo = picked);
  }

  Future<bool> _record() async {
    final name = _name.text.trim();
    final price = _priceValue!;
    final orgId = widget.org.id;
    // The server refuses a name an article holds, retired or not (098): a
    // service never turns an article into one.
    final id = await widget.retail.ensureProduct(
      orgId: orgId,
      name: name,
      salePrice: price,
      isService: true,
    );
    final words = _description.text.trim();
    await widget.retail.updateProduct(
      id,
      name: name,
      salePrice: price,
      unit: _unit,
      isPublished: _published,
      isService: true,
      priceFrom: _from,
    );
    // The words, and the duration — its own column since 136, before it the
    // description's first line: their own writes, so that a refusal never
    // takes the name, the price and the vitrine with it.
    _descriptionLost = false;
    try {
      if (words.isNotEmpty) await widget.retail.updateProduct(id, description: words);
      if (_minutes != null) {
        await widget.retail.setServiceDuration(id, _minutes, description: words);
      }
    } catch (_) {
      _descriptionLost = true;
    }
    final photo = _photo;
    final capture = widget.capture;
    _photoWaits = false;
    if (photo != null && capture != null) {
      final doc = await CaptureAction.hang(
        capture,
        orgId: orgId,
        productId: id,
        name: name,
        photo: photo,
        hadPhoto: false,
      );
      _photoWaits = doc == null;
      if (doc != null && mounted) {
        await AppScope.read(context)?.session.reloadFeatures(orgId);
      }
    }
    _savedName = name;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StepFlow(
      title: context.tr('Nouveau service'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(key: 'service:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'photo',
          title: context.tr('Une photo ?'),
          help: context.tr('Elle paraît sur la vitrine et dans la recherche.'),
          optional: true,
          shown: () => widget.capture != null && widget.capture!.isConfigured,
          builder: _photoStep,
        ),
        FlowStep(
          id: 'name',
          title: context.tr('Quel service ?'),
          isValid: () => _name.text.trim().isNotEmpty,
          builder: (_) => TextField(
            key: const Key('service-flow-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.titleLarge,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr('Coupe homme, cours de maths…'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        FlowStep(
          id: 'price',
          title: context.tr('Quel prix ?'),
          isValid: () => (_priceValue ?? 0) > 0,
          builder: _priceStep,
        ),
        FlowStep(
          id: 'duration',
          title: context.tr('Combien de temps ?'),
          help: context.tr('Écrit sous son nom, sur la vitrine.'),
          optional: true,
          isEmpty: () => _minutes == null,
          builder: (_) => DurationPicker(
            key: const Key('service-flow-duration'),
            minutes: _minutes,
            onChanged: (m) {
              setState(() => _minutes = m);
              _flow.keep();
            },
          ),
        ),
        FlowStep(
          id: 'describe',
          title: context.tr('Décrivez-le en quelques mots'),
          help: context.tr('Ce que le client lit avant de réserver, sur la vitrine.'),
          optional: true,
          isValid: () => descriptionLength(_description.text) <= _describeMax,
          isEmpty: () => _description.text.trim().isEmpty,
          builder: (_) => DescriptionField(
            key: const Key('service-flow-description'),
            controller: _description,
            autofocus: true,
            maxLength: _describeMax,
            example: describeExample(context, widget.org, service: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'vitrine',
          title: context.tr('Sur la vitrine ?'),
          help: context.tr('Les clients le voient et le réservent, si votre vitrine est ouverte.'),
          builder: (_) => FlowChoice<bool>(
            options: [
              FlowOption(true, context.tr('Oui, sur la vitrine'), icon: Icons.storefront),
              FlowOption(false, context.tr('Non, pas pour l\'instant'), icon: Icons.storefront_outlined),
            ],
            value: _published,
            onChanged: (v) {
              setState(() => _published = v);
              _flow.keep();
            },
          ),
        ),
      ],
      summary: (_) => FlowSummary(rows: [
        FlowSummaryRow(context.tr('Service'), _name.text.trim(), step: 'name', bold: true),
        if (_photo != null) FlowSummaryRow(context.tr('Photo'), context.tr('Oui'), step: 'photo'),
        FlowSummaryRow(context.tr('Prix'), _priceLine(), step: 'price'),
        if (_minutes != null)
          FlowSummaryRow(context.tr('Durée'), formatDuration(_minutes!), step: 'duration'),
        if (_description.text.trim().isNotEmpty)
          FlowSummaryRow(context.tr('Description'), _description.text.trim(), step: 'describe'),
        FlowSummaryRow(context.tr('Sur la vitrine'),
            _published ? context.tr('Oui') : context.tr('Non'),
            step: 'vitrine'),
      ]),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{name} ajouté', {'name': _savedName}),
        details: _photoWaits || _descriptionLost
            ? Text(
                [
                  if (_descriptionLost) context.tr('La description n\'a pas été enregistrée : modifiez l\'article pour l\'écrire à nouveau.'),
                  if (_photoWaits)
                    context.tr('Photo gardée, en attente de réseau. Une fois envoyée, liez-la à l\'article depuis Documents.'),
                ].join('\n'),
                textAlign: TextAlign.center)
            : null,
        actions: [
          FlowAction(
            key: const Key('service-another'),
            label: context.tr('Ajouter un autre service'),
            icon: Icons.add,
            primary: true,
            onPressed: () {
              setState(_reset);
              _flow.restart();
            },
          ),
        ],
      ),
    );
  }

  String _priceLine() {
    final price = _money.format(_priceValue ?? 0);
    final per = _unit.isEmpty ? '' : ' / $_unit';
    return _from
        ? context.tr('À partir de {price}', {'price': '$price$per'})
        : '$price$per';
  }

  Widget _photoStep(BuildContext context) {
    final theme = Theme.of(context);
    final photo = _photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: InkWell(
            key: const Key('service-flow-photo'),
            borderRadius: BorderRadius.circular(16),
            onTap: _pickPhoto,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 200,
                height: 200,
                color: theme.colorScheme.surfaceContainerHighest,
                child: photo != null
                    ? Image.memory(photo.bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))
                    : Icon(Icons.add_a_photo_outlined,
                        size: 56, color: theme.colorScheme.outline),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            key: const Key('service-flow-photo-pick'),
            onPressed: _pickPhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(photo == null
                ? context.tr('Prendre ou choisir une photo')
                : context.tr('Changer la photo')),
          ),
        ),
        if (photo != null)
          TextButton(
            onPressed: () => setState(() => _photo = null),
            child: Text(context.tr('Sans photo')),
          ),
        PhotoCounter(org: widget.org),
      ],
    );
  }

  Widget _priceStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowChoice<bool>(
          options: [
            FlowOption(false, context.tr('Un prix fixe'), icon: Icons.sell_outlined),
            FlowOption(true, context.tr('« À partir de »'),
                icon: Icons.trending_up,
                detail: context.tr('Le prix de départ : le client sait que cela peut coûter plus.')),
          ],
          value: _from,
          onChanged: (v) {
            setState(() => _from = v);
            _flow.keep();
          },
        ),
        const SizedBox(height: 8),
        FlowNumberField(
          key: const Key('service-flow-price'),
          controller: _price,
          autofocus: false,
          hint: '0',
          suffix: currencySymbol(widget.org.currency),
          currency: widget.org.currency,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text(context.tr('Par (facultatif)'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final u in _units)
              ChoiceChip(
                key: ValueKey('service-flow-unit-$u'),
                label: Text(context.tr(u), style: const TextStyle(fontSize: 16)),
                selected: _unit == u,
                onSelected: (on) {
                  setState(() => _unit = on ? u : '');
                  _flow.keep();
                },
              ),
          ],
        ),
      ],
    );
  }
}

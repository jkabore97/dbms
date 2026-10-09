import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/retail/retail_repository.dart';
import '../capture/capture_action.dart';
import '../common/step_flow.dart';
import '../retail/photo_quota.dart';

/// « Service », one entry at a time (115) — the shop's, the farm's and the
/// association's (098's « Mes services »): a photo (taken, chosen, or
/// « Choisir dans Photos », 114) → the name → the price, or « à partir
/// de » → how long it takes (optional) → on the vitrine or not → the
/// summary → « Enregistrer » → « C'est fait », « Ajouter un autre service ».
///
/// A service is a product row with `is_service` (098), written as the
/// sheet it replaces wrote it: ensure_product() as a service (the server
/// refuses a name an article holds), then its price, « à partir de »,
/// unit and vitrine. The duration has no column of its own: it opens the
/// service's description (« Durée : 1 h »), the words the vitrine already
/// shows under its name — the sheet's own hint told people to write it
/// there. Online, as the sheet was.
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
  final _otherDuration = TextEditingController();
  String _unit = '';
  bool _from = false;
  String? _duration;
  bool _published = true;
  PickedPhoto? _photo;
  String _savedName = '';
  bool _photoWaits = false;

  /// What a service is counted by, one tap each (as the sheet's).
  static const _units = ['heure', 'séance', 'personne', 'jour', 'mois'];

  /// How long, one tap each; « Autre » is typed.
  static const _durations = ['15 min', '30 min', '1 h', '2 h', 'une demi-journée', 'une journée'];

  NumberFormat get _money => moneyFormat(widget.org.currency);
  double? get _priceValue => FlowNumberField.read(_price);

  String? get _durationText {
    if (_duration == null) return null;
    if (_duration == 'other') {
      final t = _otherDuration.text.trim();
      return t.isEmpty ? null : t;
    }
    return _duration;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _otherDuration.dispose();
    super.dispose();
  }

  void _reset() {
    _name.clear();
    _price.clear();
    _otherDuration.clear();
    _unit = '';
    _from = false;
    _duration = null;
    _published = true;
    _photo = null;
  }

  Map<String, Object?> _save() => {
        'name': _name.text,
        'price': _price.text,
        'unit': _unit,
        'from': _from,
        'duration': _duration,
        'other': _otherDuration.text,
        'published': _published,
      };

  void _restore(Map<String, Object?> a) {
    setState(() {
      _reset();
      _name.text = '${a['name'] ?? ''}';
      _price.text = '${a['price'] ?? ''}';
      _unit = '${a['unit'] ?? ''}';
      _from = a['from'] == true;
      final d = a['duration'];
      _duration = d is String ? d : null;
      _otherDuration.text = '${a['other'] ?? ''}';
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
    final duration = _durationText;
    await widget.retail.updateProduct(
      id,
      name: name,
      salePrice: price,
      unit: _unit,
      isPublished: _published,
      // In the vitrine's language, as the durations offered are.
      description: duration == null ? null : 'Durée : $duration',
      isService: true,
      priceFrom: _from,
    );
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
          isValid: () => _duration != 'other' || _otherDuration.text.trim().isNotEmpty,
          builder: _durationStep,
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
        if (_durationText != null)
          FlowSummaryRow(context.tr('Durée'), _durationText!, step: 'duration'),
        FlowSummaryRow(context.tr('Sur la vitrine'),
            _published ? context.tr('Oui') : context.tr('Non'),
            step: 'vitrine'),
      ]),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{name} ajouté', {'name': _savedName}),
        details: _photoWaits
            ? Text(
                context.tr('Photo gardée, en attente de réseau. Une fois envoyée, liez-la à l\'article depuis Documents.'),
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
          suffix: widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency,
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

  Widget _durationStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in _durations)
              ChoiceChip(
                key: ValueKey('service-flow-duration-$d'),
                label: Text(context.tr(d), style: const TextStyle(fontSize: 16)),
                selected: _duration == d,
                onSelected: (on) {
                  setState(() => _duration = on ? d : null);
                  _flow.keep();
                },
              ),
            ChoiceChip(
              key: const ValueKey('service-flow-duration-other'),
              label: Text(context.tr('Autre'), style: const TextStyle(fontSize: 16)),
              selected: _duration == 'other',
              onSelected: (on) => setState(() => _duration = on ? 'other' : null),
            ),
          ],
        ),
        if (_duration == 'other') ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('service-flow-duration-text'),
            controller: _otherDuration,
            autofocus: true,
            maxLength: 40,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr('45 min, 3 séances…'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/auth/whatsapp_phone.dart';
import '../../core/courier/courier_dossier.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/phone/country_codes.dart';
import '../common/phone_field.dart';
import '../storefront/shop_skeleton.dart';
import '../storefront/shop_style.dart';
import '../storefront/whatsapp_verify_screen.dart';
import 'courier_words.dart';

/// A photo just taken: its bytes and type.
typedef CourierShot = ({Uint8List bytes, String type});

/// Takes one photo — the front camera for the selfie, the back one (or the
/// gallery) for a document. Null when the person changed their mind.
typedef CourierCamera = Future<CourierShot?> Function({required bool selfie, bool gallery});

/// « Devenir livreur » (112): the dossier, one question per screen, then
/// the wait, said with its history.
///
/// The server keeps the dossier (my_courier_application) — every « Suivant »
/// saves its step there — so it resumes on any phone, and decides which
/// steps may be filled: all of them on a draft, only the ones sent back
/// after a refusal (the rest is kept). The photos go to the uploads Worker
/// and are never read back here: the screen shows the picture just taken,
/// and afterwards only that it was sent.
class BecomeCourierScreen extends StatefulWidget {
  const BecomeCourierScreen({
    super.key,
    required this.dossier,
    required this.files,
    this.whatsApp,
    this.camera,
    this.pollEvery = const Duration(seconds: 30),
  });

  final CourierDossierRepository dossier;
  final CourierFiles files;

  /// F's WhatsApp proof (109); null hides « Vérifier sur WhatsApp ».
  final WhatsAppPhone? whatsApp;
  final CourierCamera? camera;

  /// While examined, the page asks again on its own (the courier page's
  /// lesson): an approval lands without a reload.
  final Duration pollEvery;

  @override
  State<BecomeCourierScreen> createState() => _BecomeCourierScreenState();
}

class _BecomeCourierScreenState extends State<BecomeCourierScreen> {
  CourierDossier? _d;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  String? _problem;

  /// null: the status or the intro; else the wizard, on [_at].
  List<String>? _flow;
  int _at = 0;

  // The answers being typed.
  final _city = TextEditingController();
  final _zone = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _colour = TextEditingController();
  final _plate = TextEditingController();
  final _phone = TextEditingController();
  final _payout = TextEditingController();
  CountryCode _country = defaultCountry;
  List<String> _zones = [];
  Set<String> _days = {};
  String _from = '08:00';
  String _to = '18:00';
  String? _vehicle;
  String? _idKind;
  bool _charter = false;

  /// The pictures taken on this phone, this visit — never fetched back.
  final _shots = <String, Uint8List>{};
  String? _sending;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // What is due goes first (30 days after a refusal, a replaced photo):
    // the applicant's own, deleted as they come back.
    unawaited(widget.files.purge());
    _load();
    _poll = Timer.periodic(widget.pollEvery, (_) {
      if (mounted && _flow == null && !_busy && _d?.status == 'pending') _load(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final c in [_city, _zone, _make, _model, _colour, _plate, _phone, _payout]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final d = await widget.dossier.mine();
      if (!mounted) return;
      setState(() {
        _d = d;
        _loading = false;
        if (!silent) _fill(d);
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  /// The form starts from what the server kept.
  void _fill(CourierDossier d) {
    _city.text = d.city ?? '';
    _zones = [...d.zones];
    _days = {...d.days};
    _from = d.hoursFrom ?? '08:00';
    _to = d.hoursTo ?? '18:00';
    _vehicle = d.vehicle;
    _make.text = d.vehicleMake ?? '';
    _model.text = d.vehicleModel ?? '';
    _colour.text = d.vehicleColour ?? '';
    _plate.text = d.vehiclePlate ?? '';
    _idKind = d.idKind;
    final phone = d.phone ?? d.verifiedPhone;
    if (phone != null) {
      _country = countryOfNumber(phone) ?? defaultCountry;
      _phone.text = phone.substring(_country.dial.length);
    }
    _payout.text = d.payoutNumber ?? '';
    _charter = d.charterVersion == d.rules.charterVersion;
  }

  /// The screens of the flow: every step on a draft, the reopened ones
  /// after a refusal; the vehicle's details only for a motor vehicle; the
  /// summary last.
  List<String> _screens(CourierDossier d) {
    final open = d.openSteps.toSet();
    return [
      for (final s in courierSteps)
        if (open.contains(s)) ...[s, if (s == 'vehicle' && motorVehicles.contains(_vehicle)) 'vehicle_details'],
      'summary',
    ];
  }

  void _start() {
    final d = _d!;
    setState(() {
      _flow = _screens(d);
      _problem = null;
      // A draft resumes on its first step not done yet.
      _at = 0;
      for (var i = 0; i < _flow!.length; i++) {
        final s = _flow![i];
        // The details screen is done when the vehicle step is (its plate).
        final done = s == 'vehicle_details' ? d.stepDone('vehicle') : d.stepDone(s);
        if (s == 'summary' || !done) {
          _at = i;
          break;
        }
      }
      if (d.status == 'refused') _at = 0;
    });
  }

  String get _screen => _flow![_at];

  // ---------------------------------------------------------------
  // Each screen's « Suivant »
  // ---------------------------------------------------------------

  bool get _ready => switch (_screen) {
        'zone' => _city.text.trim().isNotEmpty && _zones.isNotEmpty,
        'hours' => _days.isNotEmpty && _from.compareTo(_to) < 0,
        'vehicle' => _vehicle != null,
        'vehicle_details' => _make.text.trim().isNotEmpty &&
            _model.text.trim().isNotEmpty &&
            _colour.text.trim().isNotEmpty &&
            _plate.text.trim().length >= 2,
        'selfie' => _d!.hasFile('selfie') && _sending == null,
        'id' => _idKind != null &&
            _d!.hasFile('id_front') &&
            _d!.hasFile('id_back') &&
            (!licenceVehicles.contains(_vehicle ?? _d!.vehicle) ||
                !_d!.rules.licenceRequired ||
                _d!.hasFile('licence')) &&
            _sending == null,
        'phone' => _phoneNumber != null &&
            (!_d!.rules.phoneVerified || _phoneNumber == _d!.verifiedPhone),
        'charter' => _charter,
        _ => true,
      };

  String? get _phoneNumber {
    final typed = _phone.text.trim();
    if (typed.isEmpty || _country.lengthProblem(typed) != null) return null;
    return _country.toE164(typed);
  }

  Future<void> _next() async {
    if (!_ready || _busy) return;
    if (_screen == 'summary') return _send();
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final d = switch (_screen) {
        'zone' => await widget.dossier.save('zone', {'city': _city.text.trim(), 'zones': _zones}),
        'hours' => await widget.dossier.save('hours', {'days': [..._days], 'hours_from': _from, 'hours_to': _to}),
        // A motor vehicle is saved with its details, on the next screen.
        'vehicle' when motorVehicles.contains(_vehicle) => null,
        'vehicle' => await widget.dossier.save('vehicle', {'vehicle': _vehicle}),
        'vehicle_details' => await widget.dossier.save('vehicle', {
            'vehicle': _vehicle,
            'vehicle_make': _make.text.trim(),
            'vehicle_model': _model.text.trim(),
            'vehicle_colour': _colour.text.trim(),
            'vehicle_plate': _plate.text.trim(),
          }),
        'id' => await widget.dossier.save('id', {'id_kind': _idKind}),
        'phone' => await widget.dossier.save('phone', {
            'phone': _phoneNumber,
            if (_d!.rules.mobileMoney) 'payout_number': _payout.text.trim(),
          }),
        'charter' => await widget.dossier.save('charter', {'charter_version': _d!.rules.charterVersion}),
        _ => null,
      };
      if (!mounted) return;
      setState(() {
        if (d != null) _d = d;
        // The vehicle chosen decides whether its details come next.
        final at = _screen;
        _flow = _screens(_d!);
        _at = _flow!.indexOf(at) + 1;
      });
    } catch (e) {
      if (mounted) setState(() => _problem = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_at == 0) {
      setState(() => _flow = null);
      return;
    }
    setState(() {
      _at--;
      _problem = null;
    });
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final d = await widget.dossier.send();
      if (!mounted) return;
      setState(() {
        _d = d;
        _flow = null;
      });
    } catch (e) {
      if (mounted) setState(() => _problem = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------

  Future<CourierShot?> _defaultCamera({required bool selfie, bool gallery = false}) async {
    final file = await ImagePicker().pickImage(
      source: gallery ? ImageSource.gallery : ImageSource.camera,
      // A face and a card read well at 1600 px; a market's line carries it.
      maxWidth: 1600,
      imageQuality: 80,
      preferredCameraDevice: selfie ? CameraDevice.front : CameraDevice.rear,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final type = file.mimeType ??
        (name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
                ? 'image/webp'
                : name.endsWith('.heic')
                    ? 'image/heic'
                    : 'image/jpeg');
    return (bytes: bytes, type: type);
  }

  Future<void> _take(String part, {bool gallery = false}) async {
    if (_sending != null) return;
    CourierShot? shot;
    try {
      shot = await (widget.camera ?? _defaultCamera)(selfie: part == 'selfie', gallery: gallery);
    } catch (e) {
      if (mounted) {
        setState(() => _problem = context.tr('La caméra n\'est pas disponible : {error}', {'error': e}));
      }
      return;
    }
    if (shot == null || !mounted) return;
    setState(() {
      _sending = part;
      _problem = null;
      _shots[part] = shot!.bytes;
    });
    try {
      await widget.files.upload(part, shot.bytes, shot.type);
      final d = await widget.dossier.mine();
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) {
        setState(() {
          _shots.remove(part);
          _problem = e is CourierFileException ? context.tr(e.message) : describeError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _verify() async {
    final phone = widget.whatsApp;
    if (phone == null) return;
    final proved = await Navigator.of(context).push(WhatsAppVerifyScreen.route(phone));
    if (proved == null || !mounted) return;
    setState(() {
      _country = countryOfNumber(proved) ?? defaultCountry;
      _phone.text = proved.substring(_country.dial.length);
    });
    final d = await widget.dossier.mine().catchError((_) => _d!);
    if (mounted) setState(() => _d = d);
  }

  // ---------------------------------------------------------------
  // The page
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final inFlow = _flow != null && d != null;
    return ShopPage(
      title: context.tr('Devenir livreur'),
      leading: IconButton(
        tooltip: inFlow ? context.tr('Retour') : context.tr('Les vitrines'),
        icon: const Icon(Icons.arrow_back),
        onPressed: inFlow ? _back : () => context.go(Routes.directory),
      ),
      bottom: inFlow ? _bar(context) : null,
      body: _loading
          ? ShopSkeleton.list(rows: 3)
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))))
              : inFlow
                  ? _flowPage(context, d)
                  : _home(context, d!),
    );
  }

  /// No flow open: what the dossier is now.
  Widget _home(BuildContext context, CourierDossier d) {
    // Suspended first: an approved dossier does not undo a suspension.
    if (d.isSuspended) {
      return _Panel(
        icon: Icons.block_outlined,
        title: context.tr('Accès suspendu'),
        lines: [context.tr('Votre accès livreur est suspendu. Contactez la plateforme.')],
      );
    }
    if (d.isApprovedCourier) {
      return _Panel(
        icon: Icons.verified_outlined,
        title: context.tr('Vous êtes livreur'),
        lines: [context.tr('Les livraisons vous attendent dans l\'espace livreur.')],
        action: FilledButton(
          key: const Key('courier-open-space'),
          onPressed: () => context.go(Routes.courier),
          child: Text(context.tr('Ouvrir l\'espace livreur')),
        ),
        timeline: d.timeline,
      );
    }
    switch (d.status) {
      case 'pending':
        return _Panel(
          key: const Key('courier-pending'),
          icon: Icons.hourglass_top_outlined,
          title: context.tr('En cours d\'examen'),
          lines: [context.tr('Mara vérifie votre demande. Vous serez prévenu ici et par une notification.')],
          timeline: d.timeline,
          now: context.tr('En cours d\'examen'),
        );
      case 'refused':
        final r = d.refusal;
        return _Panel(
          key: const Key('courier-refused'),
          icon: Icons.edit_note,
          title: r?.isNewPhoto == true ? context.tr('Nouvelle photo demandée') : context.tr('À corriger'),
          lines: [
            courierReasonLabel(context, r?.reason),
            if ((r?.note ?? '').isNotEmpty) '« ${r!.note} »',
            context.tr('À refaire : {steps}. Le reste de votre demande est gardé.', {
              'steps': d.openSteps.map((s) => courierStepLabel(context, s)).join(', '),
            }),
          ],
          action: FilledButton(
            key: const Key('courier-fix'),
            onPressed: _start,
            child: Text(r?.isNewPhoto == true
                ? context.tr('Reprendre la photo')
                : context.tr('Corriger ma demande')),
          ),
          timeline: d.timeline,
        );
    }
    // No dossier yet, or a draft.
    return _Panel(
      key: const Key('courier-intro'),
      icon: Icons.delivery_dining_outlined,
      title: context.tr('Livrez pour les boutiques du quartier'),
      lines: [
        context.tr('Vous choisissez vos quartiers et vos heures. Mara valide chaque livreur avant sa première course.'),
        context.tr('Préparez votre pièce d\'identité et votre téléphone : cinq minutes suffisent.'),
        if (d.courierStatus == 'pending')
          context.tr('Votre inscription est à l\'étude. Un dossier complet aide la plateforme à la valider.'),
      ],
      action: FilledButton(
        key: const Key('courier-start'),
        onPressed: _start,
        child: Text(d.status == 'draft' ? context.tr('Continuer ma demande') : context.tr('Commencer')),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final last = _screen == 'summary';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            OutlinedButton(
              key: const Key('courier-back'),
              onPressed: _busy ? null : _back,
              child: Text(context.tr('Retour')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('courier-next'),
                onPressed: _ready && !_busy ? _next : null,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ShopStyle.paper))
                    : Text(last ? context.tr('Envoyer ma demande') : context.tr('Suivant')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flowPage(BuildContext context, CourierDossier d) {
    final total = _flow!.length;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ShopWidth(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  key: const Key('courier-progress'),
                  value: (_at + 1) / total,
                  minHeight: 6,
                  backgroundColor: ShopStyle.stone,
                ),
              ),
              const SizedBox(height: 8),
              Text(context.tr('Étape {n} sur {total}', {'n': _at + 1, 'total': total}),
                  style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
              const SizedBox(height: 18),
              ..._question(context, d),
              if (_problem != null) ...[
                const SizedBox(height: 14),
                Text(_problem!,
                    key: const Key('courier-problem'),
                    style: const TextStyle(fontSize: 14, color: Color(0xFFB3261E))),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _question(BuildContext context, CourierDossier d) {
    Widget title(String t) => Text(t,
        style: const TextStyle(fontSize: 24, height: 1.15, fontWeight: FontWeight.w700, color: ShopStyle.ink));
    Widget hint(String t) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t, style: const TextStyle(fontSize: 15, height: 1.35, color: ShopStyle.mist)),
        );
    const gap = SizedBox(height: 18);
    InputDecoration field(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());

    switch (_screen) {
      case 'zone':
        return [
          title(context.tr('Où livrez-vous ?')),
          hint(context.tr('Votre ville, puis les quartiers où vous voulez livrer.')),
          gap,
          TextField(
            key: const Key('courier-city'),
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: field(context.tr('Ville')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('courier-zone'),
                  controller: _zone,
                  textCapitalization: TextCapitalization.words,
                  decoration: field(context.tr('Un quartier')),
                  onSubmitted: (_) => _addZone(),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                key: const Key('courier-zone-add'),
                tooltip: context.tr('Ajouter'),
                onPressed: _addZone,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final z in _zones)
                InputChip(
                  label: Text(z),
                  onDeleted: () => setState(() => _zones.remove(z)),
                ),
            ],
          ),
        ];
      case 'hours':
        final times = [for (var h = 5; h <= 23; h++) for (final m in ['00', '30']) '${h.toString().padLeft(2, '0')}:$m'];
        return [
          title(context.tr('Quand êtes-vous disponible ?')),
          hint(context.tr('Les jours, puis les heures.')),
          gap,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final day in courierDays)
                FilterChip(
                  key: Key('courier-day-$day'),
                  label: Text(courierDayLabel(context, day)),
                  selectedColor: ShopStyle.ink,
                  checkmarkColor: ShopStyle.paper,
                  labelStyle: TextStyle(color: _days.contains(day) ? ShopStyle.paper : ShopStyle.ink),
                  selected: _days.contains(day),
                  onSelected: (on) => setState(() => on ? _days.add(day) : _days.remove(day)),
                ),
            ],
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('courier-from'),
                  initialValue: times.contains(_from) ? _from : '08:00',
                  decoration: field(context.tr('De')),
                  items: [for (final t in times) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => setState(() => _from = v ?? _from),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('courier-to'),
                  initialValue: times.contains(_to) ? _to : '18:00',
                  decoration: field(context.tr('À')),
                  items: [for (final t in times) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) => setState(() => _to = v ?? _to),
                ),
              ),
            ],
          ),
          if (_from.compareTo(_to) >= 0) hint(context.tr('L\'heure de fin vient après l\'heure de début')),
        ];
      case 'vehicle':
        return [
          title(context.tr('Comment livrez-vous ?')),
          gap,
          for (final v in ['moto', 'velo', 'voiture', 'tricycle', 'pied'])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Tile(
                key: Key('courier-vehicle-$v'),
                icon: courierVehicleIcon(v),
                label: courierVehicleLabel(context, v),
                selected: _vehicle == v,
                onTap: () => setState(() => _vehicle = v),
              ),
            ),
        ];
      case 'vehicle_details':
        return [
          title(context.tr('Votre {vehicle}', {'vehicle': courierVehicleLabel(context, _vehicle).toLowerCase()})),
          hint(context.tr('Pour que la boutique et le client vous reconnaissent.')),
          gap,
          TextField(
              key: const Key('courier-make'),
              controller: _make,
              decoration: field(context.tr('Marque')),
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          TextField(
              key: const Key('courier-model'),
              controller: _model,
              decoration: field(context.tr('Modèle')),
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          TextField(
              key: const Key('courier-colour'),
              controller: _colour,
              decoration: field(context.tr('Couleur')),
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          TextField(
              key: const Key('courier-plate'),
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: field(context.tr('Plaque d\'immatriculation')),
              onChanged: (_) => setState(() {})),
        ];
      case 'selfie':
        return [
          title(context.tr('Une photo de vous')),
          hint(context.tr('Avec la caméra de devant. Elle sert à vérifier que la pièce d\'identité est bien la vôtre.')),
          gap,
          _Guide(lines: [
            context.tr('Le visage en entier, bien éclairé'),
            context.tr('Sans lunettes de soleil ni casquette'),
            context.tr('Seul sur la photo'),
          ]),
          const SizedBox(height: 14),
          _PhotoSlot(
            key: const Key('courier-photo-selfie'),
            label: courierPartLabel(context, 'selfie'),
            icon: Icons.face_outlined,
            shot: _shots['selfie'],
            sent: d.hasFile('selfie'),
            sending: _sending == 'selfie',
            onTake: () => _take('selfie'),
          ),
        ];
      case 'id':
        final licence = licenceVehicles.contains(_vehicle ?? d.vehicle);
        return [
          title(context.tr('Votre pièce d\'identité')),
          hint(context.tr('Le recto et le verso, toute la pièce dans le cadre, lisible, sans reflet.')),
          gap,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in ['cnib', 'passeport', 'carte_consulaire'])
                ChoiceChip(
                  key: Key('courier-id-$k'),
                  label: Text(courierIdLabel(context, k)),
                  selectedColor: ShopStyle.ink,
                  checkmarkColor: ShopStyle.paper,
                  labelStyle: TextStyle(color: _idKind == k ? ShopStyle.paper : ShopStyle.ink),
                  selected: _idKind == k,
                  onSelected: (_) => setState(() => _idKind = k),
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (final part in ['id_front', 'id_back', if (licence) 'licence'])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PhotoSlot(
                key: Key('courier-photo-$part'),
                label: part == 'licence' && !d.rules.licenceRequired
                    ? context.tr('{part} (facultatif)', {'part': courierPartLabel(context, part)})
                    : courierPartLabel(context, part),
                icon: part == 'licence' ? Icons.badge_outlined : Icons.credit_card_outlined,
                shot: _shots[part],
                sent: d.hasFile(part),
                sending: _sending == part,
                onTake: () => _take(part),
                onGallery: () => _take(part, gallery: true),
              ),
            ),
          hint(context.tr('Ces photos restent privées : seule l\'équipe Mara les voit, et elles sont effacées 30 jours après un refus.')),
        ];
      case 'phone':
        final proved = d.verifiedPhone;
        return [
          title(context.tr('Votre numéro WhatsApp')),
          hint(context.tr('La boutique et le client vous joignent sur ce numéro.')),
          gap,
          if (proved != null && _phoneNumber == proved)
            Row(
              key: const Key('courier-phone-proved'),
              children: [
                const Icon(Icons.verified, color: Color(0xFF3F7A52)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('{phone} — vérifié sur WhatsApp', {'phone': proved}),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            )
          else ...[
            PhoneField(
              controller: _phone,
              country: _country,
              onCountry: (c) => setState(() => _country = c),
              labelText: context.tr('Numéro WhatsApp'),
              errorText: _phone.text.trim().isEmpty ? null : _country.lengthProblem(_phone.text),
              onChanged: (_) => setState(() {}),
            ),
            if (d.rules.phoneVerified)
              hint(context.tr('Mara demande un numéro vérifié : recevez le code sur WhatsApp.'))
            else
              hint(context.tr('Un numéro vérifié rassure la plateforme.')),
          ],
          if (widget.whatsApp != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('courier-verify'),
                onPressed: _verify,
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: Text(proved != null && _phoneNumber == proved
                    ? context.tr('Utiliser un autre numéro')
                    : context.tr('Vérifier sur WhatsApp')),
              ),
            ),
          ],
          gap,
          // RULE M: the payout number only while Mara takes mobile money.
          if (d.rules.mobileMoney)
            TextField(
              key: const Key('courier-payout'),
              controller: _payout,
              keyboardType: TextInputType.phone,
              decoration: field(context.tr('Numéro Mobile Money pour vos gains (facultatif)')),
            )
          else
            Text(context.tr('Vos courses vous sont payées en espèces, à la porte.'),
                key: const Key('courier-cash-line'),
                style: const TextStyle(fontSize: 14, color: ShopStyle.mist)),
        ];
      case 'charter':
        return [
          title(context.tr('La charte du livreur')),
          gap,
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: ShopStyle.stone, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in courierCharter(context))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(fontSize: 15)),
                        Expanded(child: Text(line, style: const TextStyle(fontSize: 15, height: 1.35))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('courier-charter'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _charter,
            onChanged: (v) => setState(() => _charter = v ?? false),
            title: Text(context.tr('J\'ai lu et j\'accepte la charte du livreur')),
          ),
        ];
      default:
        final open = d.openSteps.toSet();
        Widget row(String step, String value) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(d.stepDone(step) ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: d.stepDone(step) ? const Color(0xFF3F7A52) : ShopStyle.mist),
              title: Text(courierStepLabel(context, step),
                  style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
              subtitle: Text(value, style: const TextStyle(fontSize: 16, color: ShopStyle.ink)),
              trailing: open.contains(step)
                  ? TextButton(
                      onPressed: () => setState(() => _at = _flow!.indexOf(step)),
                      child: Text(context.tr('Modifier')),
                    )
                  : null,
            );
        return [
          title(context.tr('Tout est prêt ?')),
          hint(context.tr('Relisez, puis envoyez : Mara examine chaque demande.')),
          gap,
          row('zone', '${d.city ?? ''} · ${d.zones.join(', ')}'),
          row('hours', courierHoursLine(context, d)),
          row('vehicle', courierVehicleLine(context, d)),
          row('selfie', d.hasFile('selfie') ? context.tr('Envoyé') : '—'),
          row('id', [
            courierIdLabel(context, d.idKind),
            if (d.hasFile('id_front') && d.hasFile('id_back')) context.tr('recto et verso'),
            if (d.hasFile('licence')) context.tr('permis'),
          ].join(' · ')),
          row('phone', [
            d.phone ?? '—',
            if (d.phone != null && d.phone == d.verifiedPhone) context.tr('vérifié'),
          ].join(' · ')),
          row('charter', d.charterVersion == d.rules.charterVersion ? context.tr('Acceptée') : '—'),
        ];
    }
  }

  void _addZone() {
    final z = _zone.text.trim();
    if (z.isEmpty || _zones.contains(z) || _zones.length >= 12) return;
    setState(() {
      _zones.add(z);
      _zone.clear();
    });
  }
}

/// A screen with no question: an icon, a title, a few lines, one action,
/// and the history under it.
class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
    this.action,
    this.timeline = const [],
    this.now,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Widget? action;
  final List<CourierEvent> timeline;
  final String? now;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 40, color: ShopStyle.ink),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(
                        fontSize: 28, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: ShopStyle.ink)),
                for (final l in lines) ...[
                  const SizedBox(height: 10),
                  Text(l, style: const TextStyle(fontSize: 16, height: 1.4, color: ShopStyle.ink)),
                ],
                if (action != null) ...[const SizedBox(height: 22), action!],
              ],
            ),
          ),
        ),
        if (timeline.isNotEmpty || now != null)
          ShopWidth(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShopSectionLabel(context.tr('Votre demande')),
                const SizedBox(height: 14),
                CourierTimeline(events: timeline, now: now),
              ],
            ),
          ),
      ],
    );
  }
}

/// A big choice: an icon and a word.
class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? ShopStyle.ink : ShopStyle.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? ShopStyle.ink : ShopStyle.line, width: 1.4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 28, color: selected ? ShopStyle.paper : ShopStyle.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600, color: selected ? ShopStyle.paper : ShopStyle.ink)),
              ),
              if (selected) const Icon(Icons.check, color: ShopStyle.paper),
            ],
          ),
        ),
      ),
    );
  }
}

/// How to take the photo, in three short lines.
class _Guide extends StatelessWidget {
  const _Guide({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF3F7A52)),
                const SizedBox(width: 8),
                Expanded(child: Text(l, style: const TextStyle(fontSize: 15))),
              ],
            ),
          ),
      ],
    );
  }
}

/// One photo of the dossier: the picture just taken (this visit only), or
/// that one was sent; take it, or take it again.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    super.key,
    required this.label,
    required this.icon,
    required this.shot,
    required this.sent,
    required this.sending,
    required this.onTake,
    this.onGallery,
  });

  final String label;
  final IconData icon;
  final Uint8List? shot;
  final bool sent;
  final bool sending;
  final VoidCallback onTake;
  final VoidCallback? onGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: sent ? const Color(0xFF3F7A52) : ShopStyle.line, width: 1.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 84,
              height: 84,
              color: ShopStyle.stone,
              child: shot != null
                  ? Image.memory(shot!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(icon, size: 36, color: ShopStyle.mist))
                  : Icon(icon, size: 36, color: ShopStyle.mist),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (sent && !sending) ...[
                      const Icon(Icons.check_circle, size: 16, color: Color(0xFF3F7A52)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      sending
                          ? context.tr('Envoi…')
                          : sent
                              ? context.tr('Envoyée')
                              : context.tr('Pas encore prise'),
                      style: TextStyle(fontSize: 13, color: sent && !sending ? const Color(0xFF3F7A52) : ShopStyle.mist),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    sending
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        : TextButton.icon(
                            onPressed: onTake,
                            icon: const Icon(Icons.photo_camera_outlined, size: 18),
                            label: Text(sent ? context.tr('Reprendre') : context.tr('Prendre la photo')),
                          ),
                    if (onGallery != null && !sending)
                      IconButton(
                        tooltip: context.tr('Galerie'),
                        onPressed: onGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

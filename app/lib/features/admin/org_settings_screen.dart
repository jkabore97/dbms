import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/admin/admin_repository.dart';
import '../account/pro_sheet.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/rates/currency_rates.dart';
import '../../core/retail/retail_repository.dart';
import '../capture/capture_action.dart';
import '../retail/product_photo.dart';
import '../common/owned_controller.dart';
import '../home/business_frame.dart' show UnsavedInput;
import 'pin_preview.dart';
import 'spots_card.dart';
import 'vitrine_plus_card.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/errors.dart';
import '../../core/theme/mara_mark.dart';
import '../cauris/unlock_sheet.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// The business's own details.
///
/// Only two fields are editable, and the ones that are missing matter more
/// than the ones that are here:
///
///  * `slug` is a live subdomain. Changing it breaks every link anyone has.
///  * `profile` decides which home screen every member of the org opens on.
///    Changing it from a settings form would move a whole congregation to a
///    farm screen because somebody was curious.
///
/// Both are shown, read-only, so an admin can see what they are and quote them
/// when asking for a change.
class OrgSettingsScreen extends StatefulWidget {
  const OrgSettingsScreen({
    super.key,
    required this.admin,
    required this.orgId,
    this.onSaved,
    this.canSuspend = false,
    this.suspended = false,
    this.canSetPlan = false,
    this.plan = 'free',
    this.retail,
    this.capture,
    this.initialPart,
  });

  final AdminRepository admin;

  /// The rubrique to open at once ('articles', 'identite', 'vitrine',
  /// 'position'): where the vitrine guide's « Faire maintenant » lands.
  final String? initialPart;
  final String orgId;

  /// For the vitrine's Pro dressing (068): the articles to pin and the
  /// photographs to choose a cover from. Null in a build with no server.
  final RetailRepository? retail;
  final CaptureRepository? capture;

  /// Whether to show the platform's plan form (065). True only for a platform
  /// admin; the server refuses `set_org_plan` to anyone else regardless.
  final bool canSetPlan;

  /// The effective plan as the org list last reported ('free' or 'pro'):
  /// what every member reads on this screen, with no signal.
  final String plan;

  /// Lets whoever opened this refresh the org list — the name shown in the app
  /// bar and the picker comes from `my_orgs()`, not from this screen.
  final VoidCallback? onSaved;

  /// Whether to show the platform's freeze control (049). True only for a
  /// platform admin; the server refuses `set_org_suspended` to anyone else
  /// regardless of what the client draws.
  final bool canSuspend;

  /// Whether this business is currently frozen, as the org list last reported.
  final bool suspended;

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> {
  final _nameController = TextEditingController();
  final _waveController = TextEditingController();

  String _currency = 'XOF';
  List<CurrencyRate> _rates = const [];
  String _slug = '';
  String _profile = '';
  String? _theme;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  late bool _suspended = widget.suspended;
  bool _togglingSuspend = false;

  // The plan as the platform set it (065): raw plan, paid-until, note. The
  // effective plan shown to members is `widget.plan`, from the org list.
  String _planRaw = 'free';
  DateTime? _planUntil;
  final _planNoteController = TextEditingController();
  bool _savingPlan = false;
  String? _planMessage;

  bool _storefrontEnabled = false;
  final _blurbController = TextEditingController();

  /// The phone and address a shopper reads (and the invoice header): two
  /// of the vitrine's six steps, set here since the first setup.
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String _savedPhone = '';
  String _savedAddress = '';

  /// What the vitrine has and lacks (070): each rubrique's « fait » or
  /// « à faire », and the articles count. Null with no server.
  VitrineChecklist? _checklist;

  /// Where the shop is on the vitrine map (053). Text, not doubles, so the
  /// field can be typed into, pasted from a Google Maps link, or filled from
  /// the phone's own position — and cleared to lift the pin.
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  // The shop's own delivery rates (061); empty means the platform's.
  final _deliveryBaseController = TextEditingController();
  final _deliveryPerKmController = TextEditingController();
  // How far the shop delivers (069); empty means the platform's 15 km.
  final _deliveryReachController = TextEditingController();

  /// « Minimum, puis au km » (081): the base covers the first
  /// [_deliveryIncludedController] km. Off: « Prix au km » from the door.
  bool _deliveryMinimum = false;
  final _deliveryIncludedController = TextEditingController();
  bool _locating = false;

  /// The pin as typed, when both fields read as a position on the planet.
  (double, double)? get _pin {
    final lat = double.tryParse(
      _latController.text.trim().replaceAll(',', '.'),
    );
    final lng = double.tryParse(
      _lngController.text.trim().replaceAll(',', '.'),
    );
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return (lat, lng);
  }

  /// The vitrine's address, on marakaj.com. What the shop pastes into a
  /// WhatsApp status.
  String get _storefrontUrl => publicShopUrl(_slug);

  static const _currencies = ['XOF', 'XAF', 'EUR', 'USD', 'GHS', 'NGN'];

  @override
  void initState() {
    super.initState();
    _open = _Part.byKey(widget.initialPart);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLockRule();
      _loadShopWave();
      _loadLogo();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _waveController.dispose();
    _blurbController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _deliveryBaseController.dispose();
    _deliveryPerKmController.dispose();
    _deliveryReachController.dispose();
    _deliveryIncludedController.dispose();
    _planNoteController.dispose();
    _payoutController.dispose();
    _merchantRefController.dispose();
    super.dispose();
  }

  static String _plain(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.round().toString() : '$v');

  /// What each field said when it was last read or saved, to tell an edit
  /// not saved yet (A4: the bar asks before leaving it).
  final Map<TextEditingController, String> _baseline = {};
  String? _baselineChoices;

  List<TextEditingController> get _savedTogether => [
        _nameController, _waveController, _planNoteController, _blurbController,
        _phoneController, _addressController, _latController, _lngController,
        _deliveryBaseController, _deliveryPerKmController, _deliveryReachController,
        _deliveryIncludedController,
      ];

  String get _choices => '$_currency|$_deliveryMinimum';

  void _markSaved(Iterable<TextEditingController> fields, {bool choices = false}) {
    for (final c in fields) {
      _baseline[c] = c.text;
    }
    if (choices) _baselineChoices = _choices;
  }

  bool _unsavedEdits() =>
      !_loading &&
      !_saving &&
      (_baseline.entries.any((e) => e.key.text != e.value) ||
          (_baselineChoices != null && _baselineChoices != _choices));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final org = await widget.admin.fetchOrg(widget.orgId);
      final wave = await widget.admin.waveMerchant(widget.orgId);
      final rates = await widget.admin.currencyRates(widget.orgId);
      final storefront = await widget.admin.storefront(widget.orgId);
      // The reach is one optional field: failing to read it must not cost
      // the owner the rest of the settings.
      double? reach;
      try {
        reach = await widget.admin.deliveryReach(widget.orgId);
      } catch (_) {
        reach = null;
      }
      final included = await widget.admin.deliveryIncludedKm(widget.orgId);
      // The contact lines and the checklist are extras: failing to read
      // them must not cost the owner the rest of the settings.
      ({String? phone, String? address}) contact = (phone: null, address: null);
      try {
        contact = await widget.admin.orgContact(widget.orgId);
      } catch (_) {}
      VitrineChecklist? checklist;
      try {
        checklist = await widget.admin.vitrineChecklist(widget.orgId);
      } catch (_) {}
      // Only the platform edits the plan, so only the platform pays for the
      // read; members show what the org list already says.
      final plan = widget.canSetPlan
          ? await widget.admin.orgPlan(widget.orgId)
          : (plan: widget.plan, until: null, note: null);
      if (!mounted) return;
      setState(() {
        _planRaw = plan.plan;
        _planUntil = plan.until;
        _planNoteController.text = plan.note ?? '';
        _nameController.text = (org['name'] as String?) ?? '';
        _waveController.text = wave ?? '';
        _rates = rates;
        final currency = (org['default_currency'] as String?) ?? 'XOF';
        _currency = _currencies.contains(currency) ? currency : 'XOF';
        _slug = (org['slug'] as String?) ?? '';
        _profile = (org['profile'] as String?) ?? 'generic';
        _theme = org['theme'] as String?;
        _storefrontEnabled = storefront.enabled;
        _blurbController.text = storefront.blurb ?? '';
        _savedPhone = contact.phone ?? '';
        _savedAddress = contact.address ?? '';
        _phoneController.text = _savedPhone;
        _addressController.text = _savedAddress;
        _checklist = checklist;
        _latController.text = storefront.lat?.toString() ?? '';
        _lngController.text = storefront.lng?.toString() ?? '';
        _deliveryBaseController.text = _plain(storefront.deliveryBase);
        _deliveryPerKmController.text = _plain(storefront.deliveryPerKm);
        _deliveryReachController.text = _plain(reach);
        _deliveryMinimum = (included ?? 0) > 0;
        _deliveryIncludedController.text =
            (included ?? 0) > 0 ? _plain(included) : '';
        _loading = false;
        _markSaved(_savedTogether, choices: true);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.tr('Le nom de l\'activité ne peut pas être vide.'));
      return;
    }

    // The pin is both numbers or neither — half a position is no position,
    // and the database refuses it too (053).
    final latText = _latController.text.trim().replaceAll(',', '.');
    final lngText = _lngController.text.trim().replaceAll(',', '.');
    double? lat;
    double? lng;
    if (latText.isNotEmpty || lngText.isNotEmpty) {
      lat = double.tryParse(latText);
      lng = double.tryParse(lngText);
      if (lat == null ||
          lng == null ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        setState(
          () => _error =
              context.tr('Indiquez la latitude et la longitude, ou aucune des deux.'),
        );
        return;
      }
    }

    // The delivery rates are both or neither, never negative — the
    // database refuses the same (061).
    final baseText = _deliveryBaseController.text.trim().replaceAll(',', '.');
    final perKmText = _deliveryPerKmController.text.trim().replaceAll(',', '.');
    double? deliveryBase;
    double? deliveryPerKm;
    if (baseText.isNotEmpty || perKmText.isNotEmpty) {
      deliveryBase = double.tryParse(baseText);
      deliveryPerKm = double.tryParse(perKmText);
      if (deliveryBase == null ||
          deliveryPerKm == null ||
          deliveryBase < 0 ||
          deliveryPerKm < 0) {
        setState(
          () => _error =
              context.tr('Indiquez la base et le prix par km de livraison, ou aucun des deux pour garder ceux de la plateforme.'),
        );
        return;
      }
    }

    // The kilometres the base covers (081): 0.5 to 50 in « minimum » mode.
    double? deliveryIncluded;
    if (_deliveryMinimum) {
      deliveryIncluded = double.tryParse(
          _deliveryIncludedController.text.trim().replaceAll(',', '.'));
      if (deliveryIncluded == null ||
          deliveryIncluded <= 0 ||
          deliveryIncluded > 50) {
        setState(() => _error =
            context.tr('Indiquez jusqu\'à combien de kilomètres le minimum s\'applique (de 0,5 à 50 km).'));
        return;
      }
    }

    // The reach: empty for the platform's, else 1 to 200 km (069).
    final reachText = _deliveryReachController.text.trim().replaceAll(',', '.');
    double? deliveryReach;
    if (reachText.isNotEmpty) {
      deliveryReach = double.tryParse(reachText);
      if (deliveryReach == null || deliveryReach <= 0 || deliveryReach > 200) {
        setState(
          () => _error =
              context.tr('La distance de livraison va de 1 à 200 km, ou vide pour celle de la plateforme (15 km).'),
        );
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.admin.updateOrg(
        orgId: widget.orgId,
        name: name,
        currency: _currency,
      );
      // The Wave handle is the owner's (103): an admin's save leaves it.
      if (_ownerOrPlatform) {
        final wave = _waveController.text.trim();
        await widget.admin.setWaveMerchant(
          widget.orgId,
          wave.isEmpty ? null : wave,
        );
      }
      await widget.admin.setStorefront(
        widget.orgId,
        enabled: _storefrontEnabled,
        blurb: _blurbController.text.trim(),
      );
      final phone = _phoneController.text.trim();
      final address = _addressController.text.trim();
      if (phone != _savedPhone || address != _savedAddress) {
        await widget.admin
            .setOrgContact(widget.orgId, phone: phone, address: address);
        _savedPhone = phone;
        _savedAddress = address;
      }
      await widget.admin.setStorefrontLocation(
        widget.orgId,
        lat: lat,
        lng: lng,
      );
      // « Livraison » hidden (110): its numbers are not sent — the server
      // keeps them as they are.
      if (!_hidden('delivery')) {
      await widget.admin.setDeliveryRates(
        widget.orgId,
        base: deliveryBase,
        perKm: deliveryPerKm,
      );
      try {
        await widget.admin.setDeliveryIncludedKm(
            widget.orgId, _deliveryMinimum ? deliveryIncluded : 0);
      } on PostgrestException catch (e) {
        // A database before 081 has no included kilometres; the rest is saved.
        if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      }
      try {
        await widget.admin.setDeliveryReach(widget.orgId, deliveryReach);
      } on PostgrestException catch (e) {
        // A database before 069 has no reach to set; the rest is saved.
        if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      }
      }
      widget.onSaved?.call();
      await _reloadChecklist();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = _open;
        _markSaved(_savedTogether, choices: true);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _saving = false;
      });
    }
  }

  /// The checklist again, after a save or a visit to the articles: each
  /// rubrique's state follows at once.
  Future<void> _reloadChecklist() async {
    try {
      final c = await widget.admin.vitrineChecklist(widget.orgId);
      if (mounted) setState(() => _checklist = c);
    } catch (_) {}
  }

  /// Add a currency, or (with [existing]) change its rate. Each is one
  /// immediate write and a reload, so the list always agrees with the server.
  Future<void> _editRate([CurrencyRate? existing]) async {
    final result = await showDialog<(String, double)>(
      context: context,
      builder: (_) => RateDialog(
        homeCurrency: _currency,
        taken: [for (final r in _rates) r.currency],
        existing: existing,
      ),
    );
    if (result == null) return;
    try {
      await widget.admin.setCurrencyRate(widget.orgId, result.$1, result.$2);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(error))),
        );
      }
    }
  }

  Future<void> _removeRate(CurrencyRate rate) async {
    try {
      await widget.admin.removeCurrencyRate(widget.orgId, rate.currency);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(error))),
        );
      }
    }
  }

  /// Put the business on a plan (065). Platform only; the server checks too.
  /// The org list is refreshed afterwards so the Formule row every member
  /// reads — and the cached copy — says the new plan at once.
  Future<void> _savePlan() async {
    if (_planRaw == 'pro' && _planUntil == null) {
      // A Pro with no end is allowed (a partner, a test), but it should be a
      // decision, not a forgotten field — so it is asked, not assumed.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          // The keyboard up on a small phone: the dialog scrolls (A6).
          scrollable: true,
          title: Text(context.tr('Mara Pro sans date de fin ?')),
          content: Text(
            context.tr('Sans date, cette entreprise reste Pro jusqu\'à ce que vous changiez sa formule à la main. Pour un paiement, indiquez plutôt la date de fin.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('Annuler')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.tr('Sans date de fin')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _savingPlan = true;
      _planMessage = null;
    });
    try {
      await widget.admin.setOrgPlan(
        widget.orgId,
        plan: _planRaw,
        until: _planRaw == 'pro' ? _planUntil : null,
        note: _planNoteController.text,
      );
      widget.onSaved?.call();
      if (!mounted) return;
      setState(() {
        if (_planRaw == 'free') _planUntil = null;
        _savingPlan = false;
        _markSaved([_planNoteController]);
        _planMessage = _planRaw == 'pro'
            ? context.tr('Entreprise passée sur Mara Pro.')
            : context.tr('Entreprise repassée sur Mara (gratuit).');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingPlan = false;
        _planMessage = AuthRepository.describeError(error);
      });
    }
  }

  Future<void> _pickPlanUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _planUntil ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
      helpText: 'Payé jusqu\'au',
    );
    if (picked != null && mounted) setState(() => _planUntil = picked);
  }

  /// Freeze the business, or thaw it. Suspending is guarded by a confirmation
  /// because it stops a real shop trading; lifting it is not. Either way the
  /// org list is refreshed so the read-only banner appears or clears at once.
  Future<void> _toggleSuspend() async {
    final freezing = !_suspended;
    if (freezing) {
      // Closed with its own context: the page's is the business's
      // navigator (108), under the dialog.
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          // The keyboard up on a small phone: the dialog scrolls (A6).
          scrollable: true,
          title: Text(context.tr('Suspendre cette entreprise ?')),
          content: Text(
            context.tr('Ses membres pourront encore tout consulter, mais ne pourront plus rien enregistrer — ni vente, ni dépense, ni stock — jusqu\'à la réactivation. Les données ne sont pas supprimées.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(context.tr('Annuler')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(context.tr('Suspendre')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _togglingSuspend = true;
      _error = null;
    });
    try {
      await widget.admin.setOrgSuspended(widget.orgId, freezing);
      // The banner in the shell reads `org.suspended`, which comes from the
      // cached org list — refresh it so the freeze takes visible effect now.
      widget.onSaved?.call();
      if (!mounted) return;
      setState(() {
        _suspended = freezing;
        _togglingSuspend = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            freezing ? context.tr('Entreprise suspendue') : context.tr('Entreprise réactivée'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _togglingSuspend = false;
      });
    }
  }

  /// Fill the pin from where the phone is right now — the shopkeeper is
  /// standing in the shop, which is the one place the position is certain.
  /// Nothing is saved until "Enregistrer": the numbers can still be edited.
  Future<void> _useMyPosition() async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Sans autorisation, tapez la position ou collez un lien Google Maps.'),
            ),
          ),
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latController.text = position.latitude.toStringAsFixed(6);
        _lngController.text = position.longitude.toStringAsFixed(6);
      });
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Position introuvable. Vérifiez que le GPS est activé.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// A shop already on Google Maps pastes its own link; the numbers come
  /// out of it. Short links carry none, and the dialog says what to do then.
  Future<void> _pasteMapsLink() async {
    // The dialog owns its field (OwnedController): disposed after the
    // dialog has left the screen, not while it animates out.
    final text = await showDialog<String>(
      context: context,
      builder: (context) => OwnedController(
        builder: (context, controller) => AlertDialog(
          // The keyboard up on a small phone: the dialog scrolls (A6).
          scrollable: true,
          title: Text(context.tr('Lien Google Maps')),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: context.tr('https://www.google.com/maps/place/...@12.37,-1.52,17z'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('Annuler')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(context.tr('Utiliser')),
            ),
          ],
        ),
      ),
    );
    if (text == null || !mounted) return;
    final position = parseGoogleMapsLink(text);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Ce lien ne contient pas de position. Ouvrez-le dans Google Maps et copiez l\'adresse complète.'),
          ),
        ),
      );
      return;
    }
    setState(() {
      _latController.text = position.lat.toString();
      _lngController.text = position.lng.toString();
    });
  }

  Future<void> _openColours() async {
    await context.push(
      Routes.inside(widget.orgId, 'administration/parametres/couleurs'),
    );
    // Re-read rather than trusting what was passed back: the colour screen
    // saves on its own, and this row has to agree with the server whether it
    // saved once, three times, or not at all.
    if (mounted) await _load();
  }

  /// The parts of the settings (the audit: one scroll of everything). Each
  /// opens on its own page; the fields live in this one State, so moving
  /// between parts loses nothing typed.
  _Part? _open;

  /// The part just saved: its page then offers the next one, so a new
  /// owner walks the settings in order instead of hunting the index.
  _Part? _saved;

  /// The order a new business is walked through: the articles first —
  /// a vitrine is its shelf — then the name, the window, the pin.
  static const _flow = [_Part.articles, _Part.identity, _Part.vitrine, _Part.position];

  _Part? get _next {
    final i = _flow.indexOf(_saved ?? _Part.articles);
    return i >= 0 && i + 1 < _flow.length ? _flow[i + 1] : null;
  }

  /// The team's lock rule (075): the code after at most this many minutes
  /// on every member's phone. Null: no rule.
  int? _lockRule;
  bool _savingLock = false;

  // Kaj's Wave checkout (076): the number the shop's sales are sent to, and
  // the merchant id Wave gave the shop (the platform's to set).
  final _payoutController = TextEditingController();

  /// Mara's tick (090): Wave is drawn only once a platform admin allows it.
  late bool _waveAllowed = AppScope.read(context)
          ?.session
          .featuresFor(widget.orgId)
          ?.waveAllowed ??
      false;
  bool _savingWave = false;

  Future<void> _setWaveAllowed(bool v) async {
    setState(() => _savingWave = true);
    try {
      await widget.admin.setOrgWaveAllowed(widget.orgId, v);
      if (mounted) setState(() => _waveAllowed = v);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _savingWave = false);
    }
  }
  final _merchantRefController = TextEditingController();
  bool _savingPayout = false;

  Future<void> _loadShopWave() async {
    final pay = AppScope.read(context)?.wavePay;
    if (pay == null) return;
    final w = await pay.shopWave(widget.orgId);
    if (!mounted) return;
    setState(() {
      _payoutController.text = w.number ?? '';
      _merchantRefController.text = w.merchantRef ?? '';
      _markSaved([_payoutController, _merchantRefController]);
    });
  }

  Future<void> _savePayout({bool merchant = false}) async {
    final pay = AppScope.read(context)?.wavePay;
    if (pay == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingPayout = true);
    try {
      if (merchant) {
        await pay.setMerchantRef(widget.orgId, _merchantRefController.text);
      } else {
        await pay.setPayoutNumber(widget.orgId, _payoutController.text);
      }
      await _loadShopWave();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(context.tr('Enregistré'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _savingPayout = false);
    }
  }

  /// Where the money is paid and the Wave handle are the owner's (and the
  /// platform's) since 103: an admin reads « Réservé au propriétaire » and
  /// the server refuses a change from them all the same. With no session
  /// (a build with no server) the server is left to decide.
  bool get _ownerOrPlatform {
    final session = AppScope.maybeOf(context)?.session;
    if (session == null) return true;
    return session.isPlatformAdmin ||
        (session.orgById(widget.orgId)?.roles.contains('owner') ?? false);
  }

  List<Widget> _waveReceive(ThemeData theme) => !_ownerOrPlatform
      ? [
          const SizedBox(height: 24),
          Text(context.tr('Recevoir les paiements des clients'),
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Row(
            key: const Key('payout-owner-only'),
            children: [
              const Icon(Icons.lock_outline, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(context.tr('Réservé au propriétaire'))),
            ],
          ),
        ]
      : [
        const SizedBox(height: 24),
        Text(context.tr('Recevoir les paiements des clients'),
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
            context.tr('Quand un client paie sa commande par Wave ou par carte dans Mara, l\'argent est envoyé sur ce numéro Wave quelques instants après. Un numéro Wave ordinaire suffit.'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _payoutController,
                enabled: !_savingPayout,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: context.tr('Numéro Wave'),
                  hintText: '+226 70 00 00 00',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _savingPayout ? null : () => _savePayout(),
              child: Text(context.tr('Enregistrer')),
            ),
          ],
        ),
      ];

  Future<void> _loadLockRule() async {
    try {
      final rule = await AppScope.read(context)
          ?.securityApi
          ?.orgLockPolicy(widget.orgId);
      if (mounted) setState(() => _lockRule = rule);
    } catch (_) {}
  }

  Future<void> _saveLockRule(int? minutes) async {
    final api = AppScope.read(context)?.securityApi;
    if (api == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingLock = true);
    try {
      await api.setOrgLockPolicy(widget.orgId, minutes);
      if (!mounted) return;
      setState(() => _lockRule = minutes);
      messenger.showSnackBar(SnackBar(
          content: Text(minutes == null
              ? context.tr('Règle retirée : chacun choisit son délai.')
              : context.tr('Code exigé après {minutes} min sur les téléphones de l\'équipe.', {'minutes': minutes}))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _savingLock = false);
    }
  }

  List<Widget> _team(ThemeData theme) {
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return [
      Text(context.tr('Verrouillage des téléphones'), style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
          context.tr('Chaque membre a un code sur son téléphone. Fixez le délai maximal après lequel Mara le redemande : personne de l\'équipe ne pourra choisir plus long, ni « Jamais ».'),
          style: muted),
      const SizedBox(height: 12),
      DropdownButtonFormField<int?>(
        initialValue: _lockRule,
        isExpanded: true,
        decoration: InputDecoration(
            border: const OutlineInputBorder(), labelText: context.tr('Délai maximal')),
        items: [
          DropdownMenuItem(value: null, child: Text(context.tr('Aucune règle'))),
          DropdownMenuItem(value: 1, child: Text(context.tr('1 min'))),
          DropdownMenuItem(value: 5, child: Text(context.tr('5 min (conseillé)'))),
          DropdownMenuItem(value: 15, child: Text(context.tr('15 min'))),
          const DropdownMenuItem(value: 60, child: Text('1 h')),
        ],
        onChanged: _savingLock ? null : _saveLockRule,
      ),
      const SizedBox(height: 24),
      Text(context.tr('Un téléphone perdu ou volé'), style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
          context.tr('Ouvrez Équipe et accès, puis la personne, puis « Déconnecter partout » : tous ses appareils devront se reconnecter avec le mot de passe.'),
          style: muted),
    ];
  }

  /// A Pro tool this business has neither on its plan nor unlocked with
  /// cauris (085): drawn locked, under the Pro seal, never as a form.
  /// A vitrine feature Mara's switchboard hid for this business (110): its
  /// part, card or field is not drawn here.
  bool _hidden(String feature) =>
      AppScope.maybeOf(context)?.session.accessFor(widget.orgId).isHidden(feature) ??
      false;

  bool _toolLocked(String feature) {
    if (widget.plan == 'pro') return false;
    final f = AppScope.maybeOf(context)?.session.featuresFor(widget.orgId);
    if (f == null) return true;
    return !f.isPro && f.toolOf(feature)?.until == null;
  }

  int? _costOf(String feature) => AppScope.maybeOf(context)
      ?.session
      .featuresFor(widget.orgId)
      ?.toolOf(feature)
      ?.cost;

  /// The locked page of a Pro tool: its picture under the seal, one line,
  /// and the way to open it (cauris or Mara Pro).
  List<Widget> _proLock(ThemeData theme, String feature, IconData icon,
          String title, String line) =>
      [
        Container(
          key: Key('pro-lock-$feature'),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const Positioned(right: -10, bottom: -10, child: MaraMark(size: 38)),
                ],
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ProCostBadge(cost: _costOf(feature)),
              const SizedBox(height: 10),
              Text(line, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: Key('pro-lock-open-$feature'),
                onPressed: () => _openPro(feature),
                icon: const Icon(Icons.lock_open),
                label: Text(context.tr('Débloquer')),
              ),
            ],
          ),
        ),
      ];

  /// The door to Mara Pro, from a Pro tool on this page — delivery, the
  /// one it guards (081) — with its price in cauris (085).
  void _openPro([String feature = 'delivery']) {
    final scope = AppScope.maybeOf(context);
    final org = scope?.session.orgById(widget.orgId);
    if (scope == null || org == null) return;
    ProSheet.open(
      context,
      org: org,
      terms: scope.session.planTerms,
      admin: widget.admin,
      canRequest: org.isAdmin,
      feature: feature,
    );
  }

  // ----------------------------------------------------------------
  // The shop's logo (080)
  // ----------------------------------------------------------------

  /// The r2 key of the logo, or null.
  String? _logoKey;
  bool _logoBusy = false;

  Future<void> _loadLogo() async {
    final key = await widget.admin.orgLogoKey(widget.orgId);
    if (mounted) setState(() => _logoKey = key);
  }

  /// Take or choose the picture, send it as one of the business's own
  /// photographs, and hang it as the logo — saved at once, as an article's
  /// photo is, not with the page's Enregistrer.
  Future<void> _changeLogo() async {
    final capture = widget.capture;
    if (capture == null) return;
    final picked = await CaptureAction.pick(context);
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _logoBusy = true);
    try {
      final id = await capture.capture(
        orgId: widget.orgId,
        bytes: picked.bytes,
        contentType: picked.contentType,
        kind: 'logo',
        caption: 'Logo',
      );
      if (id == null) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: Text(context.tr('Logo gardé, en attente de réseau. Réessayez une fois connecté pour le mettre sur la vitrine.')),
        ));
        return;
      }
      final docs = await capture.documents(widget.orgId, kind: 'logo', limit: 10);
      final key = docs.where((d) => d.id == id).map((d) => d.key).firstOrNull;
      if (key == null) throw StateError("Le logo envoyé n'a pas été retrouvé.");
      await widget.admin.setOrgLogo(widget.orgId, key);
      if (!mounted) return;
      setState(() => _logoKey = key);
      messenger.showSnackBar(
          SnackBar(content: Text(context.tr('Logo enregistré : il est sur la vitrine.'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _removeLogo() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _logoBusy = true);
    try {
      await widget.admin.setOrgLogo(widget.orgId, null);
      if (mounted) setState(() => _logoKey = null);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  List<Widget> _logoRow(ThemeData theme) {
    final capture = widget.capture;
    final canUpload = capture != null && capture.isConfigured;
    return [
      Text(context.tr('Logo'), style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      Row(
        children: [
          Container(
            key: const Key('org-logo-preview'),
            width: 72,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: _logoKey == null
                ? Icon(Icons.add_photo_alternate_outlined,
                    color: theme.colorScheme.onSurfaceVariant)
                : ProductPhoto(
                    name: _nameController.text,
                    photoKey: _logoKey,
                    capture: capture,
                    fit: BoxFit.contain,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  key: const Key('org-logo-change'),
                  onPressed: !canUpload || _logoBusy ? null : _changeLogo,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(_logoKey == null ? context.tr('Ajouter un logo') : context.tr('Changer')),
                ),
                if (_logoKey != null)
                  TextButton(
                    onPressed: _logoBusy ? null : _removeLogo,
                    child: Text(context.tr('Retirer')),
                  ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        canUpload
            ? context.tr('Affiché à côté du nom sur votre vitrine. Une image carrée, sur fond clair, se lit le mieux.')
            : context.tr('L\'envoi de photos n\'est pas disponible sur cette installation.'),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _identity(ThemeData theme) => [
    ..._logoRow(theme),
    Text(context.tr('Nom'), style: theme.textTheme.labelLarge),
    const SizedBox(height: 8),
    TextField(
      controller: _nameController,
      enabled: !_saving,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(border: OutlineInputBorder()),
    ),
    const SizedBox(height: 24),
    Text(context.tr('Monnaie'), style: theme.textTheme.labelLarge),
    const SizedBox(height: 8),
    DropdownButtonFormField<String>(
      initialValue: _currency,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: [
        for (final c in _currencies) DropdownMenuItem(value: c, child: Text(c)),
      ],
      onChanged: _saving ? null : (v) => setState(() => _currency = v!),
    ),
    const SizedBox(height: 24),
    Text(context.tr('Couleurs'), style: theme.textTheme.labelLarge),
    const SizedBox(height: 8),
    _ColourRow(
      palette: paletteFor(_profile, theme: _theme),
      label: paletteNamed(_theme)?.label ?? context.tr('Couleur par défaut'),
      onTap: _saving ? null : _openColours,
    ),
    const SizedBox(height: 32),
    Text(context.tr('Non modifiable ici'), style: theme.textTheme.titleSmall),
    const SizedBox(height: 4),
    Text(
      context.tr('L\'adresse web et le type d\'activité changent ce que voient tous les membres. Contactez Kaj-consulting pour les modifier.'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 12),
    _ReadOnlyRow(label: context.tr('Adresse web'), value: 'marakaj.com/s/$_slug'),
    _ReadOnlyRow(
      label: context.tr('Type d\'activité'),
      value: switch (_profile) {
        'retail' => 'Boutique',
        'farm' => 'Ferme',
        'association' || 'church' => 'Association',
        _ => _profile,
      },
    ),
    // Which plan this business is on (065). Every member reads
    // it; only the platform changes it, below. Since 066 the
    // Pro tools are badged and held on a Free business.
    _ReadOnlyRow(
      label: context.tr('Formule'),
      value: widget.plan == 'pro' ? context.tr('Mara Pro') : context.tr('Mara (gratuit)'),
    ),
  ];

  List<Widget> _payments(ThemeData theme) => [
    if (!_waveAllowed) ...[
      Row(children: [
        const Icon(Icons.payments_outlined, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(context.tr('Espèces pour le moment'),
              key: const Key('cash-only'),
              style: theme.textTheme.titleSmall),
        ),
      ]),
      const SizedBox(height: 24),
    ] else ...[
    Text(context.tr('Paiement Wave'), style: theme.textTheme.labelLarge),
    const SizedBox(height: 8),
    TextField(
      key: const Key('wave-handle'),
      controller: _waveController,
      enabled: !_saving && _ownerOrPlatform,
      readOnly: !_ownerOrPlatform,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: '+226 70 00 00 00',
        prefixIcon: const Icon(Icons.qr_code_2),
        helperText: _ownerOrPlatform
            ? context.tr('Le numéro Wave du commerce. Laissez vide pour ne pas proposer Wave à la vente.')
            : context.tr('Réservé au propriétaire'),
        helperMaxLines: 2,
      ),
    ),
    const SizedBox(height: 24),
    ],
    ..._ratesBlock(theme),
  ];

  /// Other currencies a sale may be paid in. In Identité, beside the
  /// business's own currency, while Paiements is hidden (cash only, 090).
  List<Widget> _ratesBlock(ThemeData theme) => [
    Text(context.tr('Taux de change'), style: theme.textTheme.labelLarge),
    const SizedBox(height: 4),
    Text(
      'Pour encaisser une vente dans une autre monnaie. Les '
      'livres restent en ${_currency == 'XOF' ? 'FCFA' : _currency}.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 8),
    for (final r in _rates)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.currency_exchange),
        title: Text(rateLabel(r.currency, r.rate, _currency)),
        subtitle: Text(knownCurrencies[r.currency] ?? ''),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: context.tr('Retirer'),
          onPressed: _saving ? null : () => _removeRate(r),
        ),
        onTap: _saving ? null : () => _editRate(r),
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _saving ? null : () => _editRate(),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Ajouter une monnaie')),
      ),
    ),
  ];

  /// « Vos articles »: the shelf before anything else. How many are on
  /// sale against the minimum, then the four gestures that put one there,
  /// each a picture and a line — where the button is, what to type — and
  /// the button that opens the articles.
  List<Widget> _articles(ThemeData theme) {
    final c = _checklist;
    final farm = _profile == 'farm';
    final association = _association;
    final min = _minItems;
    final published = c?.published ?? 0;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final steps = association
        ? <(IconData, String, String)>[
            (Icons.add_box_outlined, 'Ajouter un service',
                'Dans « Mes services », le bouton « Ajouter un service » : le nom et le prix — une adhésion, un cours, la salle.'),
            (Icons.sell_outlined, 'À partir de, par heure',
                'Cochez « À partir de » quand le prix peut monter ; « Par » : heure, séance, personne.'),
            (Icons.photo_camera_outlined, 'Une photo',
                'Facultative : la salle, l\'atelier, l\'équipe. Une photo donne confiance.'),
            (Icons.storefront_outlined, 'Sur la vitrine',
                'Laissez « Sur la vitrine » coché : un service suffit pour que le public voie votre vitrine.'),
          ]
        : farm
        ? <(IconData, String, String)>[
            (Icons.add_box_outlined, 'Mettre en vente',
                'Dans « À vendre », le bouton « Mettre en vente » : quoi, le prix, par quoi (plateau, kg…).'),
            (Icons.numbers, 'Combien vous en avez',
                'La quantité disponible — ou « Pas encore prêt » pour une bande à venir.'),
            (Icons.photo_camera_outlined, 'Une photo',
                'Sur un fond simple, à la lumière du jour : un article en photo se vend bien mieux.'),
            (Icons.storefront_outlined, 'Sur la vitrine',
                'Laissez « Sur la vitrine » coché : vos clients le voient et le commandent.'),
          ]
        : <(IconData, String, String)>[
            (Icons.add_box_outlined, 'Un article à la fois',
                'Dans « Articles », le bouton « Ajouter un article » : la photo, le nom, le prix, combien vous en avez — une question à la fois.'),
            (Icons.playlist_add, 'Plusieurs à la fois',
                '« Ajout multiple » : un article par ligne, par exemple « Savon 20 300 ».'),
            (Icons.photo_camera_outlined, 'Une photo',
                'Touchez l\'article, puis « Ajouter une photo ». Trois photos et votre vitrine fait envie.'),
            (Icons.storefront_outlined, 'Sur la vitrine',
                'Cochez « Afficher sur la vitrine en ligne » — ou « Tout publier » ci-dessous.'),
          ];
    return [
      if (c != null) ...[
        Row(
          key: const Key('articles-count'),
          children: [
            Text('$published',
                style: theme.textTheme.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(' / $min',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                association
                    ? published > 1
                        ? context.tr('services en ligne : la vitrine est visible du public.')
                        : published == 1
                        ? context.tr('service en ligne : la vitrine est visible du public.')
                        : context.tr('service en ligne. Il en faut un pour que le public voie votre vitrine.')
                    : published >= min
                    ? context.tr('articles en vente : la vitrine est visible du public.')
                    : context.tr('articles en vente. Il en faut {min} pour que le public voie votre vitrine.', {'min': min}),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (published / min).clamp(0, 1).toDouble(),
            minHeight: 8,
            color: published >= min ? maraGreen : maraCaramel,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 6),
        if (!association)
          Text(
            context.tr('{n} en photo sur 3 conseillées', {'n': c.withPhoto}),
            style: muted,
          ),
        const SizedBox(height: 20),
      ],
      Text(association
              ? context.tr('Ajouter un service, en quatre gestes')
              : context.tr('Ajouter un article, en quatre gestes'),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            key: Key('articles-step-$i'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: maraDeep,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(steps[i].$1, color: maraCaramel, size: 28),
                  ),
                  Positioned(
                    left: -6,
                    top: -6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: maraCaramel,
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: maraDeep,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr(steps[i].$2),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(context.tr(steps[i].$3), style: muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      if (association && _hidden('services'))
        _SwitchedOff(
          text: context.tr('Les services ne sont pas proposés sur votre vitrine pour le moment.'),
        )
      else
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          key: const Key('articles-open'),
          onPressed: () async {
            await context.push(Routes.inside(widget.orgId,
                association ? 'services' : farm ? 'a-vendre' : 'produits'));
            if (mounted) await _reloadChecklist();
          },
          icon: const Icon(Icons.add),
          label: Text(association
              ? context.tr('Ajouter un service')
              : farm
                  ? context.tr('Mettre en vente')
                  : context.tr('Ajouter un article')),
        ),
      ),
      if (c != null && c.unpublished > 0 && widget.retail != null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('articles-publish-all'),
          onPressed: _saving
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final n = await widget.retail!.publishAll(widget.orgId);
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(
                        content: Text(context.tr('{n} article(s) publié(s) sur la vitrine.', {'n': n}))));
                    await _reloadChecklist();
                  } catch (error) {
                    messenger.showSnackBar(
                        SnackBar(content: Text(describeError(error))));
                  }
                },
          icon: const Icon(Icons.storefront_outlined),
          label: Text(context.tr('Tout publier ({unpublished})', {'unpublished': c.unpublished})),
        ),
      ],
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const Key('settings-next-go'),
          onPressed: () => setState(() => _open = _Part.identity),
          icon: const Icon(Icons.arrow_forward),
          label: Text(context.tr('Suivant : {label}', {'label': context.tr(_Part.identity.label)})),
        ),
      ),
    ];
  }

  List<Widget> _vitrine(ThemeData theme) => [
    // « Commandes en ligne » hidden by Mara (110): said where the vitrine is set.
    if (_hidden('online_orders')) ...[
      _SwitchedOff(
        key: const Key('vitrine-orders-closed'),
        text: context.tr('Commandes fermées par Mara pour le moment : vos clients voient votre vitrine sans pouvoir commander. Les commandes déjà reçues restent dans Commandes.'),
      ),
      const SizedBox(height: 16),
    ],
    Text(context.tr('Vitrine en ligne'), style: theme.textTheme.labelLarge),
    const SizedBox(height: 4),
    Text(
      _association
          ? context.tr('Une page publique de l\'association, avec les services que vous proposez et leur prix, à partager sur WhatsApp. On vous réserve depuis la vitrine ; vous fixez le rendez-vous.')
          : _profile == 'farm'
          ? context.tr('Une page publique de la ferme, avec ce que vous mettez « À vendre » — photo, prix, à l\'unité ou au plateau — à partager sur WhatsApp. Les clients commandent, même à l\'avance pour une bande ou une récolte à venir.')
          : context.tr('Une page publique de la boutique, avec les articles que vous choisissez d\'afficher — photo et prix — à partager sur WhatsApp. Les clients commandent depuis la vitrine.'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: _storefrontEnabled,
      onChanged: _saving ? null : (v) => setState(() => _storefrontEnabled = v),
      title: Text(context.tr('Ouvrir la vitrine')),
    ),
    if (_storefrontEnabled) ...[
      TextField(
        controller: _blurbController,
        enabled: !_saving,
        maxLines: 2,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: _association
              ? context.tr('Quelques mots sur l\'association (facultatif)')
              : _profile == 'farm'
              ? context.tr('Quelques mots sur la ferme (facultatif)')
              : context.tr('Quelques mots sur la boutique (facultatif)'),
        ),
      ),
      const SizedBox(height: 12),
      // Two of the six steps: what a shopper calls, and where they come.
      TextField(
        key: const Key('vitrine-phone'),
        controller: _phoneController,
        enabled: !_saving,
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: _association
              ? context.tr('Téléphone de l\'association')
              : _profile == 'farm'
              ? context.tr('Téléphone de la ferme')
              : context.tr('Téléphone de la boutique'),
          hintText: '+226 70 00 00 00',
          prefixIcon: const Icon(Icons.call_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('vitrine-address'),
        controller: _addressController,
        enabled: !_saving,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.tr('Adresse'),
          hintText: context.tr('Ex. : Gounghin près du marché, Le Plateau, Centre-ville'),
          hintMaxLines: 2,
          prefixIcon: const Icon(Icons.home_work_outlined),
        ),
      ),
      const SizedBox(height: 10),
      _LinkRow(url: _storefrontUrl),
      const SizedBox(height: 16),
      // Not a first step: the dressing (093) waits under « Vitrine
      // avancée », folded — its free basics and preview, and the Pro part
      // as one locked card.
      Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('vitrine-advanced'),
          // Open (122): the vitrine's own look — cover, colour, tagline,
          // hours — is what « my design » means to an owner; folded, it
          // read as gone.
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune),
          title: Text(context.tr('Vitrine avancée'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(context.tr('Couverture, couleur, horaires · aperçu')),
          children: [
            VitrinePlusCard(
              orgId: widget.orgId,
              admin: widget.admin,
              retail: widget.retail,
              capture: widget.capture,
              shopName: _nameController.text.trim().isEmpty
                  ? null
                  : _nameController.text.trim(),
            ),
          ],
        ),
      ),
      // The spots for sale (071), folded on their own. An association
      // buys the whole-vitrine spot only — an article in « À la une »
      // needs stock — and sees here the spots it already asked or paid.
      // Not drawn when Mara's switchboard hid « Mettre en avant » (110).
      if (!_hidden('spots'))
      Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('vitrine-spots'),
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_outlined),
          title: Text(context.tr('Mettre en avant'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(context.tr('Une place en tête de la rue')),
          children: [
            SpotsCard(
              orgId: widget.orgId,
              admin: widget.admin,
              retail: widget.retail,
              vitrineOnly: _association,
            ),
          ],
        ),
      ),
    ],
  ];

  List<Widget> _delivery(ThemeData theme) => [
    if (!_storefrontEnabled) _ClosedNote(theme: theme),
    // Delivery is Kaj Pro (081): a Free shop may prepare its rates, and is
    // told plainly that the vitrine offers pickup only until it is Pro.
    if (widget.plan != 'pro') ...[
      KajCard(
        key: const Key('delivery-pro-note'),
        child: ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(context.tr('La livraison fait partie de Mara Pro')),
          subtitle: Text(_profile == 'farm'
              ? context.tr('Votre vitrine propose le retrait à la ferme. Passez à Mara Pro pour livrer vos clients, avec le prix calculé selon la distance.')
              : context.tr('Votre vitrine propose le retrait en boutique. Passez à Mara Pro pour livrer vos clients, avec le prix calculé selon la distance.')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openPro,
        ),
      ),
      const SizedBox(height: 12),
    ],
    Text(context.tr('Frais de livraison'), style: theme.textTheme.titleSmall),
    const SizedBox(height: 8),
    SegmentedButton<bool>(
      key: const Key('delivery-mode'),
      segments: [
        ButtonSegment(value: false, label: Text(context.tr('Prix au km'))),
        ButtonSegment(value: true, label: Text(context.tr('Minimum, puis au km'))),
      ],
      selected: {_deliveryMinimum},
      onSelectionChanged: _saving
          ? null
          : (s) => setState(() => _deliveryMinimum = s.first),
    ),
    const SizedBox(height: 8),
    Text(
      _deliveryMinimum
          ? context.tr('Le minimum couvre toute course jusqu\'à la distance choisie ; au-delà, chaque kilomètre ajoute le prix par km. Vide : les tarifs de la plateforme (500 + 150 F/km). Le montant est annoncé au client avant qu\'il commande.')
          : _profile == 'farm'
          ? context.tr('Une base pour la course, plus un prix par kilomètre entre votre ferme et la porte du client. Vide : les tarifs de la plateforme (500 + 150 F/km). Le montant est annoncé au client avant qu\'il commande, et payé au livreur à la porte.')
          : context.tr('Une base pour la course, plus un prix par kilomètre entre votre boutique et la porte du client. Vide : les tarifs de la plateforme (500 + 150 F/km). Le montant est annoncé au client avant qu\'il commande, et payé au livreur à la porte.'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 10),
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: _deliveryBaseController,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: _deliveryMinimum ? context.tr('Minimum') : context.tr('Base'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _deliveryPerKmController,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.tr('Par km'),
            ),
          ),
        ),
      ],
    ),
    if (_deliveryMinimum) ...[
      const SizedBox(height: 10),
      TextField(
        key: const Key('delivery-included'),
        controller: _deliveryIncludedController,
        enabled: !_saving,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: context.tr('Minimum jusqu\'à (km)'),
          helperText: context.tr('Ex. 3 : toute course de 0 à 3 km coûte le minimum.'),
        ),
      ),
    ],
    const SizedBox(height: 10),
    TextField(
      controller: _deliveryReachController,
      enabled: !_saving,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: context.tr('Distance maximale (km)'),
        helperText:
            context.tr('Au-delà, la livraison n\'est pas proposée. Vide : 15 km.'),
      ),
    ),
  ];

  List<Widget> _position(ThemeData theme) => [
    Text(context.tr(_positionLabel), style: theme.textTheme.titleSmall),
    const SizedBox(height: 4),
    Text(
      context.tr('Pour que les clients vous trouvent dans l\'annuaire, « près de moi » et sur la carte. Facultatif.'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 10),
    Row(
      children: [
        Expanded(
          child: TextField(
            controller: _latController,
            onChanged: (_) => setState(() {}),
            enabled: !_saving && !_locating,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.tr('Latitude'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _lngController,
            onChanged: (_) => setState(() {}),
            enabled: !_saving && !_locating,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.tr('Longitude'),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          onPressed: (_saving || _locating) ? null : _useMyPosition,
          icon: _locating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
          label: Text(context.tr('Utiliser ma position')),
        ),
        OutlinedButton.icon(
          onPressed: (_saving || _locating) ? null : _pasteMapsLink,
          icon: const Icon(Icons.link),
          label: Text(context.tr('Coller un lien Google Maps')),
        ),
      ],
    ),
    // The pin, seen before saving (package 3).
    if (_pin != null) ...[
      const SizedBox(height: 12),
      PinPreview(
        lat: _pin!.$1,
        lng: _pin!.$2,
        currency: _currency,
        onMove: (lat, lng) => setState(() {
          _latController.text = lat.toStringAsFixed(6);
          _lngController.text = lng.toStringAsFixed(6);
        }),
      ),
    ],
  ];

  List<Widget> _platform(ThemeData theme) => [
        if (widget.canSuspend) ...[
          SwitchListTile(
            key: const Key('wave-allowed'),
            contentPadding: EdgeInsets.zero,
            value: _waveAllowed,
            onChanged: _savingWave ? null : _setWaveAllowed,
            title: Text(context.tr('Autoriser Wave')),
            subtitle: Text(context.tr('Sinon : espèces uniquement.')),
          ),
          const SizedBox(height: 12),
        ],
        Text(context.tr('Wave (plateforme)'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
            context.tr('L\'identifiant que Wave a donné à cette boutique (marchand agrégé). Les paiements des commandes portent son nom chez Wave.'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _merchantRefController,
              enabled: !_savingPayout,
              decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: context.tr('Identifiant marchand Wave')),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed:
                _savingPayout ? null : () => _savePayout(merchant: true),
            child: Text(context.tr('Enregistrer')),
          ),
        ]),
        const SizedBox(height: 32),
    if (widget.canSetPlan) ...[
      const SizedBox(height: 40),
      const Divider(),
      const SizedBox(height: 16),
      Text(context.tr('Formule (plateforme)'), style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        context.tr('Mara Pro se règle à la main pour l\'instant : quand le paiement est arrivé sur Wave, passez l\'entreprise en Pro jusqu\'à la date payée. Passée cette date elle redevient gratuite, sans rien perdre.'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'free', label: Text(context.tr('Mara'))),
          ButtonSegment(value: 'pro', label: Text(context.tr('Mara Pro'))),
        ],
        selected: {_planRaw},
        onSelectionChanged: _savingPlan
            ? null
            : (s) => setState(() => _planRaw = s.first),
      ),
      if (_planRaw == 'pro') ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _savingPlan ? null : _pickPlanUntil,
          icon: const Icon(Icons.event_outlined),
          label: Text(
            _planUntil == null
                ? context.tr('Payé jusqu\'au… (sans date = sans fin)')
                : 'Payé jusqu\'au '
                      '${DateFormat('d MMMM yyyy', intlLocale()).format(_planUntil!)}',
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _planNoteController,
        enabled: !_savingPlan,
        decoration: InputDecoration(
          labelText: context.tr('Note (pour la plateforme)'),
          hintText: context.tr('Wave 25 000 F le 12/09, partenaire, test…'),
          border: const OutlineInputBorder(),
        ),
      ),
      if (_planMessage != null) ...[
        const SizedBox(height: 8),
        Text(_planMessage!, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 12),
      SizedBox(
        height: 52,
        child: FilledButton.tonalIcon(
          onPressed: _savingPlan ? null : _savePlan,
          icon: _savingPlan
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.workspace_premium_outlined),
          label: Text(
            context.tr('Enregistrer la formule'),
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    ],
    if (widget.canSuspend) ...[
      const SizedBox(height: 40),
      const Divider(),
      const SizedBox(height: 16),
      Text(context.tr('Modération de la plateforme'), style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        _suspended
            ? context.tr('Cette entreprise est suspendue : ses membres peuvent consulter mais rien enregistrer. Réactivez-la pour rétablir les opérations.')
            : context.tr('Suspendre gèle toutes les écritures sans rien supprimer. À utiliser pour un impayé, un litige ou un abus, le temps de le régler.'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: _togglingSuspend ? null : _toggleSuspend,
          icon: _togglingSuspend
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _suspended ? Icons.lock_open_outlined : Icons.lock_outline,
                ),
          label: Text(
            _suspended ? context.tr('Réactiver') : context.tr('Suspendre'),
            style: const TextStyle(fontSize: 16),
          ),
          style: _suspended
              ? null
              : OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
        ),
      ),
    ],
  ];

  List<Widget> _saveBar(ThemeData theme) => [
    if (_error != null) ...[
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _error!,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
    ],
    const SizedBox(height: 24),
    SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(context.tr('Enregistrer'), style: const TextStyle(fontSize: 17)),
      ),
    ),
    if (_saved != null && _saved == _open) ...[
      const SizedBox(height: 16),
      Container(
        key: const Key('settings-next'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(context.tr('Enregistré'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            FilledButton.icon(
              key: const Key('settings-next-go'),
              onPressed: () => setState(() {
                final next = _next;
                _saved = null;
                _open = next;
              }),
              icon: Icon(_next?.icon ?? Icons.done_all),
              label: Text(_next == null ? context.tr('Terminé') : context.tr('Suivant : {label}', {'label': context.tr(_labelOf(_next!))})),
            ),
          ],
        ),
      ),
    ],
  ];

  List<Widget> _partBody(_Part part, ThemeData theme) => switch (part) {
    _Part.articles => _articles(theme),
    _Part.identity => [
        ..._identity(theme),
        if (!_waveAllowed) ...[const SizedBox(height: 24), ..._ratesBlock(theme)],
        ..._saveBar(theme),
      ],
    _Part.payments => [
        ..._payments(theme),
        ..._saveBar(theme),
        // Mara's online payment (076), unless the switchboard hid it (110).
        if (_waveAllowed && !_hidden('online_payment')) ..._waveReceive(theme),
      ],
    _Part.vitrine => [..._vitrine(theme), ..._saveBar(theme)],
    _Part.delivery => _toolLocked('delivery')
        ? _proLock(theme, 'delivery', Icons.delivery_dining,
            context.tr('Livraison'),
            context.tr('Livrez vos clients, au prix calculé selon la distance.'))
        : [..._delivery(theme), ..._saveBar(theme)],
    _Part.position => [..._position(theme), ..._saveBar(theme)],
    _Part.team => _team(theme),
    _Part.platform => _platform(theme),
  };

  /// One line under each row: where that part stands, so the index alone
  /// answers most questions.
  String _stateOf(_Part part) {
    final money = _currency == 'XOF' ? 'FCFA' : _currency;
    final c = _checklist;
    switch (part) {
      case _Part.articles:
        if (c == null) {
          return _association
              ? context.tr('Ce que vous proposez')
              : context.tr('Ce que vous vendez');
        }
        if (_association) {
          return context.tr('{n} en ligne', {'n': c.published});
        }
        return [
          context.tr('{n} / {min} en vente', {'n': c.published, 'min': _minItems}),
          context.tr('{n} en photo', {'n': c.withPhoto}),
        ].join(' · ');
      case _Part.identity:
        final name = _nameController.text.trim();
        return [if (name.isNotEmpty) name, money].join(' · ');
      case _Part.payments:
        final wave = _waveController.text.trim();
        return [
          if (!_waveAllowed) context.tr('Espèces')
          else wave.isEmpty ? context.tr('Wave non configuré') : context.tr('Wave configuré'),
          if (_payoutController.text.trim().isNotEmpty)
            context.tr('reçoit sur {number}', {'number': _payoutController.text.trim()}),
          if (_rates.isNotEmpty)
            context.tr(_rates.length > 1 ? '{n} autres monnaies' : '{n} autre monnaie', {'n': _rates.length}),
        ].join(' · ');
      case _Part.vitrine:
        if (!_storefrontEnabled) return context.tr('Fermée');
        final missing = [
          if (_blurbController.text.trim().isEmpty) context.tr('présentation'),
          if (_phoneController.text.trim().isEmpty) context.tr('téléphone'),
          if (_addressController.text.trim().isEmpty) context.tr('adresse'),
        ];
        return missing.isEmpty
            ? context.tr('Ouverte')
            : context.tr('Ouverte · manque : {what}', {'what': missing.join(', ')});
      case _Part.delivery:
        final base = _deliveryBaseController.text.trim();
        final perKm = _deliveryPerKmController.text.trim();
        final reach = _deliveryReachController.text.trim();
        final included = _deliveryIncludedController.text.trim();
        return [
          if (widget.plan != 'pro') 'Mara Pro',
          base.isEmpty && perKm.isEmpty
              ? context.tr('Tarifs de la plateforme')
              : _deliveryMinimum && included.isNotEmpty
                  ? context.tr('{base} F jusqu\'à {km} km, puis {perKm} F/km', {'base': base, 'km': included, 'perKm': perKm.isEmpty ? '0' : perKm})
                  : '${base.isEmpty ? '0' : base} F + ${perKm.isEmpty ? '0' : perKm} F/km',
          '${reach.isEmpty ? '15' : reach} km',
        ].join(' · ');
      case _Part.team:
        return _lockRule == null
            ? context.tr('Aucune règle de verrouillage')
            : context.tr('Code exigé après {delay}', {'delay': _lockRule == 60 ? '1 h' : '$_lockRule min'});
      case _Part.position:
        final pin = _pin;
        if (pin == null) return context.tr('Non renseignée');
        return pinLooksMisplaced(pin.$1, pin.$2, _currency)
            ? context.tr('Loin de la zone de la monnaie')
            : context.tr('Placée sur la carte');
      case _Part.platform:
        return [
          widget.plan == 'pro' ? context.tr('Mara Pro') : context.tr('Mara (gratuit)'),
          if (widget.canSuspend) _suspended ? context.tr('suspendue') : context.tr('active'),
        ].join(' · ');
    }
  }

  bool _warns(_Part part) {
    final pin = _pin;
    return part == _Part.position &&
        pin != null &&
        pinLooksMisplaced(pin.$1, pin.$2, _currency);
  }

  /// Items on sale before the public sees the vitrine (092), at least one;
  /// an association's opens on its first service (098).
  int get _minItems {
    if (_association) return 1;
    final m = _checklist?.minItems ?? 1;
    return m < 1 ? 1 : m;
  }

  bool get _association => _profile == 'association' || _profile == 'church';

  /// An association offers services, not articles (098): « Vos services ».
  /// The position is the business's own place, said as the owner says it
  /// (108): « La position de ma boutique », de ma ferme, de mon association.
  String _labelOf(_Part part) => part == _Part.articles && _association
      ? 'Vos services'
      : part == _Part.position
          ? _positionLabel
          : part.label;

  String get _positionLabel => _association
      ? 'La position de mon association'
      : _profile == 'farm'
          ? 'La position de ma ferme'
          : 'La position de ma boutique';

  /// Each first-steps rubrique done (true) or still to do (false); null for
  /// what is optional and has no « done » (the team's lock, the platform).
  bool? _doneOf(_Part part) {
    final c = _checklist;
    return switch (part) {
      // A service needs no photograph to be understood (098).
      _Part.articles => c == null
          ? null
          : c.published >= _minItems && (_association || c.photosDone),
      _Part.identity => _nameController.text.trim().isNotEmpty,
      _Part.vitrine => _storefrontEnabled &&
          _blurbController.text.trim().isNotEmpty &&
          _phoneController.text.trim().isNotEmpty &&
          _addressController.text.trim().isNotEmpty,
      _Part.position => _pin != null,
      _ => null,
    };
  }

  List<_Part> get _parts => [
    _Part.articles,
    _Part.identity,
    _Part.vitrine,
    _Part.position,
    // Cash only (090): nothing to set until Mara allows Wave.
    if (_waveAllowed) _Part.payments,
    _Part.team,
    // An association's services are booked, not carried (098).
    // « Livraison » hidden by Mara's switchboard (110): no part at all.
    if (!_association && !_hidden('delivery')) _Part.delivery,
    if (widget.canSetPlan || widget.canSuspend) _Part.platform,
  ];

  /// Mara Pro's own: kept apart, under their badge, so the first setup is
  /// the free essentials only.
  static const _proParts = {_Part.delivery};

  Widget _index(ThemeData theme, {required bool wide}) {
    final steps = [for (final p in _flow) _doneOf(p)].whereType<bool>().toList();
    final done = steps.where((d) => d).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Where the first steps stand, at a glance: « 2 sur 4 terminés ».
        if (steps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Column(
              key: const Key('settings-progress'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  done == steps.length
                      ? context.tr('Tout est prêt')
                      : context.tr('{done} sur {total} terminés', {'done': done, 'total': steps.length}),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: done / steps.length,
                    minHeight: 8,
                    color: done == steps.length ? maraGreen : maraCaramel,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        ],
        _Group(
          children: [
            for (final part in _parts.where(
                (p) => p != _Part.platform && !_proParts.contains(p)))
              _PartRow(
                part: part,
                label: _labelOf(part),
                state: _stateOf(part),
                done: _doneOf(part),
                warn: _warns(part),
                selected: wide && _open == part,
                onTap: () => setState(() {
                  _open = part;
                  _saved = null;
                }),
              ),
          ],
        ),
        // Mara Pro (081, 031): delivery and the team's access, apart and
        // badged — not part of a new business's first steps.
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.workspace_premium, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                context.tr('MARA PRO'),
                key: const Key('settings-pro-group'),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        _Group(
          children: [
            for (final part in _parts.where(_proParts.contains))
              _PartRow(
                part: part,
                state: _toolLocked('delivery') ? context.tr('Réservé à Mara Pro') : _stateOf(part),
                proCost: _toolLocked('delivery') ? (_costOf('delivery') ?? 0) : null,
                selected: wide && _open == part,
                onTap: () => setState(() {
                  _open = part;
                  _saved = null;
                }),
              ),
            _PartRow.link(
              icon: Icons.groups_outlined,
              label: context.tr('Équipe et accès'),
              state: _toolLocked('team_access')
                  ? context.tr('Réservé à Mara Pro')
                  : context.tr('Qui voit et modifie quoi'),
              proCost: _toolLocked('team_access') ? (_costOf('team_access') ?? 0) : null,
              onTap: _toolLocked('team_access')
                  ? () => _openPro('team_access')
                  : () => context.push(
                        Routes.inside(widget.orgId, 'administration/acces'),
                      ),
            ),
          ],
        ),
        if (_parts.contains(_Part.platform)) ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              context.tr('PLATEFORME'),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _Group(
            children: [
              _PartRow(
                part: _Part.platform,
                state: _stateOf(_Part.platform),
                selected: wide && _open == _Part.platform,
                onTap: () => setState(() => _open = _Part.platform),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _page(_Part part, ThemeData theme) => ListView(
    key: ValueKey(part),
    padding: const EdgeInsets.all(24),
    children: _partBody(part, theme),
  );

  // A rubrique's edits not saved yet: the business's bar asks before
  // leaving them (A4).
  @override
  Widget build(BuildContext context) =>
      UnsavedInput(isDirty: _unsavedEdits, child: _build(context));

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    // A part the switchboard hid (110), asked by its address: the index.
    final open = _open == _Part.delivery && _hidden('delivery') ? null : _open;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Paramètres de l\'activité'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // A desk: the index on the left, the open part beside it.
    if (wide) {
      return Scaffold(
        appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Paramètres de l\'activité'))),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 380, child: _index(theme, wide: true)),
            const VerticalDivider(width: 1),
            Expanded(
              child: open == null
                  ? Center(
                      child: Text(
                        context.tr('Choisissez une rubrique à gauche.'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : _page(open, theme),
            ),
          ],
        ),
      );
    }

    // A phone: the index, or one part on its own page. Back returns to the
    // index, not out of the settings.
    if (open == null) {
      return Scaffold(
        appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Paramètres de l\'activité'))),
        body: _index(theme, wide: false),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _open = null);
      },
      child: Scaffold(
        appBar: AppBar(
          actions: const [bellRoom],
          leading: IconButton(
            tooltip: context.tr('Retour aux paramètres'),
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _open = null),
          ),
          title: Text(context.tr(_labelOf(open))),
        ),
        body: _page(open, theme),
      ),
    );
  }
}

/// The parts of the business settings, as the index names them.
enum _Part {
  articles('Vos articles', Icons.inventory_2_outlined, 'articles'),
  identity('Identité', Icons.badge_outlined, 'identite'),
  payments('Paiements', Icons.payments_outlined, 'paiements'),
  vitrine('Vitrine', Icons.storefront_outlined, 'vitrine'),
  delivery('Livraison', Icons.delivery_dining_outlined, 'livraison'),
  position('Position', Icons.place_outlined, 'position'),
  team("Sécurité de l'équipe", Icons.shield_outlined, 'equipe'),
  platform('Formule et modération', Icons.admin_panel_settings_outlined, 'plateforme');

  const _Part(this.label, this.icon, this.key);
  final String label;
  final IconData icon;

  /// The rubrique's name in an address (`?partie=articles`).
  final String key;

  static _Part? byKey(String? key) {
    for (final p in values) {
      if (p.key == key) return p;
    }
    return null;
  }
}

/// A rounded card of rows with hairlines between them.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KajCard(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required _Part this.part,
    required this.state,
    required this.onTap,
    this.warn = false,
    this.selected = false,
    this.proCost,
    this.done,
    this.label,
  }) : icon = null;

  const _PartRow.link({
    required IconData this.icon,
    required String this.label,
    required this.state,
    required this.onTap,
    this.proCost,
  }) : part = null,
       warn = false,
       selected = false,
       done = null;

  final _Part? part;
  final IconData? icon;
  final String? label;
  final String state;
  final bool warn;
  final bool selected;
  final VoidCallback onTap;

  /// A first step: done (a green tick) or still to do (« À faire »); null
  /// for what has no « done ».
  final bool? done;

  /// Set when the row is a Pro tool still locked: the badge replaces the
  /// chevron (0 = no cauris price known).
  final int? proCost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      leading: Icon(part?.icon ?? icon),
      title: Text(
        context.tr(label ?? part!.label),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        state,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: warn ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      trailing: proCost != null
          ? ProCostBadge(cost: proCost == 0 ? null : proCost)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (done == true)
                  Icon(Icons.check_circle,
                      key: Key('part-done-${part?.key}'),
                      color: maraGreen,
                      semanticLabel: context.tr('Terminé'))
                else if (done == false)
                  Container(
                    key: Key('part-todo-${part?.key}'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: maraCaramel.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(context.tr('À faire'),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: maraEspresso, fontWeight: FontWeight.w800)),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
      onTap: onTap,
    );
  }
}

/// Delivery belongs to an open vitrine: said, rather than hidden.
class _ClosedNote extends StatelessWidget {
  const _ClosedNote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      context.tr('La vitrine est fermée : ces réglages servent dès son ouverture (rubrique Vitrine).'),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// What Mara's switchboard turned off here (110), said once, plainly.
class _SwitchedOff extends StatelessWidget {
  const _SwitchedOff({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_off_outlined, color: maraBrown),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// The current palette, shown as itself rather than named.
///
/// A row reading "Océan" tells somebody nothing about what their staff are
/// looking at; a strip of the actual gradient does.
class _ColourRow extends StatelessWidget {
  const _ColourRow({
    required this.palette,
    required this.label,
    required this.onTap,
  });

  final KajPalette palette;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 40,
              decoration: BoxDecoration(
                gradient: kajGradient(palette),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(Icons.circle, size: 14, color: palette.ink),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// The vitrine's address with a copy button — what the shop pastes into a
/// WhatsApp status. Selectable too, for the person who would rather long-press.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(url, style: theme.textTheme.bodySmall),
          ),
          IconButton(
            tooltip: context.tr('Copier le lien'),
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(context.tr('Lien copié'))));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// Adding or editing one exchange rate: pick the currency, type the rate the
/// business actually gets. Editing pins the currency and only the rate moves.
///
/// When a XOF business adds EUR, the field pre-fills the CFA franc's fixed
/// peg (655,957) — the one rate that is law rather than market. The owner may
/// still overwrite it with their bank's effective rate.
class RateDialog extends StatefulWidget {
  const RateDialog({
    super.key,
    required this.homeCurrency,
    required this.taken,
    this.existing,
  });

  final String homeCurrency;

  /// Currencies that already have a rate, kept out of the picker so the same
  /// code cannot be added twice.
  final List<String> taken;

  final CurrencyRate? existing;

  @override
  State<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<RateDialog> {
  late final _rateController = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.rate}',
  );
  late String? _code = widget.existing?.currency;

  List<String> get _choices => [
    for (final code in knownCurrencies.keys)
      if (code != widget.homeCurrency && !widget.taken.contains(code)) code,
  ];

  double? get _rate =>
      double.tryParse(_rateController.text.trim().replaceAll(',', '.'));

  bool get _canSave => _code != null && (_rate ?? 0) > 0;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  void _pick(String? code) {
    setState(() {
      _code = code;
      // The peg, offered not imposed: only into an empty field.
      if (code == 'EUR' &&
          widget.homeCurrency == 'XOF' &&
          _rateController.text.trim().isEmpty) {
        _rateController.text = '$eurXofPeg';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.homeCurrency == 'XOF' ? 'FCFA' : widget.homeCurrency;
    return AlertDialog(
      // The keyboard up on a small phone: the dialog scrolls (A6).
      scrollable: true,
      title: Text(
        widget.existing == null ? context.tr('Ajouter une monnaie') : context.tr('Modifier le taux'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.existing == null)
            DropdownButtonFormField<String>(
              initialValue: _code,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('Monnaie'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final code in _choices)
                  DropdownMenuItem(
                    value: code,
                    child: Text('$code — ${knownCurrencies[code]}'),
                  ),
              ],
              onChanged: _pick,
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.existing!.currency} — '
                '${knownCurrencies[widget.existing!.currency] ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _rateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('Taux'),
              prefixText: _code == null ? null : context.tr('1 {_code} = ', {'_code': _code}),
              suffixText: home,
              helperText: _code == 'EUR' && widget.homeCurrency == 'XOF'
                  ? context.tr('Taux fixe officiel : 655,957')
                  : context.tr('Le taux que vous obtenez réellement.'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          onPressed: _canSave
              ? () => Navigator.of(context).pop((_code!, _rate!))
              : null,
          child: Text(context.tr('Enregistrer')),
        ),
      ],
    );
  }
}

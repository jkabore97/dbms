import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/storefront/storefront_repository.dart' show parseGoogleMapsLink;
import '../admin/pin_preview.dart' deferred as pin_map;
import '../common/owned_controller.dart';
import '../storefront/shop_style.dart';
import 'shopper_profile_screen.dart' show addressName;

/// « Mes adresses de livraison » (113): Maison, Travail and the other
/// places, each with the words a courier reads first, a note, and a pin.
/// The order sheet offers them when delivery is chosen.
class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key, required this.shopper, this.tiles = true});

  final ShopperRepository shopper;

  /// The map's tiles; off in widget tests, which have no network.
  final bool tiles;

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  List<SavedAddress>? _addresses;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.shopper.isConfigured) {
      setState(() => _error = context.tr('Votre compte a besoin d\'une connexion.'));
      return;
    }
    try {
      final a = await widget.shopper.addresses();
      if (mounted) {
        setState(() {
          _addresses = a;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('Vos adresses n\'ont pas pu être chargées. Vérifiez le réseau.'));
      }
    }
  }

  Future<void> _edit([SavedAddress? a]) async {
    final all = _addresses ?? const <SavedAddress>[];
    final saved = await showShopSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Theme(
        data: ShopStyle.theme(sheet),
        child: AddressSheet(
          shopper: widget.shopper,
          address: a,
          taken: {
            for (final x in all)
              if (x.kind != 'other' && x.id != a?.id) x.kind,
          },
          tiles: widget.tiles,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(SavedAddress a) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.shopper.deleteAddress(a.id!);
      await _load();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _addresses;
    return ShopPage(
      title: context.tr('Mes adresses'),
      leading: IconButton(
        tooltip: context.tr('Retour'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go(Routes.shopperProfile),
      ),
      body: list == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : ShopNotice(
                  text: _error!,
                  action: OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                ))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                ShopWidth(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          context.tr('Choisies d\'un geste quand vous commandez avec livraison. La note et l\'épingle guident le livreur.'),
                          style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
                        ),
                        const SizedBox(height: 18),
                        for (final a in list)
                          Container(
                            key: Key('address-${a.kind}-${a.id}'),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: ShopStyle.line),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              minTileHeight: 72,
                              onTap: () => _edit(a),
                              leading: Icon(
                                switch (a.kind) {
                                  'home' => Icons.home_outlined,
                                  'work' => Icons.work_outline,
                                  _ => Icons.place_outlined,
                                },
                                color: ShopStyle.ink,
                              ),
                              title: Text(addressName(context, a),
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: ShopStyle.ink)),
                              subtitle: Text(
                                [
                                  a.address,
                                  if (a.note != null) a.note!,
                                  if (a.hasPin) context.tr('position épinglée'),
                                ].join(' · '),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, color: ShopStyle.mist),
                              ),
                              trailing: IconButton(
                                tooltip: context.tr('Retirer'),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(a),
                              ),
                            ),
                          ),
                        if (list.length < 10)
                          OutlinedButton.icon(
                            key: const Key('address-add'),
                            onPressed: () => _edit(),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: Text(list.isEmpty
                                ? context.tr('Ajouter mon adresse')
                                : context.tr('Ajouter une adresse')),
                            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          ),
                        const ShopFooter(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One address, new or changed: its kind, its words, a note, a pin.
class AddressSheet extends StatefulWidget {
  const AddressSheet({
    super.key,
    required this.shopper,
    this.address,
    this.taken = const {},
    this.tiles = true,
  });

  final ShopperRepository shopper;
  final SavedAddress? address;

  /// « home » / « work » already held by another address.
  final Set<String> taken;
  final bool tiles;

  @override
  State<AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<AddressSheet> {
  late String _kind = widget.address?.kind ??
      (!widget.taken.contains('home')
          ? 'home'
          : !widget.taken.contains('work')
              ? 'work'
              : 'other');
  late final _label = TextEditingController(text: widget.address?.label ?? '');
  late final _address = TextEditingController(text: widget.address?.address ?? '');
  late final _note = TextEditingController(text: widget.address?.note ?? '');
  late double? _lat = widget.address?.lat;
  late double? _lng = widget.address?.lng;
  bool _locating = false;
  bool _mapReady = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_lat != null) _loadMap();
  }

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The small map is its own download (flutter_map), fetched once a pin
  /// is there to show.
  Future<void> _loadMap() async {
    try {
      await pin_map.loadLibrary();
      if (mounted) setState(() => _mapReady = true);
    } catch (_) {
      // No map: the pin is still kept, said in words.
    }
  }

  void _pinAt(double lat, double lng) {
    setState(() {
      _lat = lat;
      _lng = lng;
    });
    if (!_mapReady) _loadMap();
  }

  Future<void> _here() async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          messenger?.showSnackBar(SnackBar(content: Text(context.tr('Sans votre position, l\'adresse écrite suffit.'))));
        }
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) _pinAt(p.latitude, p.longitude);
    } catch (_) {
      if (mounted) {
        messenger?.showSnackBar(SnackBar(
            content: Text(context.tr('Position introuvable. Vérifiez que le GPS est activé.'))));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _link() async {
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => OwnedController(
        builder: (context, controller) => AlertDialog(
          title: Text(context.tr('Lien Google Maps')),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(hintText: context.tr('https://www.google.com/maps/...@12.37,-1.52,17z')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Annuler'))),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text(context.tr('Utiliser'))),
          ],
        ),
      ),
    );
    if (text == null || !mounted) return;
    final at = parseGoogleMapsLink(text);
    if (at == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.tr('Ce lien ne contient pas de position. Ouvrez-le dans Google Maps et copiez l\'adresse complète.')),
      ));
      return;
    }
    _pinAt(at.lat, at.lng);
  }

  Future<void> _save() async {
    if (_address.text.trim().length < 2) {
      setState(() => _error = context.tr('Dites où livrer : le quartier, un repère.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.shopper.saveAddress(SavedAddress(
        id: widget.address?.id,
        kind: _kind,
        label: _kind == 'other' ? _label.text.trim() : null,
        address: _address.text.trim(),
        note: _note.text.trim(),
        lat: _lat,
        lng: _lng,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat = _lat;
    final lng = _lng;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.address == null ? context.tr('Nouvelle adresse') : context.tr('Mon adresse'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ShopStyle.ink),
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              key: const Key('address-kind'),
              segments: [
                ButtonSegment(
                  value: 'home',
                  label: Text(context.tr('Maison')),
                  icon: const Icon(Icons.home_outlined),
                  enabled: !widget.taken.contains('home'),
                ),
                ButtonSegment(
                  value: 'work',
                  label: Text(context.tr('Travail')),
                  icon: const Icon(Icons.work_outline),
                  enabled: !widget.taken.contains('work'),
                ),
                ButtonSegment(
                  value: 'other',
                  label: Text(context.tr('Autre')),
                  icon: const Icon(Icons.place_outlined),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _busy ? null : (s) => setState(() => _kind = s.first),
            ),
            if (_kind == 'other') ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('address-label'),
                controller: _label,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('Le nom de ce lieu'),
                  hintText: context.tr('Chez maman, le marché…'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('address-words'),
              controller: _address,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.tr('Où livrer ?'),
                hintText: context.tr('Quartier, repère, en face de…'),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('address-note'),
              controller: _note,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.tr('Une note pour le livreur (facultatif)'),
                hintText: context.tr('Portail bleu, 2e maison…'),
              ),
            ),
            const SizedBox(height: 8),
            if (lat == null || lng == null)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const Key('address-here'),
                    onPressed: _locating ? null : _here,
                    icon: _locating
                        ? const SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 16),
                    label: Text(context.tr('Épingler ma position')),
                  ),
                  TextButton(onPressed: _link, child: Text(context.tr('Lien Google Maps'))),
                ],
              )
            else ...[
              if (_mapReady)
                pin_map.PinPreview(
                  lat: lat,
                  lng: lng,
                  currency: 'XOF',
                  tiles: widget.tiles,
                  onMove: _pinAt,
                )
              else
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 18, color: ShopStyle.ink),
                    const SizedBox(width: 6),
                    Expanded(child: Text(context.tr('Position épinglée pour le livreur'))),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('address-unpin'),
                  onPressed: () => setState(() {
                    _lat = null;
                    _lng = null;
                  }),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(context.tr('Retirer l\'épingle')),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('address-save'),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ShopStyle.paper))
                  : Text(context.tr('Enregistrer')),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/nav/session.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/motion.dart';
import 'shop_style.dart';

/// A shop's window, for the street.
///
/// Opened from a link on WhatsApp by somebody with no account, so it asks for
/// nothing: no sign-in, no PIN, no business. It shows what the shop chose to
/// show — its name, a few words, the articles with a photo and a price — and
/// the ways to act on it: contact the shop, go there, or (055) put articles
/// in a basket and send the shop a réservation. Ordering is the one act that
/// needs a name, so "Commander" walks a stranger through sign-in and brings
/// them straight back to this vitrine to order.
///
/// The look is the settled one for selling goods online (see [ShopStyle]):
/// white page, a quiet header, the shop's name large over a warm band, then
/// the photographs, each on its own off-white square with the name and the
/// price in small type underneath. The photograph is the product; nothing
/// else on the page is allowed to compete with it.
class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({
    super.key,
    required this.slug,
    required this.storefront,
    required this.capture,
    required this.session,
  });

  final String slug;
  final StorefrontRepository storefront;

  /// For the photos, served publicly by the uploads Worker per key.
  final CaptureRepository capture;

  /// Who is holding the phone: ordering needs a signed-in person.
  final SessionController session;

  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  PublicShop? _shop;
  List<PublicItem> _items = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// The basket: product id → quantity. Kept on the device between visits
  /// (see [_restoreBasket]) until "Commander" sends it.
  final Map<String, double> _basket = {};

  /// Where this shop's basket sleeps on the device. Per shop, so filling a
  /// basket at the tailor's never spills into the grocer's.
  String get _basketKey => 'street_basket_${widget.slug}';

  /// A basket is a promise the shopper made to themselves; a page refresh
  /// or the walk through sign-in must not break it. Restored only onto an
  /// empty basket, and only for articles still in the window — prices are
  /// never stored, they are read fresh from the shelf.
  Future<void> _restoreBasket(List<PublicItem> items) async {
    if (_basket.isNotEmpty) return;
    final raw = await widget.session.db.readPref(_basketKey);
    if (raw == null || !mounted) return;
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final onShelf = {for (final i in items) i.id};
      setState(() {
        for (final e in saved.entries) {
          final q = (e.value as num).toDouble();
          if (q > 0 && onShelf.contains(e.key)) _basket[e.key] = q;
        }
      });
    } catch (_) {
      // A basket that cannot be read is an empty basket, not an error.
    }
  }

  void _keepBasket() {
    final db = widget.session.db;
    unawaited(db.writePref(
        _basketKey, _basket.isEmpty ? null : jsonEncode(_basket)));
  }

  /// The shelf filter: instant, on the list already fetched, accent-blind
  /// like the street's search — at forty articles three typed letters beat
  /// any amount of scrolling, and it costs no network at all.
  final _filter = TextEditingController();

  List<PublicItem> get _visible {
    final q = foldSearchText(_filter.text.trim());
    if (q.isEmpty) return _items;
    return _items
        .where((i) => foldSearchText(i.name).contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.storefront.isConfigured) {
      setState(() {
        _error = "La vitrine a besoin d'une connexion.";
        _loading = false;
      });
      return;
    }
    try {
      final shop = await widget.storefront.shop(widget.slug);
      final items = shop == null
          ? const <PublicItem>[]
          : await widget.storefront.items(widget.slug);
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _items = items;
        _loading = false;
      });
      await _restoreBasket(items);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = "La vitrine n'a pas pu être chargée. Vérifiez le réseau.";
        _loading = false;
      });
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _directory() => context.go(Routes.directory);

  void _add(PublicItem item) {
    setState(() => _basket[item.id] = (_basket[item.id] ?? 0) + 1);
    _keepBasket();
  }

  void _remove(PublicItem item) {
    setState(() {
      final q = (_basket[item.id] ?? 0) - 1;
      if (q <= 0) {
        _basket.remove(item.id);
      } else {
        _basket[item.id] = q;
      }
    });
    _keepBasket();
  }

  double get _total => _items.fold(
      0, (sum, i) => sum + (_basket[i.id] ?? 0) * i.price);

  int get _count =>
      _basket.values.fold(0, (sum, q) => sum + q.round());

  /// "Commander": the one act that needs a name. A stranger is sent through
  /// sign-in and brought back to this very vitrine — and the basket now
  /// survives the trip: it sleeps on the device (_keepBasket) and is
  /// restored when the page comes back, so the picking is done once.
  Future<void> _order() async {
    switch (widget.session.phase) {
      case SessionPhase.signedOut:
        widget.session.stashReturnTo(Routes.storefront(widget.slug));
        context.go(Routes.signIn);
        return;
      case SessionPhase.locked:
      case SessionPhase.choosingPin:
        widget.session.stashReturnTo(Routes.storefront(widget.slug));
        context.go(Routes.pin);
        return;
      case SessionPhase.booting:
      case SessionPhase.resolving:
        return;
      case SessionPhase.noOrg:
      case SessionPhase.picking:
      case SessionPhase.ready:
        break;
    }

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Theme(
        data: ShopStyle.theme(sheet),
        child: _OrderSheet(
          items: _items,
          basket: Map.of(_basket),
          currency: _shop?.currency ?? 'XOF',
          waveMerchant: _shop?.waveMerchant,
          onSubmit: _send,
        ),
      ),
    );
    if (sent == true && mounted) {
      setState(_basket.clear);
      _keepBasket(); // The promise is kept; the device forgets it.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Commande envoyée. La boutique vous répondra ici.'),
      ));
      context.go(Routes.myOrders);
    }
  }

  Future<String?> _send({
    required Map<String, double> lines,
    required String fulfilment,
    String? note,
    String? address,
    String? phone,
    required String payment,
    double? dropLat,
    double? dropLng,
  }) async {
    setState(() => _sending = true);
    try {
      await widget.storefront.placeOrder(
        widget.slug,
        lines: lines,
        fulfilment: fulfilment,
        note: note,
        address: address,
        phone: phone,
        payment: payment,
        dropLat: dropLat,
        dropLng: dropLng,
      );
      return null;
    } catch (_) {
      return "La commande n'a pas pu être envoyée. Vérifiez le réseau.";
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    final money = moneyFormat(shop?.currency ?? 'XOF');

    return ShopPage(
      title: shop?.name ?? 'Vitrine',
      leading: IconButton(
        tooltip: 'Toutes les vitrines',
        icon: const Icon(Icons.arrow_back),
        onPressed: _directory,
      ),
      bottom: _basket.isEmpty
          ? null
          : _BasketBar(
              count: _count,
              total: money.format(_total),
              sending: _sending,
              onOrder: _order,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : shop == null
                  ? ShopNotice(
                      text: "Cette vitrine n'existe pas, ou n'est pas ouverte.",
                      action: OutlinedButton(
                          onPressed: _directory,
                          child: const Text('Voir les autres vitrines')),
                    )
                  : _Window(
                      shop: shop,
                      items: _visible,
                      totalCount: _items.length,
                      filter: _filter,
                      onFilterChanged: (_) => setState(() {}),
                      capture: widget.capture,
                      basket: _basket,
                      onOpen: _open,
                      onDirectory: _directory,
                      onAdd: _add,
                      onRemove: _remove,
                    ),
    );
  }
}

/// The basket, pinned under the page: how many, how much, one button.
class _BasketBar extends StatelessWidget {
  const _BasketBar({
    required this.count,
    required this.total,
    required this.sending,
    required this.onOrder,
  });

  final int count;
  final String total;
  final bool sending;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShopStyle.paper,
        border: Border(top: BorderSide(color: ShopStyle.line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count article${count > 1 ? 's' : ''}',
                      style: const TextStyle(
                          fontSize: 13, color: ShopStyle.mist)),
                  Text(total,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ShopStyle.ink)),
                ],
              ),
            ),
            FilledButton(
              onPressed: sending ? null : onOrder,
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ShopStyle.paper))
                  : const Text('Commander'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last step: what is in the basket, how it reaches the customer, and
/// the button that sends it. Kept as one sheet so the thumb never leaves
/// the page it was shopping on.
class _OrderSheet extends StatefulWidget {
  const _OrderSheet({
    required this.items,
    required this.basket,
    required this.currency,
    required this.onSubmit,
    this.waveMerchant,
  });

  final List<PublicItem> items;
  final Map<String, double> basket;
  final String currency;

  /// The shop's Wave link (057). Null means cash is the only choice and
  /// the payment row does not appear at all.
  final String? waveMerchant;

  final Future<String?> Function({
    required Map<String, double> lines,
    required String fulfilment,
    String? note,
    String? address,
    String? phone,
    required String payment,
    double? dropLat,
    double? dropLng,
  }) onSubmit;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  String _fulfilment = 'pickup';
  String _payment = 'cash';

  /// The door's pin (058): the phone's fix or a Google Maps link. Optional;
  /// the address in words is still what the courier reads first.
  double? _dropLat;
  double? _dropLng;
  bool _locating = false;
  final _note = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Where the customer is standing, once. Refusal loses nothing — the
  /// written address still travels with the order.
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
        messenger.showSnackBar(const SnackBar(
          content: Text("Sans votre position, l'adresse écrite suffit."),
        ));
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
        _dropLat = position.latitude;
        _dropLng = position.longitude;
      });
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Position introuvable. Vérifiez que le GPS est activé.'),
      ));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// A link out of Google Maps, for the customer marking a door they are
  /// not standing at. Short goo.gl links carry nothing; the message says so.
  Future<void> _pasteMapsLink() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => Theme(
        data: ShopStyle.theme(dialog),
        child: AlertDialog(
          title: const Text('Lien Google Maps'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'https://www.google.com/maps/...@12.37,-1.52,17z',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.of(dialog).pop(controller.text),
                child: const Text('Utiliser')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    final position = parseGoogleMapsLink(text);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ce lien ne contient pas de position. Ouvrez-le dans '
            "Google Maps et copiez l'adresse complète."),
      ));
      return;
    }
    setState(() {
      _dropLat = position.lat;
      _dropLng = position.lng;
    });
  }

  Future<void> _submit() async {
    if (_fulfilment == 'delivery' && _address.text.trim().isEmpty) {
      setState(() => _error = 'Indiquez où livrer.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(
      lines: widget.basket,
      fulfilment: _fulfilment,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      payment: _payment,
      dropLat: _fulfilment == 'delivery' ? _dropLat : null,
      dropLng: _fulfilment == 'delivery' ? _dropLng : null,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(widget.currency);
    final lines = [
      for (final item in widget.items)
        if ((widget.basket[item.id] ?? 0) > 0) item,
    ];
    final total = lines.fold<double>(
        0, (sum, i) => sum + widget.basket[i.id]! * i.price);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Votre commande',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ShopStyle.ink)),
            const SizedBox(height: 14),
            for (final item in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${widget.basket[item.id]!.round()} × ${item.name}',
                          style: const TextStyle(
                              fontSize: 15, color: ShopStyle.ink)),
                    ),
                    Text(money.format(widget.basket[item.id]! * item.price),
                        style: const TextStyle(
                            fontSize: 14, color: ShopStyle.mist)),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text('Total',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ShopStyle.ink)),
                ),
                Text(money.format(total),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: ShopStyle.ink)),
              ],
            ),
            const SizedBox(height: 18),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'pickup',
                    label: Text('Retrait'),
                    icon: Icon(Icons.storefront_outlined)),
                ButtonSegment(
                    value: 'delivery',
                    label: Text('Livraison'),
                    icon: Icon(Icons.delivery_dining_outlined)),
              ],
              selected: {_fulfilment},
              onSelectionChanged: (s) =>
                  setState(() => _fulfilment = s.first),
            ),
            if (widget.waveMerchant != null) ...[
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'cash',
                      label: Text('Espèces'),
                      icon: Icon(Icons.payments_outlined)),
                  ButtonSegment(
                      value: 'wave',
                      label: Text('Wave'),
                      icon: Icon(Icons.phone_iphone_outlined)),
                ],
                selected: {_payment},
                onSelectionChanged: (s) =>
                    setState(() => _payment = s.first),
              ),
            ],
            if (_fulfilment == 'delivery') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Où livrer ?',
                  hintText: 'Quartier, repère, en face de…',
                ),
              ),
              const SizedBox(height: 8),
              // The pin: exactly where the door is, for the livreur's
              // itinerary. Optional, and said so by staying quiet buttons.
              if (_dropLat == null)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _locating ? null : _useMyPosition,
                      icon: _locating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 16),
                      label: const Text('Épingler ma position'),
                    ),
                    TextButton(
                      onPressed: _pasteMapsLink,
                      child: const Text('Lien Google Maps'),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        size: 18, color: ShopStyle.ink),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Position épinglée pour le livreur',
                          style: TextStyle(
                              fontSize: 14, color: ShopStyle.ink)),
                    ),
                    IconButton(
                      tooltip: 'Retirer',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _dropLat = null;
                        _dropLng = null;
                      }),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Votre numéro (facultatif)',
                hintText: '+226 70 00 00 00',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Un mot pour la boutique (facultatif)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ShopStyle.paper))
                    : const Text('Envoyer la commande'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _payment == 'wave'
                  ? 'Rien à payer maintenant : dès que la boutique accepte, '
                      'un bouton Wave apparaît dans Mes commandes.'
                  : 'Rien à payer maintenant : vous payez à la boutique, '
                      'au retrait ou à la livraison.',
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
            ),
          ],
        ),
      ),
    );
  }
}

class _Window extends StatelessWidget {
  const _Window({
    required this.shop,
    required this.items,
    required this.totalCount,
    required this.filter,
    required this.onFilterChanged,
    required this.capture,
    required this.basket,
    required this.onOpen,
    required this.onDirectory,
    required this.onAdd,
    required this.onRemove,
  });

  final PublicShop shop;
  final List<PublicItem> items;

  /// How many articles the window really holds — [items] is the filtered
  /// view of them.
  final int totalCount;
  final TextEditingController filter;
  final void Function(String) onFilterChanged;
  final CaptureRepository capture;
  final Map<String, double> basket;
  final Future<void> Function(String url) onOpen;
  final VoidCallback onDirectory;
  final void Function(PublicItem) onAdd;
  final void Function(PublicItem) onRemove;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(shop.currency);
    final whatsapp = whatsappUrl(shop.phone);
    final phone = (shop.phone ?? '').trim();
    final address = (shop.address ?? '').trim();
    final blurb = (shop.blurb ?? '').trim();
    final width = MediaQuery.sizeOf(context).width;
    final columns = ShopStyle.columnsFor(width);
    final wide = width >= 560;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // The band: who this is, in a word or two, and the ways to act.
        ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: wide ? 56 : 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.name,
                  style: TextStyle(
                    fontSize: wide ? 40 : 30,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: ShopStyle.ink,
                  ),
                ),
                if (blurb.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(blurb,
                        style: const TextStyle(
                            fontSize: 17,
                            height: 1.45,
                            color: ShopStyle.ink)),
                  ),
                ],
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(address,
                      style: const TextStyle(
                          fontSize: 14, color: ShopStyle.mist)),
                ],
                // Always shown: even a shop with no phone and no pin can be
                // passed along, and Partager is how that happens.
                ...[
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (whatsapp != null)
                        FilledButton(
                          onPressed: () => onOpen(whatsapp),
                          child: const Text('Écrire sur WhatsApp'),
                        ),
                      if (phone.isNotEmpty)
                        OutlinedButton(
                          onPressed: () => onOpen('tel:$phone'),
                          child: const Text('Appeler'),
                        ),
                      // The way there, in the maps app the phone already
                      // has: turn-by-turn, no key, no bill (054).
                      if (shop.hasLocation)
                        OutlinedButton.icon(
                          onPressed: () =>
                              onOpen(directionsUrl(shop.lat!, shop.lng!)),
                          icon: const Icon(Icons.directions_outlined, size: 18),
                          label: const Text('Itinéraire'),
                        ),
                      // A vitrine travels the way news does here: sent on
                      // WhatsApp from one phone to the next. The shop's
                      // customers are its advertisers.
                      OutlinedButton.icon(
                        onPressed: () => onOpen(whatsappShareUrl(
                            'Découvrez ${shop.name} sur Kaj : '
                            '${publicShopUrl(shop.slug)}')),
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: const Text('Partager'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // The goods.
        ShopWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              ShopSectionLabel(
                'Les articles',
                note: totalCount == 0
                    ? null
                    : items.length == totalCount
                        ? '$totalCount article${totalCount > 1 ? 's' : ''}'
                        : '${items.length} sur $totalCount',
              ),
              if (totalCount > 0) ...[
                const SizedBox(height: 6),
                const Text(
                  'Touchez un article pour le commander.',
                  style: TextStyle(fontSize: 13, color: ShopStyle.mist),
                ),
              ],
              // The shelf filter, once the shelf is long enough to need
              // one — on six articles a search box is furniture.
              if (totalCount > 6) ...[
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: TextField(
                    controller: filter,
                    onChanged: onFilterChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Chercher dans la boutique…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: filter.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                filter.clear();
                                onFilterChanged('');
                              },
                            ),
                      filled: true,
                      fillColor: ShopStyle.stone,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(
                            color: ShopStyle.ink, width: 1.4),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (totalCount == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aucun article affiché pour le moment.',
                      style: TextStyle(fontSize: 15, color: ShopStyle.mist)),
                )
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Aucun article ne répond à « ${filter.text.trim()} » '
                    'dans cette boutique.',
                    style:
                        const TextStyle(fontSize: 15, color: ShopStyle.mist),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: wide ? 24 : 14,
                    mainAxisSpacing: wide ? 36 : 26,
                    // Room under the square for a two-line name, the price
                    // and an "Épuisé" — measured, not guessed: 0.74 clipped
                    // the last line on a 390px phone.
                    childAspectRatio: wide ? 0.70 : 0.62,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final tile = Lift(
                      // Steady while the basket is open: a tile with the
                      // stepper on it must not slide under the thumb.
                      enabled: (basket[items[i].id] ?? 0) == 0,
                      child: _ItemTile(
                        item: items[i],
                        money: money,
                        capture: capture,
                        quantity: basket[items[i].id] ?? 0,
                        onAdd: () => onAdd(items[i]),
                        onRemove: () => onRemove(items[i]),
                      ),
                    );
                    // The entrance plays when the shelf appears — not on
                    // every keystroke of the filter, which rebuilds these
                    // tiles: a page that re-enters as you type flickers.
                    if (filter.text.isNotEmpty) return tile;
                    return Reveal(delay: KajMotion.stagger(i), child: tile);
                  },
                ),
              ShopFooter(onDirectory: onDirectory),
            ],
          ),
        ),
      ],
    );
  }
}

/// One article: the photograph on its square, then the name and the price
/// in small type. No frame, no shadow — the square is the frame. Tapping
/// an article in stock puts one in the basket; once there, a small stepper
/// sits on the photo. Out of stock fades the picture and says so under the
/// price, rather than shouting over it in red.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.money,
    required this.capture,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final PublicItem item;
  final dynamic money;
  final CaptureRepository capture;
  final double quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.inStock ? onAdd : null,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: ShopStyle.stone,
                    child: Opacity(
                      opacity: item.inStock ? 1 : 0.45,
                      child: _Photo(photoKey: item.photoKey, capture: capture),
                    ),
                  ),
                  if (quantity > 0)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ShopStyle.ink,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StepButton(
                                icon: Icons.remove, onTap: onRemove),
                            Text('${quantity.round()}',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: ShopStyle.paper)),
                            _StepButton(icon: Icons.add, onTap: onAdd),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: ShopStyle.ink),
          ),
          const SizedBox(height: 3),
          Text(
            money.format(item.price),
            style: const TextStyle(fontSize: 14, color: ShopStyle.mist),
          ),
          if (!item.inStock)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text('Épuisé',
                  style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: ShopStyle.mist)),
            ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 16, color: ShopStyle.paper),
      ),
    );
  }
}

/// The article's photo, fetched once through the public read and held for
/// the life of the tile — a rebuild must not refetch a picture on a slow link.
class _Photo extends StatefulWidget {
  const _Photo({required this.photoKey, required this.capture});

  final String? photoKey;
  final CaptureRepository capture;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  late final Future<Uint8List>? _bytes = widget.photoKey == null
      ? null
      : widget.capture.publicObjectBytes(widget.photoKey!);

  @override
  Widget build(BuildContext context) {
    const placeholder = Center(
      child: Icon(Icons.image_outlined, size: 34, color: ShopStyle.line),
    );
    final future = _bytes;
    if (future == null) return placeholder;
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}

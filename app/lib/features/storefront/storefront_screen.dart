import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/nav/session.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/motion.dart';
import '../common/owned_controller.dart';
import 'shop_skeleton.dart';
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

  /// The basket's place in the page, just above « Toutes les vitrines »
  /// and the footer. Once it is on screen the floating card steps aside,
  /// so the basket is never drawn under the footer.
  final _inlineBasket = GlobalKey();
  bool _inlineShown = false;

  void _checkInline() {
    if (!mounted) return;
    final box = _inlineBasket.currentContext?.findRenderObject() as RenderBox?;
    var shown = false;
    if (box != null && box.attached && box.hasSize) {
      final top = box.localToGlobal(Offset.zero).dy;
      shown = top < MediaQuery.sizeOf(context).height - 24;
    }
    if (shown != _inlineShown) setState(() => _inlineShown = shown);
  }

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
          // A Pro shop's shelf order (068): pinned first, out-of-stock
          // left off when it asked. The street reads it, the shop set it.
          : shop.style.arrange(await widget.storefront.items(widget.slug));
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _items = items;
        _loading = false;
      });
      // The street's counter (071): a window opened. Never in the way.
      if (shop != null) {
        unawaited(widget.storefront.recordVisit(widget.slug, 'opened'));
        unawaited(_countVisitor());
      }
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

  /// This phone, as one visitor of the street (084): a random id made once
  /// and kept on the device — never a hardware id, never the person.
  static const _visitorKey = 'street.visitor_id';

  Future<void> _countVisitor() async {
    try {
      final db = widget.session.db;
      var id = await db.readPref(_visitorKey);
      if (id == null || id.length < 8) {
        id = const Uuid().v4();
        await db.writePref(_visitorKey, id);
      }
      await widget.storefront.recordVisitor(widget.slug, id);
    } catch (_) {}
  }

  void _add(PublicItem item) {
    if ((_basket[item.id] ?? 0) == 0) {
      unawaited(widget.storefront
          .recordVisit(widget.slug, 'added', productId: item.id));
    }
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
      case SessionPhase.twoStep:
        widget.session.stashReturnTo(Routes.storefront(widget.slug));
        context.go(Routes.twoStep);
        return;
      case SessionPhase.booting:
      case SessionPhase.resolving:
        return;
      case SessionPhase.noOrg:
      case SessionPhase.picking:
      case SessionPhase.ready:
        break;
    }

    final sent = await showShopSheet<bool>(
      context: context,
      builder: (sheet) => Theme(
        data: ShopStyle.theme(sheet),
        child: OrderSheet(
          items: _items,
          basket: Map.of(_basket),
          currency: _shop?.currency ?? 'XOF',
          waveMerchant: _shop?.waveMerchant,
          delivers: _shop?.delivers ?? false,
          onSubmit: _send,
          quote: (lat, lng) =>
              widget.storefront.deliveryCheck(widget.slug, lat: lat, lng: lng),
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
    } on PostgrestException catch (e) {
      // A refusal the shop's rules made (069: beyond its reach) is said in
      // the server's words; only a failure to reach the server is "network".
      return e.code == 'P0001'
          ? e.message
          : "La commande n'a pas pu être envoyée. Vérifiez le réseau.";
    } catch (_) {
      return "La commande n'a pas pu être envoyée. Vérifiez le réseau.";
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Measured after this frame: has the basket's place in the page come
    // into view (a short shelf, or scrolled to the end)?
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInline());
    Widget basketBar({required bool floating}) => _BasketBar(
          floating: floating,
          picked: [
            for (final i in _items)
              if ((_basket[i.id] ?? 0) > 0) (i, (_basket[i.id] ?? 0).round()),
          ],
          capture: widget.capture,
          count: _count,
          total: moneyFormat(_shop?.currency ?? 'XOF').format(_total),
          sending: _sending,
          onOrder: _order,
        );
    final shop = _shop;

    return ShopPage(
      title: shop?.name ?? 'Vitrine',
      announcements:
          shop?.profile == 'farm' ? ShopPage.farm : ShopPage.street,
      // A Pro shop's button colour (068) — the order bar, WhatsApp, the
      // stepper — decided by the shop, read by the street.
      accent: shop?.style.accent,
      leading: IconButton(
        tooltip: 'Toutes les vitrines',
        icon: const Icon(Icons.arrow_back),
        onPressed: _directory,
      ),
      overlay: _basket.isEmpty || _inlineShown ? null : basketBar(floating: true),
      body: _loading
          ? const ShopSkeleton.shelf()
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
                  : NotificationListener<ScrollNotification>(
                      // Measured once the scrolled frame is laid out: during
                      // the notification the page has not moved yet.
                      onNotification: (_) {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _checkInline());
                        return false;
                      },
                      child: _Window(
                      basketCard: _basket.isEmpty
                          ? null
                          : KeyedSubtree(
                              key: _inlineBasket,
                              child: basketBar(floating: false)),
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
                      onDetails: _details,
                    ),
                    ),
    );
  }

  /// The article on its own (070): the large photo, the words the shop
  /// wrote, the stock, the stepper, and a question by WhatsApp — the page a
  /// shopper wants before deciding, which used to be one tap straight into
  /// the basket.
  Future<void> _details(PublicItem item) async {
    final shop = _shop;
    if (shop == null) return;
    unawaited(widget.storefront
        .recordVisit(widget.slug, 'opened', productId: item.id));
    await showShopSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Theme(
        data: ShopStyle.theme(sheet, accent: shop.style.accent),
        child: StatefulBuilder(
          builder: (sheet, setSheet) => ArticleSheet(
            item: item,
            shopName: shop.name,
            currency: shop.currency,
            phone: shop.phone,
            capture: widget.capture,
            quantity: _basket[item.id] ?? 0,
            onAdd: () {
              _add(item);
              setSheet(() {});
            },
            onRemove: () {
              _remove(item);
              setSheet(() {});
            },
            onOpen: _open,
          ),
        ),
      ),
    );
  }
}

/// The basket, pinned under the page: how many, how much, one button.
class _BasketBar extends StatelessWidget {
  const _BasketBar({
    required this.floating,
    required this.picked,
    required this.capture,
    required this.count,
    required this.total,
    required this.sending,
    required this.onOrder,
  });

  /// Over the page while browsing, or in it, above the footer.
  final bool floating;

  /// What is in the basket, in the shelf's order, with how many of each.
  final List<(PublicItem, int)> picked;
  final CaptureRepository capture;
  final int count;
  final String total;
  final bool sending;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    // A card that floats over the page while the shopper is among the
    // goods; at the end of the page the same card sits in it, above
    // « Toutes les vitrines » and the footer — never under them.
    final card = Material(
              key: Key(floating ? 'basket-bar' : 'basket-inline'),
              color: ShopStyle.paper,
              elevation: floating ? 4 : 0,
              shadowColor: const Color(0x22000000),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: ShopStyle.line),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!floating) ...[
                      const Text('VOTRE PANIER',
                          style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                              color: ShopStyle.ink)),
                      const SizedBox(height: 8),
                    ],
                    // Each article picked: its photo, small, and its name.
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        key: const Key('basket-picked'),
                        scrollDirection: Axis.horizontal,
                        itemCount: picked.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final (item, qty) = picked[i];
                          return _PickedChip(
                              key: ValueKey(item.id),
                              item: item,
                              qty: qty,
                              capture: capture);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
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
                  ],
                ),
              ),
            );
    if (!floating) return card;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: card,
          ),
        ),
      ),
    );
  }
}

/// One article in the basket bar: a small square of its photo (or its
/// initial), its name, and « ×2 » when there is more than one.
class _PickedChip extends StatelessWidget {
  const _PickedChip({
    super.key,
    required this.item,
    required this.qty,
    required this.capture,
  });

  final PublicItem item;
  final int qty;
  final CaptureRepository capture;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: ShopStyle.stone,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 36,
              height: 36,
              child: item.photoKey == null
                  ? ColoredBox(
                      color: ShopStyle.paper,
                      child: Center(
                        child: Text(
                          item.name.isEmpty
                              ? '?'
                              : item.name.characters.first.toUpperCase(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: ShopStyle.mist),
                        ),
                      ),
                    )
                  : _Photo(
                      photoKey: item.photoKey,
                      capture: capture,
                      label: item.name,
                      lean: false,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: ShopStyle.ink)),
          ),
          if (qty > 1)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('×$qty',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ShopStyle.mist)),
            ),
        ],
      ),
    );
  }
}

/// The last step: what is in the basket, how it reaches the customer, and
/// the button that sends it. Kept as one sheet so the thumb never leaves
/// the page it was shopping on.
class OrderSheet extends StatefulWidget {
  const OrderSheet({
    super.key,
    required this.items,
    required this.basket,
    required this.currency,
    required this.onSubmit,
    required this.quote,
    this.waveMerchant,
    this.delivers = true,
  });

  /// Whether « Livraison » is offered at all (081: Kaj Pro shops on the
  /// map). False: pickup is the only way, and no toggle is drawn.

  final List<PublicItem> items;
  final Map<String, double> basket;
  final String currency;

  /// The shop's Wave link (057). Null means cash is the only choice and
  /// the payment row does not appear at all.
  final String? waveMerchant;

  final bool delivers;

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

  /// What a delivery to a pin would cost and whether the shop goes that far
  /// (061, 069) — asked the moment the customer pins their door, so the
  /// answer is on the sheet before "Commander".
  final Future<DeliveryCheck?> Function(double lat, double lng) quote;

  @override
  State<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<OrderSheet> {
  String _fulfilment = 'pickup';
  String _payment = 'cash';

  /// The door's pin (058): the phone's fix or a Google Maps link. Optional;
  /// the address in words is still what the courier reads first.
  double? _dropLat;
  double? _dropLng;
  bool _locating = false;

  /// The delivery's price for the pinned door: a number, null when none
  /// could be fixed ("à discuter"), and unknown while the question is out.
  double? _fee;
  bool _quoting = false;
  bool _feeKnown = false;

  /// The door is beyond the shop's reach (069): no delivery to it.
  bool _tooFar = false;
  double? _distanceKm;
  double? _maxKm;
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

  /// Asks the shop what the run to the pin costs. Answered in words when
  /// there is no number: a customer told nothing decides nothing.
  Future<void> _refreshQuote() async {
    final lat = _dropLat;
    final lng = _dropLng;
    if (lat == null || lng == null) {
      setState(() {
        _fee = null;
        _feeKnown = false;
        _tooFar = false;
      });
      return;
    }
    setState(() => _quoting = true);
    DeliveryCheck? check;
    try {
      check = await widget.quote(lat, lng);
    } catch (_) {
      check = null;
    }
    if (!mounted) return;
    setState(() {
      _fee = check?.fee;
      _tooFar = check?.tooFar ?? false;
      _distanceKm = check?.distanceKm;
      _maxKm = check?.maxKm;
      _feeKnown = true;
      _quoting = false;
    });
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
      await _refreshQuote();
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
    // The dialog owns its field (OwnedController): disposed after the
    // dialog has left the screen, not while it animates out.
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => Theme(
        data: ShopStyle.theme(dialog),
        child: OwnedController(
          builder: (context, controller) => AlertDialog(
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler')),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(controller.text),
                  child: const Text('Utiliser')),
            ],
          ),
        ),
      ),
    );
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
    await _refreshQuote();
  }

  Future<void> _submit() async {
    if (_fulfilment == 'delivery' && _address.text.trim().isEmpty) {
      setState(() => _error = 'Indiquez où livrer.');
      return;
    }
    if (_fulfilment == 'delivery' && _tooFar) {
      setState(() => _error = _tooFarSentence);
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

  /// "Trop loin" said with its numbers, and the way out.
  String get _tooFarSentence {
    final km = _distanceKm == null ? '' : ' (${_distanceKm!.toStringAsFixed(1)} km';
    final max = _maxKm == null
        ? (km.isEmpty ? '' : ')')
        : '${km.isEmpty ? ' (' : ', '}livraison jusqu\'à ${_maxKm!.toStringAsFixed(0)} km)';
    return 'Cette boutique ne livre pas aussi loin$km$max. '
        'Choisissez le retrait en boutique.';
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
            // The delivery's price sits above the total, said before the
            // customer commits: a number once the door is pinned, "à
            // discuter" when none can be fixed, and a hint until then.
            if (_fulfilment == 'delivery') ...[
              Row(
                children: [
                  const Expanded(
                    child: Text('Livraison',
                        style: TextStyle(fontSize: 15, color: ShopStyle.ink)),
                  ),
                  if (_quoting)
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Text(
                      !_feeKnown
                          ? 'épinglez votre porte pour le prix'
                          : _tooFar
                              ? 'trop loin'
                              : _fee == null
                                  ? 'à discuter avec la boutique'
                                  : money.format(_fee!),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: _fee == null && !_tooFar
                              ? FontWeight.w400
                              : FontWeight.w600,
                          color: _tooFar
                              ? Theme.of(context).colorScheme.error
                              : _fee == null
                                  ? ShopStyle.mist
                                  : ShopStyle.ink),
                    ),
                ],
              ),
              if (_tooFar) ...[
                const SizedBox(height: 4),
                Text(_tooFarSentence,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                const Expanded(
                  child: Text('Total',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ShopStyle.ink)),
                ),
                Text(
                    money.format(total +
                        (_fulfilment == 'delivery' && !_tooFar
                            ? (_fee ?? 0)
                            : 0)),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: ShopStyle.ink)),
              ],
            ),
            const SizedBox(height: 18),
            if (widget.delivers)
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
                        _fee = null;
                        _feeKnown = false;
                        _tooFar = false;
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
                onPressed:
                    _busy || (_fulfilment == 'delivery' && _tooFar)
                        ? null
                        : _submit,
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
    this.basketCard,
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
    required this.onDetails,
  });

  /// The basket, in the page after the goods, before the footer.
  final Widget? basketCard;
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
  final void Function(PublicItem) onDetails;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(shop.currency);
    final whatsapp = whatsappUrl(shop.phone);
    final phone = (shop.phone ?? '').trim();
    final address = (shop.address ?? '').trim();
    final blurb = (shop.blurb ?? '').trim();
    final style = shop.style;
    final width = MediaQuery.sizeOf(context).width;
    final columns = ShopStyle.columnsFor(width);
    final wide = width >= 560;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // A Pro shop's cover (068): one of its own photographs, wide and
        // quiet, over the band. The band itself does not change.
        if (style.coverKey != null)
          AspectRatio(
            aspectRatio: wide ? 3.2 : 1.9,
            child: ColoredBox(
              color: ShopStyle.stone,
              child: _Photo(
                photoKey: style.coverKey,
                capture: capture,
                label: 'Photo de ${shop.name}',
              ),
            ),
          ),
        // The band: who this is, in a word or two, and the ways to act.
        // It settles in as the page opens.
        Reveal(
        child: ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: wide ? 40 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The shop's logo (080) beside its name, for every plan.
                Row(
                  children: [
                    if (style.logoKey != null) ...[
                      Container(
                        key: const Key('shop-logo'),
                        width: wide ? 72 : 56,
                        height: wide ? 72 : 56,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x14000000)),
                        ),
                        child: _Photo(
                          photoKey: style.logoKey,
                          capture: capture,
                          label: 'Logo de ${shop.name}',
                          fit: BoxFit.contain,
                        ),
                      ),
                      SizedBox(width: wide ? 18 : 14),
                    ],
                    Expanded(
                      child: Text(
                        shop.name,
                        style: TextStyle(
                          fontSize: wide ? 40 : 30,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: ShopStyle.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                // The tagline (068): one line, in the shop's colour when
                // it chose one.
                if (style.tagline != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    style.tagline!,
                    style: TextStyle(
                      fontSize: wide ? 20 : 17,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: style.accent ?? ShopStyle.ink,
                    ),
                  ),
                ],
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
                // The facts a shopper looks for first, on one quiet line:
                // what kind of place, where, and how the goods reach them.
                // A fact the shop has not given is left out, never shown
                // empty (070).
                const SizedBox(height: 10),
                // Last week's podium (086): a shop customers can trust.
                if (style.topWeekRank != null) ...[
                  Container(
                    key: const Key('top-week-badge'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B63D),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      style.topWeekRank == 1
                          ? '🏆 1er de la semaine'
                          : '🏆 Top 3 de la semaine',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E2560)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  [
                    _kindOf(shop.profile),
                    if (address.isNotEmpty) address,
                    shop.delivers
                        ? 'Retrait ou livraison'
                        : shop.profile == 'farm'
                            ? 'Retrait à la ferme'
                            : 'Retrait en boutique',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 14, color: ShopStyle.mist),
                ),
                // Opening hours (068), the question every caller asks.
                if (style.hours != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.schedule_outlined,
                          size: 15, color: ShopStyle.mist),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(style.hours!,
                            style: const TextStyle(
                                fontSize: 14, color: ShopStyle.mist)),
                      ),
                    ],
                  ),
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
                            'Découvrez ${shop.name} sur Mara : '
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
                  'Touchez un article pour le voir, « + » pour l\'ajouter.',
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
                LayoutBuilder(builder: (context, box) {
                  final gap = wide ? 24.0 : 14.0;
                  final cell = (box.maxWidth - gap * (columns - 1)) / columns;
                  return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: wide ? 28 : 20,
                    // The cell is the square plus the text under it, added
                    // up rather than guessed as a ratio: the ratio left a
                    // band of empty space under every row on a phone (the
                    // audit's screenshot), and clipped when names ran long.
                    mainAxisExtent: cell +
                        _ItemTile.textHeight(
                          context,
                          description: items.any((i) => i.hasDescription),
                          soldOut: items.any((i) => !i.inStock),
                        ),
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final tile = Lift(
                      // The photograph leans in (ZoomOnHover); the tile holds still.
                      scale: 1.0,
                      // Steady while the basket is open: a tile with the
                      // stepper on it must not slide under the thumb.
                      enabled: (basket[items[i].id] ?? 0) == 0,
                      child: _ItemTile(
                        item: items[i],
                        money: money,
                        capture: capture,
                        quantity: basket[items[i].id] ?? 0,
                        accent: shop.style.accent,
                        onAdd: () => onAdd(items[i]),
                        onRemove: () => onRemove(items[i]),
                        onOpen: () => onDetails(items[i]),
                      ),
                    );
                    // The entrance plays when the shelf appears — not on
                    // every keystroke of the filter, which rebuilds these
                    // tiles: a page that re-enters as you type flickers.
                    if (filter.text.isNotEmpty) return tile;
                    // Each row rises as the reader reaches it, the tiles of a
                    // row a beat apart (the goods sites' collection grid).
                    return ScrollReveal(
                        delay: KajMotion.stagger(i % columns), child: tile);
                  },
                );
                }),
              if (basketCard != null) ...[
                const SizedBox(height: 32),
                basketCard!,
              ],
              ShopFooter(onDirectory: onDirectory),
            ],
          ),
        ),
      ],
    );
  }
}

/// The price as the street reads it: « 2 500 F / plateau » when the
/// business sells by a unit (083), the plain price otherwise.
String priceOf(NumberFormat money, PublicItem item) => item.unit == null
    ? money.format(item.price)
    : '${money.format(item.price)} / ${item.unit}';

/// « Disponible à partir du 15/11 » — a batch or a harvest still to come,
/// orderable now (083).
String preorderLine(PublicItem item) =>
    'Disponible à partir du ${DateFormat('dd/MM').format(item.availableFrom!)}';

/// What kind of place this is, in the word a shopper uses.
String _kindOf(String profile) => switch (profile) {
      'farm' => 'Ferme',
      'association' || 'church' => 'Association',
      _ => 'Boutique',
    };

/// One article: its square — the photograph, or the name set large when
/// there is none — then the name and the price in small type. Tapping the
/// tile opens the article (ArticleSheet); the round « + » on the square
/// puts one in the basket without opening anything, and once there a
/// stepper takes its place. Out of stock fades the square and says so.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.money,
    required this.capture,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
    this.accent,
  });

  final PublicItem item;
  final dynamic money;
  final CaptureRepository capture;
  final double quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onOpen;
  final Color? accent;

  /// The height of everything under the square, measured from the type
  /// sizes below and the text scale in force — so the grid's cells fit
  /// their tiles exactly, with no band of white under each row.
  static double textHeight(BuildContext context,
      {required bool description, required bool soldOut}) {
    final k = MediaQuery.textScalerOf(context).scale(1);
    var h = 10.0; // gap under the square
    h += 15 * 1.25 * 2 * k; // name, two lines
    h += 3 + 14 * 1.4 * k; // price
    if (description) h += 4 + 13 * 1.3 * 2 * k;
    if (soldOut) h += 2 + 12 * 1.4 * k;
    return h + 4;
  }

  @override
  Widget build(BuildContext context) {
    final count = quantity.round();
    final label = [
      item.name,
      priceOf(money, item),
      if (item.isPreorder) preorderLine(item),
      if (item.hasDescription) item.description!,
      if (!item.inStock) 'épuisé',
      if (count > 0) '$count dans le panier',
    ].join(', ');
    return _HoverScope(
      child: Semantics(
      container: true,
      button: true,
      label: label,
      hint: "Voir l'article",
      onTap: onOpen,
      child: InkWell(
        onTap: onOpen,
        excludeFromSemantics: true,
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
                    ExcludeSemantics(
                      child: Opacity(
                        opacity: item.inStock ? 1 : 0.45,
                        child: item.photoKey == null
                            ? NoPhotoPanel(name: item.name, accent: accent)
                            : ColoredBox(
                                color: ShopStyle.stone,
                                child: _Photo(
                                    photoKey: item.photoKey, capture: capture),
                              ),
                      ),
                    ),
                    if (item.inStock)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: count > 0
                            ? _Stepper(
                                name: item.name,
                                count: count,
                                onAdd: onAdd,
                                onRemove: onRemove)
                            : _ShowOnHover(
                                child: _QuickAdd(name: item.name, onAdd: onAdd)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    priceOf(money, item),
                    style:
                        const TextStyle(fontSize: 14, color: ShopStyle.mist),
                  ),
                  if (item.isPreorder)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(preorderLine(item),
                          key: const Key('preorder-line'),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ShopStyle.ink)),
                    ),
                  if (item.hasDescription)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: ShopStyle.mist),
                      ),
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
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// Whether the pointer is over an article's tile, for what should only
/// show then: on a desk the « + » waits off the square and slides up under
/// the pointer, as the goods sites' quick-add does. On a phone — no
/// pointer to hover — it is always there.
class _HoverScope extends StatefulWidget {
  const _HoverScope({required this.child});

  final Widget child;

  static bool hovered(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Hovered>()?.on ?? false;

  @override
  State<_HoverScope> createState() => _HoverScopeState();
}

class _HoverScopeState extends State<_HoverScope> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _on = true),
        onExit: (_) => setState(() => _on = false),
        child: _Hovered(on: _on, child: widget.child),
      );
}

class _Hovered extends InheritedWidget {
  const _Hovered({required this.on, required super.child});

  final bool on;

  @override
  bool updateShouldNotify(_Hovered old) => old.on != on;
}

class _ShowOnHover extends StatelessWidget {
  const _ShowOnHover({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final desk = MediaQuery.sizeOf(context).width >= ShopStyle.deskWidth;
    if (!desk || KajMotion.reduced(context)) return child;
    final on = _HoverScope.hovered(context);
    return AnimatedSlide(
      offset: on ? Offset.zero : const Offset(0, 0.6),
      duration: KajMotion.quick,
      curve: KajMotion.ease,
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: KajMotion.quick,
        curve: KajMotion.ease,
        // A keyboard or screen-reader user reaches it all the same.
        alwaysIncludeSemantics: true,
        child: child,
      ),
    );
  }
}

/// The square of an article with no photograph (070): the name, set in
/// type on a soft wash of the shop's colour — a label, not a missing
/// picture. The audit found one photo in seventy articles; the grey icon
/// this replaces made every one of the other sixty-nine read as broken.
class NoPhotoPanel extends StatelessWidget {
  const NoPhotoPanel({super.key, required this.name, this.accent, this.large = false});

  final String name;
  final Color? accent;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? ShopStyle.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(tint.withValues(alpha: 0.07), ShopStyle.stone),
        border: Border(left: BorderSide(color: tint.withValues(alpha: 0.55), width: 3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(large ? 28 : 14),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            name,
            maxLines: large ? 3 : 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: large ? 30 : 19,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Color.alphaBlend(tint.withValues(alpha: 0.75), ShopStyle.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round « + » on an article's square: one in the basket, nothing opened.
class _QuickAdd extends StatelessWidget {
  const _QuickAdd({required this.name, required this.onAdd});

  final String name;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      label: 'Ajouter un $name au panier',
      excludeSemantics: true,
      onTap: onAdd,
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onAdd,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.add, size: 20, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}

/// − count + on a basketed article.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.name,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });

  final String name;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ShopStyle.ink,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
              icon: Icons.remove, label: 'Retirer un $name', onTap: onRemove),
          ExcludeSemantics(
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ShopStyle.paper)),
          ),
          _StepButton(icon: Icons.add, label: 'Ajouter un $name', onTap: onAdd),
        ],
      ),
    );
  }
}

/// One article on its own (070): what a shopper wants before deciding —
/// the photograph large (or the name, large), the price, the shop's own
/// words, whether there is any, the stepper, and a question to the shop on
/// WhatsApp naming the article.
class ArticleSheet extends StatelessWidget {
  const ArticleSheet({
    super.key,
    required this.item,
    required this.shopName,
    required this.currency,
    required this.capture,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
    this.phone,
  });

  final PublicItem item;
  final String shopName;
  final String currency;
  final String? phone;
  final CaptureRepository capture;
  final double quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(currency);
    final count = quantity.round();
    final ask = whatsappUrl(phone, text:
        'Bonjour $shopName, une question sur « ${item.name} » vu sur votre vitrine Mara.');
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: AspectRatio(
                // A photograph gets room; a name on a wash needs little.
                aspectRatio: item.photoKey == null ? 3 : 1.25,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Opacity(
                    opacity: item.inStock ? 1 : 0.5,
                    child: item.photoKey == null
                        ? NoPhotoPanel(
                            name: item.name,
                            accent: accent == ShopStyle.ink ? null : accent)
                        : ColoredBox(
                            color: ShopStyle.stone,
                            child: _Photo(
                                photoKey: item.photoKey,
                                capture: capture,
                                label: 'Photo de ${item.name}'),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(item.name,
                style: const TextStyle(
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: ShopStyle.ink)),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(priceOf(money, item),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink)),
                const SizedBox(width: 10),
                Text(
                    item.isPreorder
                        ? preorderLine(item)
                        : item.inStock
                            ? 'En stock'
                            : 'Épuisé',
                    style: const TextStyle(fontSize: 14, color: ShopStyle.mist)),
              ],
            ),
            if (item.hasDescription) ...[
              const SizedBox(height: 12),
              Text(item.description!,
                  style: const TextStyle(
                      fontSize: 15, height: 1.45, color: ShopStyle.ink)),
            ],
            const SizedBox(height: 20),
            if (item.inStock)
              count == 0
                  ? SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onAdd,
                        child: const Text('Ajouter au panier'),
                      ),
                    )
                  : Row(
                      children: [
                        _Stepper(
                            name: item.name,
                            count: count,
                            onAdd: onAdd,
                            onRemove: onRemove),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('$count dans le panier',
                              style: const TextStyle(
                                  fontSize: 15, color: ShopStyle.ink)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Continuer'),
                        ),
                      ],
                    ),
            if (ask != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onOpen(ask),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('Poser une question sur WhatsApp'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One half of the stepper on a basketed tile. 40 px a side: the icon is
/// small so the chip stays quiet on the photo, but the target under the
/// thumb is not — a plus you keep missing is a basket you give up on.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: Icon(icon, size: 16, color: ShopStyle.paper)),
        ),
      ),
    );
  }
}

/// The article's photo, fetched once through the public read and held for
/// the life of the tile — a rebuild must not refetch a picture on a slow link.
class _Photo extends StatefulWidget {
  const _Photo({
    required this.photoKey,
    required this.capture,
    this.label = "Photo de l'article",
    this.fit = BoxFit.cover,
    this.lean = true,
  });

  final String? photoKey;
  final CaptureRepository capture;
  final String label;

  /// A logo is shown whole (contain); a photo fills its square (cover).
  final BoxFit fit;

  /// Whether a photo leans in under the pointer; a thumbnail holds still.
  final bool lean;

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
        final image =
            Image.memory(bytes, fit: widget.fit, semanticLabel: widget.label);
        // A product photograph leans in under the pointer; a logo, shown
        // whole, holds still.
        if (widget.fit != BoxFit.cover || !widget.lean) return image;
        return ClipRect(child: ZoomOnHover(child: image));
      },
    );
  }
}


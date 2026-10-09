import 'dart:async';
import '../notify/notifications_screen.dart' show ShopperBell;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/whatsapp_phone.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/nav/session.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/retail/stock_rule.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/theme/motion.dart';
import '../../core/theme/mara_mark.dart';
import '../common/owned_controller.dart';
import '../shopper/follow_heart.dart';
import '../shopper/shopper_profile_screen.dart' show addressName;
import 'lazy_photo.dart';
import 'open_badge.dart';
import 'order_sign_in_sheet.dart';
import 'shop_skeleton.dart';
import 'share_vitrine.dart';
import 'shop_style.dart';
import 'whatsapp_verify_screen.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../common/keyboard_sheet.dart';

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
    this.whatsApp,
    this.shopper,
  });

  final String slug;
  final StorefrontRepository storefront;

  /// The shopper's own (113): the ♥ on the band, and the order sheet's
  /// saved addresses and preferred payment. Null: neither.
  final ShopperRepository? shopper;

  /// The shopper's number, proved on WhatsApp before an order when the
  /// platform asks (109). Null: Supabase's, through the session's client.
  final WhatsAppPhone? whatsApp;

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
    // « Commandes fermées » (110): a showcase keeps no basket.
    if (_shop?.style.ordersClosed ?? false) return;
    final raw = await widget.session.db.readPref(_basketKey);
    if (raw == null || !mounted) return;
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final onShelf = {for (final i in items) i.id: i};
      setState(() {
        for (final e in saved.entries) {
          var q = (e.value as num).toDouble();
          final item = onShelf[e.key];
          // No more than is left now (101), and nothing of « Épuisé ».
          final cap = item?.stockLeft;
          if (cap != null && q > cap) q = cap.floorToDouble();
          if (item != null && !item.inStock) q = 0;
          if (q > 0 && item != null) _basket[e.key] = q;
        }
      });
    } catch (_) {
      // A basket that cannot be read is an empty basket, not an error.
    }
  }

  void _keepBasket() {
    final db = widget.session.db;
    unawaited(
      db.writePref(_basketKey, _basket.isEmpty ? null : jsonEncode(_basket)),
    );
  }

  /// The shelf filter: instant, on the list already fetched, accent-blind
  /// like the street's search — at forty articles three typed letters beat
  /// any amount of scrolling, and it costs no network at all.
  final _filter = TextEditingController();

  List<PublicItem> get _visible {
    final q = foldSearchText(_filter.text.trim());
    if (q.isEmpty) return _items;
    return _items.where((i) => foldSearchText(i.name).contains(q)).toList();
  }

  /// The ♥ on the band (113), known once the shopper is signed in.
  late final Follows _follows = Follows(widget.shopper);
  bool? _signedIn;

  void _followsFor() {
    final phase = widget.session.phase;
    final inside = phase == SessionPhase.noOrg ||
        phase == SessionPhase.picking ||
        phase == SessionPhase.ready;
    if (inside == _signedIn) return;
    _signedIn = inside;
    unawaited(_follows.load());
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _followsFor();
    _load();
    unawaited(_forgetAbandonedSignIn());
  }

  /// Back on this vitrine still signed out — « Se connecter autrement » or
  /// « Créer un compte », then back without signing in: the way back and
  /// the order to resume are forgotten, so a sign-in later (from anywhere,
  /// within the half hour) brings no surprise order sheet. A Google sign-in
  /// in flight is never signed out here: on a phone the vitrine stays open
  /// under the browser (no new visit), on the web the reload boots first.
  Future<void> _forgetAbandonedSignIn() async {
    if (widget.session.phase != SessionPhase.signedOut) return;
    final db = widget.session.db;
    try {
      final raw = await db.readPref(_resumeKey);
      if (raw != null && (raw == widget.slug || raw.startsWith('${widget.slug}|'))) {
        await db.writePref(_resumeKey, null);
      }
    } catch (_) {}
    if (widget.session.phase != SessionPhase.signedOut) return;
    final stashed = widget.session.takeReturnTo();
    if (stashed != null && stashed != Routes.storefront(widget.slug)) {
      widget.session.stashReturnTo(stashed);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _follows.dispose();
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
        _error = context.tr('La vitrine a besoin d\'une connexion.');
        _loading = false;
      });
      return;
    }
    // The shop as this phone last saw it, at once (street_cache.dart): on
    // a slow line the shelf shows while the fresh answer comes.
    final kept = _shop == null ? await widget.storefront.keptVitrine(widget.slug) : null;
    if (kept != null && mounted && _shop == null) {
      setState(() {
        _shop = kept.shop;
        _showcase = kept.showcase;
        _items = _shelfOf(kept.shop, kept.items, kept.showcase);
        _loading = false;
      });
    }
    try {
      // The three questions at once: on 3G each is a round trip of half a
      // second and more, and the shelf used to wait for them in turn.
      final asked = widget.storefront.shop(widget.slug);
      final showcases = widget.storefront.showcaseSlugs();
      final shelfAsked = widget.storefront.items(widget.slug)
        // Its failure is heard below, or not at all when the shop failed
        // first — never as an error nobody caught.
        ..ignore();
      final shop = await asked;
      // A vitrine d'exemple (094): browsed, never ordered from.
      final showcase = shop != null && (await showcases).contains(shop.slug);
      final items = shop == null ? const <PublicItem>[] : await shelfAsked;
      final keptAt = widget.storefront.keptAt;
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _showcase = showcase;
        _items = shop == null ? const [] : _shelfOf(shop, items, showcase);
        _loading = false;
      });
      // No network: the last look, said as such.
      if (keptAt != null) _sayKept();
      // The street's counter (071): a window opened. Never in the way.
      if (shop != null) {
        unawaited(widget.storefront.recordVisit(widget.slug, 'opened'));
        unawaited(_countVisitor());
      }
      await _restoreBasket(items);
      unawaited(_resumeOrder());
    } catch (error) {
      if (!mounted) return;
      if (_shop != null) {
        // The last look is on screen: it stays, said as such.
        _sayKept();
        await _restoreBasket(_items);
        return;
      }
      setState(() {
        _error = context.tr(
          'La vitrine n\'a pas pu être chargée. Vérifiez le réseau.',
        );
        _loading = false;
      });
    }
  }

  /// The shelf in the order the street shows it.
  static List<PublicItem> _shelfOf(PublicShop shop, List<PublicItem> items, bool showcase) {
    // A Pro shop's shelf order (068): pinned first, out-of-stock left off
    // when it asked. The street reads it, the shop set it.
    final arranged = shop.style.arrange(items);
    // A vitrine d'exemple shows its photographed articles first (095).
    return showcase
        ? [
            ...arranged.where((i) => i.photoKey != null),
            ...arranged.where((i) => i.photoKey == null),
          ]
        : arranged;
  }

  void _sayKept() {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(context.tr('Pas de réseau — la vitrine de votre dernière visite')),
      ));
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
    if (_shop?.style.ordersClosed ?? false) return;
    // No more than is left on the shelf (101): the stepper stops there. The
    // window says how many only when few are left (« Plus que 3 »); with
    // more, the count stays the shop's and the stepper just stops.
    final cap = item.stockLeft;
    if (cap != null && (_basket[item.id] ?? 0) + 1 > cap) {
      if (cap > 0 && cap <= 5) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(context.tr('Plus que {n}', {'n': stockQty(cap)})),
          ));
      }
      return;
    }
    if ((_basket[item.id] ?? 0) == 0) {
      unawaited(
        widget.storefront.recordVisit(widget.slug, 'added', productId: item.id),
      );
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

  double get _total =>
      _items.fold(0, (sum, i) => sum + (_basket[i.id] ?? 0) * i.price);

  int get _count => _basket.values.fold(0, (sum, q) => sum + q.round());

  /// Only services in the basket (098): a booking, said as one.
  bool get _booking {
    final picked = [
      for (final i in _items)
        if ((_basket[i.id] ?? 0) > 0) i,
    ];
    return picked.isNotEmpty && picked.every((i) => i.isService);
  }

  /// "Commander": the one act that needs a name. A stranger is sent through
  /// sign-in and brought back to this very vitrine — and the basket now
  /// survives the trip: it sleeps on the device (_keepBasket) and is
  /// restored when the page comes back, so the picking is done once.
  /// A vitrine d'exemple (094): the shopper may look and fill a basket;
  /// the order is refused here, before any sign-in, and by the server too.
  bool _showcase = false;

  Future<void> _farAway() => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      key: const Key('showcase-far'),
      icon: const Icon(Icons.location_off_outlined),
      title: Text(dialog.tr('Pas à proximité')),
      content: Text(
        dialog.tr(
          'Cette boutique ne prend pas de commandes près de chez vous. C\'est une vitrine d\'exemple de Mara : regardez, inspirez-vous, et commandez dans les boutiques de votre quartier.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: Text(dialog.tr('Compris')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialog);
            _directory();
          },
          child: Text(dialog.tr('Voir les autres vitrines')),
        ),
      ],
    ),
  );

  late final WhatsAppPhone _phone =
      widget.whatsApp ?? SupabaseWhatsAppPhone(widget.session.auth.client);

  /// The server's answer about the shopper's number (109), once asked.
  OrderPhoneGate? _gate;

  /// The shopper's saved addresses and preferred payment (113), once asked
  /// per visit. No answer in time (or no repository): the sheet as before.
  ShopperProfile? _mine;

  Future<void> _askMine() async {
    final shopper = widget.shopper;
    if (shopper == null || !shopper.isConfigured) return;
    try {
      _mine = await shopper.profile().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// F1: an order a stranger began, kept on the device while they sign in
  /// (on the web, Google comes back as a reload): `slug|when`. Back
  /// signed in within half an hour, on this vitrine with its basket, the
  /// order opens again by itself.
  static const _resumeKey = 'street_order_after_sign_in';
  static const _resumeFresh = Duration(minutes: 30);
  bool _resuming = false;

  void _onSession() {
    if (!mounted) return;
    _followsFor();
    unawaited(_resumeOrder());
  }

  Future<void> _resumeOrder() async {
    if (_resuming || _loading || _shop == null || _basket.isEmpty || _showcase) {
      return;
    }
    final phase = widget.session.phase;
    if (phase == SessionPhase.signedOut ||
        phase == SessionPhase.booting ||
        phase == SessionPhase.resolving) {
      return;
    }
    _resuming = true;
    try {
      final db = widget.session.db;
      String? raw;
      try {
        raw = await db.readPref(_resumeKey);
      } catch (_) {}
      if (raw == null || !mounted) return;
      final cut = raw.indexOf('|');
      final slug = cut < 0 ? raw : raw.substring(0, cut);
      final at = cut < 0 ? null : DateTime.tryParse(raw.substring(cut + 1));
      if (slug != widget.slug) return;
      if (at == null || DateTime.now().difference(at) > _resumeFresh) {
        await db.writePref(_resumeKey, null);
        return;
      }
      // Something opened over the vitrine (an article, a sheet): not now.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final inside = phase == SessionPhase.noOrg ||
          phase == SessionPhase.picking ||
          phase == SessionPhase.ready;
      if (inside) {
        await db.writePref(_resumeKey, null);
        // The vitrine left itself as the way back from sign-in. Back here
        // without the router taking it (Google on a phone returns to this
        // very page), it must not send the shopper here again later.
        final stashed = widget.session.takeReturnTo();
        if (stashed != null && stashed != Routes.storefront(widget.slug)) {
          widget.session.stashReturnTo(stashed);
        }
      }
      if (!mounted) return;
      // Inside: the order sheet. At a gate still (the code to choose or to
      // type): the gate, then back here.
      await _order();
    } finally {
      _resuming = false;
    }
  }

  /// « Commander » signed out (F1): Google first, the two other doors at
  /// the bottom. The basket is already on the device; the way back is this
  /// vitrine, and the order opens again once they are in (_resumeOrder).
  Future<void> _askSignIn() async {
    final choice = await showOrderSignInSheet(
      context,
      booking: _booking,
      googleAvailable: widget.session.auth.googleAvailable,
    );
    if (choice == null || !mounted) return;
    try {
      await widget.session.db.writePref(
        _resumeKey,
        '${widget.slug}|${DateTime.now().toIso8601String()}',
      );
    } catch (_) {}
    if (!mounted) return;
    widget.session.stashReturnTo(Routes.storefront(widget.slug));
    switch (choice) {
      case OrderSignIn.google:
        final messenger = ScaffoldMessenger.of(context);
        try {
          await widget.session.signInWithGoogle();
        } catch (error) {
          messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
        }
      case OrderSignIn.otherWay:
        context.go(Routes.signIn);
      case OrderSignIn.newAccount:
        context.go('${Routes.signIn}?compte=nouveau');
    }
  }

  Future<void> _order() async {
    if (_showcase) return _farAway();
    switch (widget.session.phase) {
      case SessionPhase.signedOut:
        return _askSignIn();
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

    // 109: a number proved on WhatsApp first, when the platform asks for
    // one (Réglages › « Numéro WhatsApp vérifié avant de commander », off
    // as installed). No answer — no signal, a database before 109 — asks
    // nothing here; the server still decides at the order.
    // Asked once per visit (one round trip on a slow network), the
    // button turning while it is; a refusal at the order asks again.
    var gate = _gate;
    if (gate == null) {
      if (_sending) return;
      setState(() => _sending = true);
      try {
        // The shopper's addresses and payment (113), asked beside the gate:
        // one wait, not two.
        final mine = _mine == null ? _askMine() : null;
        gate = await _phone.gate();
        if (mine != null) await mine;
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      if (!mounted) return;
      _gate = gate;
    }
    if (gate != null && gate.mustVerify) {
      final proved = await Navigator.of(context).push(WhatsAppVerifyScreen.route(_phone));
      if (proved == null || !mounted) return;
      gate = _gate = OrderPhoneGate(required: true, verified: true, phone: proved);
    }
    if (!mounted) return;

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
          provedPhone: gate != null && gate.required ? gate.phone : null,
          addresses: _mine?.addresses ?? const [],
          preferredPayment: _mine?.payment ?? 'cash',
          onSubmit: _send,
          quote: (lat, lng) =>
              widget.storefront.deliveryCheck(widget.slug, lat: lat, lng: lng),
        ),
      ),
    );
    if (sent == true && mounted) {
      final booking = _booking;
      setState(_basket.clear);
      _keepBasket(); // The promise is kept; the device forgets it.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            booking
                ? context.tr(
                    'Demande envoyée. Vous recevrez la réponse ici, avec le rendez-vous.',
                  )
                : context.tr('Commande envoyée. La boutique vous répondra ici.'),
          ),
        ),
      );
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
      if (!mounted) return null;
      // 109's refusal: the switch was turned on since the answer was read.
      if (e.message == 'Vérifiez d\'abord votre numéro WhatsApp') _gate = null;
      // Said in the reader's language when the app has the sentence (098's
      // « Un service se réserve sur rendez-vous… », say).
      // A stock refusal (101) carries its own code, MA001.
      return e.code == 'P0001' || e.code == stockRefusalCode
          ? (stockShortText(context.trLanguage, e.message) ?? context.tr(e.message))
          : context.tr(
              'La commande n\'a pas pu être envoyée. Vérifiez le réseau.',
            );
    } catch (_) {
      if (!mounted) return null;
      return context.tr(
        'La commande n\'a pas pu être envoyée. Vérifiez le réseau.',
      );
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
      booking: _booking,
      total: moneyFormat(_shop?.currency ?? 'XOF').format(_total),
      sending: _sending,
      onOrder: _order,
    );
    final shop = _shop;

    return ShopPage(
      title: shop?.name ?? context.tr('Vitrine'),
      announcements: switch (shop?.profile) {
        // « Commandes en ligne » hidden by Mara (110): a showcase, said first.
        _ when shop?.style.ordersClosed ?? false => [
          context.tr('Commandes fermées pour le moment'),
          context.tr('Regardez la vitrine, appelez ou écrivez sur WhatsApp'),
        ],
        'farm' => ShopPage.farm,
        // An association's window (098): its services, booked.
        'association' || 'church' => [
          context.tr('Réservez en ligne, sur rendez-vous'),
          context.tr('Une association de chez vous, tenue par ses membres'),
          context.tr('Rien à payer en ligne : vous réglez sur place'),
        ],
        _ => ShopPage.street,
      },
      // A Pro shop's button colour (068) — the order bar, WhatsApp, the
      // stepper — decided by the shop, read by the street.
      accent: shop?.style.accent,
      leading: IconButton(
        tooltip: context.tr('Toutes les vitrines'),
        icon: const Icon(Icons.arrow_back),
        onPressed: _directory,
      ),
      // The shopper's bell (115), once signed in.
      trailing: const ShopperBell(),
      overlay: _basket.isEmpty || _inlineShown
          ? null
          : basketBar(floating: true),
      body: _loading
          ? const ShopSkeleton.shelf()
          : _error != null
          ? ShopNotice(
              text: _error!,
              action: OutlinedButton(
                onPressed: _load,
                child: Text(context.tr('Réessayer')),
              ),
            )
          : shop == null
          ? ShopNotice(
              text: "Cette vitrine n'existe pas, ou n'est pas ouverte.",
              action: OutlinedButton(
                onPressed: _directory,
                child: Text(context.tr('Voir les autres vitrines')),
              ),
            )
          : NotificationListener<ScrollNotification>(
              // Measured once the scrolled frame is laid out: during
              // the notification the page has not moved yet.
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _checkInline(),
                );
                return false;
              },
              child: _OrdersClosed(
                closed: shop.style.ordersClosed,
                child: _Window(
                basketCard: _basket.isEmpty
                    ? null
                    : KeyedSubtree(
                        key: _inlineBasket,
                        child: basketBar(floating: false),
                      ),
                shop: shop,
                heart: FollowHeart(follows: _follows, slug: shop.slug),
                showcase: _showcase,
                items: _visible,
                totalCount: _items.length,
                serviceCount: _items.where((i) => i.isService).length,
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
    unawaited(
      widget.storefront.recordVisit(widget.slug, 'opened', productId: item.id),
    );
    await showShopSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Theme(
        data: ShopStyle.theme(sheet, accent: shop.style.accent),
        child: StatefulBuilder(
          builder: (sheet, setSheet) => _OrdersClosed(
            closed: shop.style.ordersClosed,
            child: ArticleSheet(
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
    this.booking = false,
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

  /// Only services picked (098): « 2 services », « Réserver ».
  final bool booking;
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
              Text(
                context.tr('VOTRE PANIER'),
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: ShopStyle.ink,
                ),
              ),
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
                    capture: capture,
                  );
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
                      Text(
                        booking
                            ? context.tr(
                                count > 1 ? '{n} services' : '{n} service',
                                {'n': count},
                              )
                            : context.tr(
                                count > 1 ? '{n} articles' : '{n} article',
                                {'n': count},
                              ),
                        style: const TextStyle(
                          fontSize: 13,
                          color: ShopStyle.mist,
                        ),
                      ),
                      Text(
                        total,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ShopStyle.ink,
                        ),
                      ),
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
                            strokeWidth: 2,
                            color: ShopStyle.paper,
                          ),
                        )
                      : Text(
                          booking
                              ? context.tr('Réserver')
                              : context.tr('Commander'),
                        ),
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
                            color: ShopStyle.mist,
                          ),
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
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: ShopStyle.ink),
            ),
          ),
          if (qty > 1)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                context.tr('×{qty}', {'qty': qty}),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ShopStyle.mist,
                ),
              ),
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
    this.provedPhone,
    this.addresses = const [],
    this.preferredPayment = 'cash',
  });

  /// The number WhatsApp proved (109), when the platform asks for one: it
  /// is the order's number, said instead of the optional field.
  final String? provedPhone;

  /// The shopper's saved places (113): offered, the first one picked, once
  /// « Livraison » is chosen. Empty: the field as before.
  final List<SavedAddress> addresses;

  /// 'wave' (113, only while the platform allows it) makes Wave the
  /// sheet's first choice where the vitrine takes it; 'cash' otherwise.
  final String preferredPayment;

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
  })
  onSubmit;

  /// What a delivery to a pin would cost and whether the shop goes that far
  /// (061, 069) — asked the moment the customer pins their door, so the
  /// answer is on the sheet before "Commander".
  final Future<DeliveryCheck?> Function(double lat, double lng) quote;

  @override
  State<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<OrderSheet> {
  String _fulfilment = 'pickup';
  late String _payment =
      widget.waveMerchant != null && widget.preferredPayment == 'wave' ? 'wave' : 'cash';

  /// The saved address picked (113), by its index in [OrderSheet.addresses].
  int? _picked;

  /// « Livraison » chosen: the first saved address, if the field is empty.
  void _chooseFulfilment(String f) {
    setState(() => _fulfilment = f);
    if (f == 'delivery' &&
        _picked == null &&
        _address.text.trim().isEmpty &&
        widget.addresses.isNotEmpty) {
      _useAddress(0);
    }
  }

  /// One saved address on the sheet: its words and note in the field, its
  /// pin for the courier and the price.
  void _useAddress(int i) {
    final a = widget.addresses[i];
    setState(() {
      _picked = i;
      _address.text = a.forOrder;
      _dropLat = a.lat;
      _dropLng = a.lng;
    });
    unawaited(_refreshQuote());
  }

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
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Sans votre position, l\'adresse écrite suffit.'),
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
        _dropLat = position.latitude;
        _dropLng = position.longitude;
      });
      await _refreshQuote();
    } catch (_) {
      if (!mounted) return;
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
            // The keyboard up on a small phone: the dialog scrolls (A6).
            scrollable: true,
            title: Text(context.tr('Lien Google Maps')),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: context.tr(
                  'https://www.google.com/maps/...@12.37,-1.52,17z',
                ),
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
      ),
    );
    if (text == null || !mounted) return;
    final position = parseGoogleMapsLink(text);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Ce lien ne contient pas de position. Ouvrez-le dans Google Maps et copiez l\'adresse complète.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _dropLat = position.lat;
      _dropLng = position.lng;
    });
    await _refreshQuote();
  }

  /// Only services in the basket (098): a booking. Nothing travels, so no
  /// delivery is offered; the day and time wanted are what the shop needs.
  bool get _booking {
    final picked = [
      for (final item in widget.items)
        if ((widget.basket[item.id] ?? 0) > 0) item,
    ];
    return picked.isNotEmpty && picked.every((i) => i.isService);
  }

  Future<void> _submit() async {
    if (_booking && _note.text.trim().isEmpty) {
      setState(
        () => _error = context.tr(
          'Dites quel jour et à quelle heure vous souhaitez venir.',
        ),
      );
      return;
    }
    if (_fulfilment == 'delivery' && _address.text.trim().isEmpty) {
      setState(() => _error = context.tr('Indiquez où livrer.'));
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
      phone: widget.provedPhone != null || _phone.text.trim().isEmpty
          ? null
          : _phone.text.trim(),
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
    final km = _distanceKm == null
        ? ''
        : ' (${_distanceKm!.toStringAsFixed(1)} km';
    final max = _maxKm == null
        ? (km.isEmpty ? '' : ')')
        : '${km.isEmpty ? ' (' : ', '}livraison jusqu\'à ${_maxKm!.toStringAsFixed(0)} km)';
    return context.tr(
      'Cette boutique ne livre pas aussi loin{km}{max}. Choisissez le retrait en boutique.',
      {'km': km, 'max': max},
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(widget.currency);
    final lines = [
      for (final item in widget.items)
        if ((widget.basket[item.id] ?? 0) > 0) item,
    ];
    final total = lines.fold<double>(
      0,
      (sum, i) => sum + widget.basket[i.id]! * i.price,
    );
    final booking = _booking;
    final note = TextField(
      key: const Key('order-note'),
      controller: _note,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: booking
            ? context.tr('Date et heure souhaitées')
            : context.tr('Un mot pour la boutique (facultatif)'),
        hintText: booking
            ? context.tr('Samedi 10 h, ou dès que possible')
            : null,
      ),
    );

    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      // The fields scroll; the button stays above the keyboard (A6).
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || (_fulfilment == 'delivery' && _tooFar)
                    ? null
                    : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ShopStyle.paper,
                        ),
                      )
                    : Text(
                        booking
                            ? context.tr('Envoyer la réservation')
                            : context.tr('Envoyer la commande'),
                      ),
              ),
            ),
        ],
      ),
      children: [
            Text(
              booking
                  ? context.tr('Votre réservation')
                  : context.tr('Votre commande'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ShopStyle.ink,
              ),
            ),
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
                          fontSize: 15,
                          color: ShopStyle.ink,
                        ),
                      ),
                    ),
                    Text(
                      money.format(widget.basket[item.id]! * item.price),
                      style: const TextStyle(
                        fontSize: 14,
                        color: ShopStyle.mist,
                      ),
                    ),
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
                  Expanded(
                    child: Text(
                      context.tr('Livraison'),
                      style: const TextStyle(
                        fontSize: 15,
                        color: ShopStyle.ink,
                      ),
                    ),
                  ),
                  if (_quoting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      !_feeKnown
                          ? context.tr('épinglez votre porte pour le prix')
                          : _tooFar
                          ? context.tr('trop loin')
                          : _fee == null
                          ? context.tr('à discuter avec la boutique')
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
                            : ShopStyle.ink,
                      ),
                    ),
                ],
              ),
              if (_tooFar) ...[
                const SizedBox(height: 4),
                Text(
                  _tooFarSentence,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Total'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ShopStyle.ink,
                    ),
                  ),
                ),
                Text(
                  money.format(
                    total +
                        (_fulfilment == 'delivery' && !_tooFar
                            ? (_fee ?? 0)
                            : 0),
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ShopStyle.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // A booking (098): « Sur rendez-vous », said where the way the
            // goods travel would be chosen.
            if (booking)
              Row(
                key: const Key('order-appointment'),
                children: [
                  const Icon(
                    Icons.event_available_outlined,
                    size: 22,
                    color: ShopStyle.ink,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('Sur rendez-vous'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink,
                      ),
                    ),
                  ),
                ],
              )
            else if (widget.delivers)
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'pickup',
                    label: Text(context.tr('Retrait')),
                    icon: const Icon(Icons.storefront_outlined),
                  ),
                  ButtonSegment(
                    value: 'delivery',
                    label: Text(context.tr('Livraison')),
                    icon: const Icon(Icons.delivery_dining_outlined),
                  ),
                ],
                selected: {_fulfilment},
                onSelectionChanged: (s) => _chooseFulfilment(s.first),
              ),
            // RULE M, as the coordinator settled it (113): the order sheet
            // follows the vitrine's own Wave — the storefront hands a Wave
            // link only where the platform ticked « Wave autorisé » for that
            // business (090's wave_allowed) and 110's « Paiement en ligne »
            // is not hidden: that IS Mara allowing mobile payment for that
            // vitrine. The platform-wide switch (076's wave_checkout, «
            // Payer en ligne par Wave ») governs the shopper profile's
            // « Paiement préféré » and the courier's payout number instead.
            // The profile's Wave preference only picks the first choice
            // here; it never draws Wave where the vitrine does not take it.
            if (widget.waveMerchant != null) ...[
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'cash',
                    label: Text(context.tr('Espèces')),
                    icon: const Icon(Icons.payments_outlined),
                  ),
                  ButtonSegment(
                    value: 'wave',
                    label: Text(context.tr('Wave')),
                    icon: const Icon(Icons.phone_iphone_outlined),
                  ),
                ],
                selected: {_payment},
                onSelectionChanged: (s) => setState(() => _payment = s.first),
              ),
            ],
            if (_fulfilment == 'delivery') ...[
              // The shopper's saved places (113), one tap each.
              if (widget.addresses.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  key: const Key('order-addresses'),
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < widget.addresses.length; i++)
                      ChoiceChip(
                        key: Key('order-address-$i'),
                        avatar: Icon(
                          switch (widget.addresses[i].kind) {
                            'home' => Icons.home_outlined,
                            'work' => Icons.work_outline,
                            _ => Icons.place_outlined,
                          },
                          size: 18,
                        ),
                        label: Text(addressName(context, widget.addresses[i])),
                        selected: _picked == i,
                        onSelected: (_) => _useAddress(i),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const Key('order-address'),
                controller: _address,
                onChanged: (_) {
                  if (_picked != null) setState(() => _picked = null);
                },
                decoration: InputDecoration(
                  labelText: context.tr('Où livrer ?'),
                  hintText: context.tr('Quartier, repère, en face de…'),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, size: 16),
                      label: Text(context.tr('Épingler ma position')),
                    ),
                    TextButton(
                      onPressed: _pasteMapsLink,
                      child: Text(context.tr('Lien Google Maps')),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 18,
                      color: ShopStyle.ink,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr('Position épinglée pour le livreur'),
                        style: const TextStyle(
                          fontSize: 14,
                          color: ShopStyle.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Retirer'),
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
            // A booking asks first for the day and the hour (098).
            if (booking) ...[const SizedBox(height: 12), note],
            const SizedBox(height: 12),
            if (widget.provedPhone != null)
              Row(
                key: const Key('order-proved-phone'),
                children: [
                  const Icon(Icons.verified_outlined, size: 20, color: maraGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('Votre numéro WhatsApp vérifié : {phone}', {
                        'phone': widget.provedPhone,
                      }),
                      style: const TextStyle(fontSize: 14, color: ShopStyle.ink),
                    ),
                  ),
                ],
              )
            else
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.tr('Votre numéro (facultatif)'),
                  hintText: '+226 70 00 00 00',
                ),
              ),
            if (!booking) ...[const SizedBox(height: 12), note],
            const SizedBox(height: 6),
            Text(
              booking && _payment != 'wave'
                  ? context.tr(
                      'Rien à payer maintenant : vous payez sur place, au rendez-vous.',
                    )
                  : _payment == 'wave'
                  ? context.tr(
                      'Rien à payer maintenant : dès que la boutique accepte, un bouton Wave apparaît dans Mes commandes.',
                    )
                  : context.tr(
                      'Rien à payer maintenant : vous payez à la boutique, au retrait ou à la livraison.',
                    ),
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
            ),
      ],
    );
  }
}

class _Window extends StatelessWidget {
  const _Window({
    this.basketCard,
    required this.shop,
    this.heart,
    this.showcase = false,
    required this.items,
    required this.totalCount,
    this.serviceCount = 0,
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

  /// ♥, beside the name (113): follow this vitrine.
  final Widget? heart;

  /// A vitrine d'exemple (094): « Pas à proximité » under the name.
  final bool showcase;
  final List<PublicItem> items;

  /// How many articles the window really holds — [items] is the filtered
  /// view of them.
  final int totalCount;

  /// How many of them are services (098).
  final int serviceCount;
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
    // « Grandes photos » (093, Pro): half as many columns, never fewer than one.
    final shelfColumns = style.layout == VitrineLayout.large
        ? (columns ~/ 2).clamp(1, 3)
        : columns;
    final wide = width >= 560;
    // The goods and the services (098), each in its own section.
    final goods = [
      for (final i in items)
        if (!i.isService) i,
    ];
    final services = [
      for (final i in items)
        if (i.isService) i,
    ];
    final goodsTotal = totalCount - serviceCount;
    final showGoods = goodsTotal > 0
        ? goods.isNotEmpty || items.isEmpty
        : serviceCount == 0;
    final showServices = serviceCount > 0 && (services.isNotEmpty || !showGoods);
    // The shelf filter, once the window is long enough to need one — on
    // six articles a search box is furniture. One fixed place above both
    // sections, so a query that empties one of them does not move the
    // field (and take the keyboard away) mid-word.
    final filterBox = <Widget>[
      if (totalCount > 6) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            key: const Key('shelf-filter'),
            controller: filter,
            onChanged: onFilterChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.tr('Chercher dans la boutique…'),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: filter.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.tr('Effacer'),
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
                borderSide: const BorderSide(color: ShopStyle.ink, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    ];
    final noMatch = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'Aucun article ne répond à « ${filter.text.trim()} » '
        'dans cette boutique.',
        style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
      ),
    );

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
                label: context.tr('Photo de {name}', {'name': shop.name}),
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
                horizontal: 20,
                vertical: wide ? 40 : 24,
              ),
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
                            label: context.tr('Logo de {name}', {
                              'name': shop.name,
                            }),
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
                      ?heart,
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
                      child: Text(
                        blurb,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.45,
                          color: ShopStyle.ink,
                        ),
                      ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC49A6C),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        style.topWeekRank == 1
                            ? context.tr('🏆 1er de la semaine')
                            : context.tr('🏆 Top 3 de la semaine'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0E0D0C),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    [
                      _kindOf(shop.profile),
                      if (address.isNotEmpty) address,
                      // A window of services alone (098): booked, not
                      // collected.
                      serviceCount > 0 && serviceCount == totalCount
                          ? context.tr('Sur rendez-vous')
                          : shop.delivers
                          ? context.tr('Retrait ou livraison')
                          : shop.profile == 'farm'
                          ? context.tr('Retrait à la ferme')
                          : context.tr('Retrait en boutique'),
                    ].join(' · '),
                    style: const TextStyle(fontSize: 14, color: ShopStyle.mist),
                  ),
                  // Opening hours (068; days and times since 093), the
                  // question every caller asks — in the reader's language.
                  if (style.schedule != null || style.hours != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_outlined,
                          size: 15,
                          color: ShopStyle.mist,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            style.schedule?.label(context.trLanguage) ??
                                style.hours!,
                            key: const Key('shop-hours'),
                            style: const TextStyle(
                              fontSize: 14,
                              color: ShopStyle.mist,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // The number itself (100): tapped, it opens the business's
                  // WhatsApp chat — wa.me reaches regular and Business
                  // WhatsApp alike. « Appeler » below still dials it.
                  if (whatsapp != null && phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    InkWell(
                      key: const Key('shop-phone'),
                      onTap: () => onOpen(whatsapp),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.chat_outlined,
                              size: 16,
                              color: maraGreen,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                phone,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: ShopStyle.ink,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            const Text(
                              ' · WhatsApp',
                              style: TextStyle(
                                fontSize: 14,
                                color: ShopStyle.mist,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // A vitrine d'exemple (094): far from everyone, said plainly.
                  if (showcase) ...[
                    const SizedBox(height: 10),
                    const FarBadge(key: Key('shop-far'), large: true),
                  ],
                  // « Commandes en ligne » hidden by Mara (110): a showcase —
                  // look, call, write; no basket.
                  if (style.ordersClosed) ...[
                    const SizedBox(height: 10),
                    const _ClosedBadge(key: Key('orders-closed')),
                  ],
                  // « Ouvert maintenant » / « Fermé » (093, Pro): the server
                  // reads the schedule against Ouagadougou's clock.
                  if (style.openNow != null) ...[
                    const SizedBox(height: 10),
                    OpenBadge(
                      key: const Key('shop-open'),
                      open: style.openNow!,
                      large: true,
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
                            child: Text(context.tr('Écrire sur WhatsApp')),
                          ),
                        if (phone.isNotEmpty)
                          OutlinedButton(
                            onPressed: () => onOpen('tel:$phone'),
                            child: Text(context.tr('Appeler')),
                          ),
                        // The way there, in the maps app the phone already
                        // has: turn-by-turn, no key, no bill (054).
                        if (shop.hasLocation)
                          OutlinedButton.icon(
                            onPressed: () =>
                                onOpen(directionsUrl(shop.lat!, shop.lng!)),
                            icon: const Icon(
                              Icons.directions_outlined,
                              size: 18,
                            ),
                            label: Text(context.tr('Itinéraire')),
                          ),
                        // A vitrine travels the way news does here: sent on
                        // WhatsApp from one phone to the next. The shop's
                        // customers are its advertisers.
                        OutlinedButton.icon(
                          key: const Key('shop-share'),
                          onPressed: () => ShareVitrine.open(
                            context,
                            shop: shop,
                            items: items,
                            capture: capture,
                          ),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: Text(context.tr('Partager')),
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
              // The filter first, searching both sections; then the goods,
              // then the services (098), each under its own word; a window
              // of services alone opens on them.
              ...filterBox,
              if (showGoods) ...[
                ShopSectionLabel(
                  'Les articles',
                  note: goodsTotal == 0
                      ? null
                      : goods.length == goodsTotal
                      ? '$goodsTotal article${goodsTotal > 1 ? 's' : ''}'
                      : context.tr('{length} sur {totalCount}', {
                          'length': goods.length,
                          'totalCount': goodsTotal,
                        }),
                ),
                if (goodsTotal > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    style.ordersClosed
                        ? context.tr('Touchez un article pour le voir.')
                        : context.tr(
                      'Touchez un article pour le voir, « + » pour l\'ajouter.',
                    ),
                    style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
                  ),
                ],
                const SizedBox(height: 18),
                if (totalCount == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      context.tr('Aucun article affiché pour le moment.'),
                      style: const TextStyle(
                        fontSize: 15,
                        color: ShopStyle.mist,
                      ),
                    ),
                  )
                else if (items.isEmpty)
                  noMatch
                else if (style.layout == VitrineLayout.list ||
                    style.layout == VitrineLayout.menu)
                  _rows(context, money, goods)
                else
                  _grid(
                    context,
                    money,
                    goods,
                    shelfColumns: shelfColumns,
                    wide: wide,
                  ),
              ],
              if (showServices) ...[
                if (showGoods) const SizedBox(height: 40),
                ShopSectionLabel(
                  context.tr('Services'),
                  key: const Key('shelf-services'),
                  note: services.length == serviceCount
                      ? context.tr(
                          serviceCount > 1 ? '{n} services' : '{n} service',
                          {'n': serviceCount},
                        )
                      : context.tr('{length} sur {totalCount}', {
                          'length': services.length,
                          'totalCount': serviceCount,
                        }),
                ),
                const SizedBox(height: 6),
                Text(
                  style.ordersClosed
                      ? context.tr('Touchez un service pour le voir.')
                      : context.tr(
                    'Touchez un service pour le voir, « Réserver » pour le choisir.',
                  ),
                  style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
                ),
                const SizedBox(height: 10),
                // One to a line, whatever the shelf's layout: a service is
                // read — its price, « à partir de », by the hour — more
                // than looked at, and « Réserver » needs its word.
                if (services.isEmpty) noMatch else _rows(context, money, services),
              ],
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

extension on _Window {
  /// « Liste » and « Menu » (093, Pro): one article to a line — a small
  /// photo, the name and the price for a list; the name, a dotted leader
  /// and the price for a menu, the way a maquis writes its board. The
  /// services (098) are always drawn this way.
  Widget _rows(BuildContext context, NumberFormat money, List<PublicItem> list) {
    final menu = shop.style.layout == VitrineLayout.menu;
    final services = list.isNotEmpty && list.first.isService;
    return Column(
      key: Key(
        services
            ? 'shelf-service-rows'
            : menu
            ? 'shelf-menu'
            : 'shelf-list',
      ),
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: ShopStyle.line),
          _ItemRow(
            item: list[i],
            menu: menu,
            money: money,
            capture: capture,
            quantity: basket[list[i].id] ?? 0,
            accent: shop.style.accent,
            onAdd: () => onAdd(list[i]),
            onRemove: () => onRemove(list[i]),
            onOpen: () => onDetails(list[i]),
          ),
        ],
      ],
    );
  }

  /// The common shelf: the photographs in a grid, the name and the price
  /// under each.
  Widget _grid(
    BuildContext context,
    NumberFormat money,
    List<PublicItem> list, {
    required int shelfColumns,
    required bool wide,
  }) {
    return LayoutBuilder(
      builder: (context, box) {
        final gap = wide ? 24.0 : 14.0;
        final cell =
            (box.maxWidth - gap * (shelfColumns - 1)) /
            shelfColumns;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: shelfColumns,
            crossAxisSpacing: gap,
            mainAxisSpacing: wide ? 28 : 20,
            // The cell is the square plus the text under it, added
            // up rather than guessed as a ratio: the ratio left a
            // band of empty space under every row on a phone (the
            // audit's screenshot), and clipped when names ran long.
            mainAxisExtent:
                cell +
                _ItemTile.textHeight(
                  context,
                  description: list.any((i) => i.hasDescription),
                  soldOut: list.any((i) => !i.inStock),
                ),
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final tile = Lift(
              // The photograph leans in (ZoomOnHover); the tile holds still.
              scale: 1.0,
              // Steady while the basket is open: a tile with the
              // stepper on it must not slide under the thumb.
              enabled: (basket[list[i].id] ?? 0) == 0,
              child: _ItemTile(
                item: list[i],
                money: money,
                capture: capture,
                quantity: basket[list[i].id] ?? 0,
                accent: shop.style.accent,
                onAdd: () => onAdd(list[i]),
                onRemove: () => onRemove(list[i]),
                onOpen: () => onDetails(list[i]),
              ),
            );
            // The entrance plays when the shelf appears — not on
            // every keystroke of the filter, which rebuilds these
            // tiles: a page that re-enters as you type flickers.
            if (filter.text.isNotEmpty) return tile;
            // Each row rises as the reader reaches it, the tiles of a
            // row a beat apart (the goods sites' collection grid).
            return ScrollReveal(
              delay: KajMotion.stagger(i % shelfColumns),
              child: tile,
            );
          },
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.menu,
    required this.money,
    required this.capture,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
    this.accent,
  });

  final PublicItem item;
  final bool menu;
  final NumberFormat money;
  final CaptureRepository capture;
  final double quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onOpen;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final count = quantity.round();
    final price = Text(
      priceOf(money, item, context.trLanguage),
      style: TextStyle(
        fontSize: menu ? 15 : 14,
        fontWeight: menu ? FontWeight.w700 : FontWeight.w600,
        color: ShopStyle.ink,
      ),
    );
    final name = Text(
      item.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: ShopStyle.ink,
      ),
    );
    final action = _OrdersClosed.of(context) && item.inStock
        ? const SizedBox.shrink()
        : !item.inStock
        ? Text(
            context.tr('Épuisé'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ShopStyle.mist,
            ),
          )
        : count > 0
        ? _Stepper(
            name: item.name,
            count: count,
            onAdd: onAdd,
            onRemove: onRemove,
          )
        : item.isService
        ? _BookButton(name: item.name, onAdd: onAdd)
        : _QuickAdd(name: item.name, onAdd: onAdd);
    return Semantics(
      container: true,
      button: true,
      label: [
        item.name,
        priceOf(money, item, context.trLanguage),
        if (!item.inStock) 'épuisé',
        if (count > 0) '$count dans le panier',
      ].join(', '),
      hint: "Voir l'article",
      onTap: onOpen,
      child: InkWell(
        onTap: onOpen,
        excludeFromSemantics: true,
        child: Opacity(
          opacity: item.inStock ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!menu) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: ExcludeSemantics(
                        // Too small for the name set large: its initial.
                        child: item.photoKey == null
                            ? ColoredBox(
                                color: (accent ?? ShopStyle.ink).withValues(
                                  alpha: 0.10,
                                ),
                                child: Center(
                                  child: Text(
                                    item.name.isEmpty
                                        ? '?'
                                        : item.name.characters.first
                                              .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: accent ?? ShopStyle.ink,
                                    ),
                                  ),
                                ),
                              )
                            : ColoredBox(
                                color: ShopStyle.stone,
                                child: _Photo(
                                  photoKey: item.photoKey,
                                  capture: capture,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (menu)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(child: name),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(6, 0, 6, 4),
                                  child: Text(
                                    '. . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: ShopStyle.mist,
                                    ),
                                  ),
                                ),
                              ),
                              price,
                            ],
                          )
                        else ...[
                          name,
                          const SizedBox(height: 3),
                          price,
                        ],
                        if (item.isPreorder)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              preorderLine(item),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: ShopStyle.ink,
                              ),
                            ),
                          ),
                        if (item.hasDescription)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              item.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: ShopStyle.mist,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                action,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The price as the street reads it: « 2 500 F / plateau » when the
/// business sells by a unit (083), the plain price otherwise.
/// A service's « à partir de » (098) goes before it: « à partir de 5 000 F
/// / heure ».
String priceOf(NumberFormat money, PublicItem item, [String lang = 'fr']) {
  final amount = item.priceFrom
      ? translate(lang, 'à partir de {price}', {
          'price': money.format(item.price),
        })
      : money.format(item.price);
  return item.unit == null ? amount : '$amount / ${item.unit}';
}

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
  static double textHeight(
    BuildContext context, {
    required bool description,
    required bool soldOut,
  }) {
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
      priceOf(money, item, context.trLanguage),
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
                                    photoKey: item.photoKey,
                                    capture: capture,
                                  ),
                                ),
                        ),
                      ),
                      if (item.inStock && !_OrdersClosed.of(context))
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: count > 0
                              ? _Stepper(
                                  name: item.name,
                                  count: count,
                                  onAdd: onAdd,
                                  onRemove: onRemove,
                                )
                              : _ShowOnHover(
                                  child: _QuickAdd(
                                    name: item.name,
                                    onAdd: onAdd,
                                  ),
                                ),
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
                        color: ShopStyle.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      priceOf(money, item, context.trLanguage),
                      style: const TextStyle(
                        fontSize: 14,
                        color: ShopStyle.mist,
                      ),
                    ),
                    if (item.isPreorder)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          preorderLine(item),
                          key: const Key('preorder-line'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ShopStyle.ink,
                          ),
                        ),
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
                            color: ShopStyle.mist,
                          ),
                        ),
                      ),
                    if (!item.inStock)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          context.tr('Épuisé'),
                          style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                            color: ShopStyle.mist,
                          ),
                        ),
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
  const NoPhotoPanel({
    super.key,
    required this.name,
    this.accent,
    this.large = false,
  });

  final String name;
  final Color? accent;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? ShopStyle.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(tint.withValues(alpha: 0.07), ShopStyle.stone),
        border: Border(
          left: BorderSide(color: tint.withValues(alpha: 0.55), width: 3),
        ),
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
              color: Color.alphaBlend(
                tint.withValues(alpha: 0.75),
                ShopStyle.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the vitrine below takes no order (110's « Commandes en ligne »
/// hidden): its rows, tiles and article sheet draw no « + », « Réserver »
/// or stepper.
class _OrdersClosed extends InheritedWidget {
  const _OrdersClosed({required this.closed, required super.child});

  final bool closed;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OrdersClosed>()?.closed ?? false;

  @override
  bool updateShouldNotify(_OrdersClosed old) => old.closed != closed;
}

/// « Commandes fermées pour le moment », under the vitrine's name.
class _ClosedBadge extends StatelessWidget {
  const _ClosedBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: maraDeep,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.storefront_outlined, size: 18, color: maraCaramel),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            context.tr('Commandes fermées pour le moment'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: maraPaper,
            ),
          ),
        ),
      ],
    ),
  );
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
      label: context.tr('Ajouter un {name} au panier', {'name': name}),
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

/// « Réserver » on a service's line (098): the word, not a « + » — booking
/// a lesson is not dropping a tin in a basket.
class _BookButton extends StatelessWidget {
  const _BookButton({required this.name, required this.onAdd});

  final String name;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: context.tr('Réserver {name}', {'name': name}),
      excludeSemantics: true,
      onTap: onAdd,
      child: FilledButton(
        key: const Key('book-service'),
        onPressed: onAdd,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const StadiumBorder(),
        ),
        child: Text(context.tr('Réserver')),
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
            icon: Icons.remove,
            label: context.tr('Retirer un {name}', {'name': name}),
            onTap: onRemove,
          ),
          ExcludeSemantics(
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ShopStyle.paper,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            label: context.tr('Ajouter un {name}', {'name': name}),
            onTap: onAdd,
          ),
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
    final ask = whatsappUrl(
      phone,
      text:
          'Bonjour $shopName, une question sur « ${item.name} » vu sur votre vitrine Mara.',
    );
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
                            accent: accent == ShopStyle.ink ? null : accent,
                          )
                        : ColoredBox(
                            color: ShopStyle.stone,
                            child: _Photo(
                              photoKey: item.photoKey,
                              capture: capture,
                              label: context.tr('Photo de {name}', {
                                'name': item.name,
                              }),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              item.name,
              style: const TextStyle(
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: ShopStyle.ink,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  priceOf(money, item, context.trLanguage),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: ShopStyle.ink,
                  ),
                ),
                Text(
                  item.isPreorder
                      ? preorderLine(item)
                      : item.isService
                      ? context.tr('Sur rendez-vous')
                      : item.inStock
                      ? context.tr('En stock')
                      : context.tr('Épuisé'),
                  style: const TextStyle(fontSize: 14, color: ShopStyle.mist),
                ),
              ],
            ),
            if (item.hasDescription) ...[
              const SizedBox(height: 12),
              Text(
                item.description!,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: ShopStyle.ink,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (item.inStock && !_OrdersClosed.of(context))
              count == 0
                  ? SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onAdd,
                        child: Text(
                          item.isService
                              ? context.tr('Réserver')
                              : context.tr('Ajouter au panier'),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        _Stepper(
                          name: item.name,
                          count: count,
                          onAdd: onAdd,
                          onRemove: onRemove,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.tr('{count} dans le panier', {
                              'count': count,
                            }),
                            style: const TextStyle(
                              fontSize: 15,
                              color: ShopStyle.ink,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(context.tr('Continuer')),
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
                  label: Text(context.tr('Poser une question sur WhatsApp')),
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
  @override
  Widget build(BuildContext context) {
    const placeholder = Center(
      child: Icon(Icons.image_outlined, size: 34, color: ShopStyle.line),
    );
    final key = widget.photoKey;
    if (key == null) return placeholder;
    // Asked for once near the screen, at the size it is drawn (lazy_photo):
    // a tile gets the Worker's small copy, not the 2000 px photograph.
    return LazyPhoto(
      load: (width) => widget.capture.publicObjectBytes(key, width: width),
      placeholder: placeholder,
      builder: (context, bytes, width) {
        final image = Image.memory(
          bytes,
          fit: widget.fit,
          // Decoded at the size it is drawn: a phone holds forty of these.
          cacheWidth: widget.fit == BoxFit.cover ? width : null,
          semanticLabel: widget.label,
        );
        // A product photograph leans in under the pointer; a logo, shown
        // whole, holds still.
        if (widget.fit != BoxFit.cover || !widget.lean) return image;
        return ClipRect(child: ZoomOnHover(child: image));
      },
    );
  }
}

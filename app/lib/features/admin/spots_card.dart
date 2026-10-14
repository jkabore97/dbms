import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/access/store_rules.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/pay/price_zone.dart';
import '../../core/pay/wave_pay.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../pay/wave_buttons.dart';
import '../account/support.dart';
import '../pro/store_billing.dart';
import '../pro/store_watcher.dart';
import 'spot_preview.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';

/// "Mettre en avant" (071): the shop's spots on the street, and the door to
/// buy one.
///
/// The audit: À la une existed, but only the platform could put an article
/// there, by hand, and an owner had no way to ask, no price, no way to pay
/// and no figure to judge it by. The card lists the shop's spots with what
/// each earned (seen, opened, added, ordered) and opens the sheet that sells
/// one.
///
/// Since 142 (139): 7 days only, two products — « Un article à la une,
/// 7 jours » and « La boutique à la une, 7 jours » (the farm's, the
/// association's) — paid through the store in the Android and iPhone apps
/// and by card on the website, at the business's zone price. Pro pays too.
class SpotsCard extends StatefulWidget {
  const SpotsCard({
    super.key,
    required this.orgId,
    required this.admin,
    required this.retail,
    this.vitrineOnly = false,
    this.org,
    this.store,
    this.pay,
    this.photo,
  });

  final String orgId;
  final AdminRepository admin;
  final RetailRepository? retail;

  /// An association (no stock): only the whole-vitrine spot is offered.
  final bool vitrineOnly;

  /// The business, when the caller has it (tests); else the session's.
  final OrgSummary? org;

  /// The store side, for tests; the app's own store listener otherwise.
  final SpotStoreSide? store;
  final WavePay? pay;
  final Future<Uint8List> Function(String key)? photo;

  @override
  State<SpotsCard> createState() => _SpotsCardState();
}

class _SpotsCardState extends State<SpotsCard> {
  List<Promotion> _spots = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final spots = await widget.admin.myPromotions(widget.orgId);
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _buy() async {
    final changed = await SpotSheet.open(context,
        orgId: widget.orgId,
        admin: widget.admin,
        retail: widget.retail,
        vitrineOnly: widget.vitrineOnly,
        org: widget.org,
        store: widget.store,
        pay: widget.pay,
        photo: widget.photo);
    if (changed == true) await _load();
  }

  Future<void> _claim(Promotion spot) async {
    final changed = await SpotSheet.pay(context,
        orgId: widget.orgId,
        spot: spot,
        admin: widget.admin,
        org: widget.org,
        store: widget.store,
        pay: widget.pay);
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return KajCard(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('Mettre en avant'),
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.vitrineOnly
                  ? context.tr('Un service en tête de « À la une », ou votre vitrine en haut de la liste des vitrines, pour 7 jours.')
                  : context.tr('Un article ou un service en tête de « À la une » sur la page d\'accueil, ou toute la vitrine en haut de la liste, pour 7 jours.'),
              style: muted,
            ),
            if (_loaded && _spots.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final s in _spots.take(5))
                _SpotRow(spot: s, onPay: () => _claim(s)),
            ],
            if (sellsSpotsInApp) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _buy,
                icon: const Icon(Icons.add),
                label: Text(context.tr('Mettre en avant')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpotRow extends StatelessWidget {
  const _SpotRow({required this.spot, required this.onPay});

  final Promotion spot;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('d MMM', intlLocale());
    final state = spot.stateLabel();
    final running = state == 'En cours' || state == 'Terminée';
    final dates = spot.startsAt == null
        ? context.tr('{days} jours', {'days': spot.days})
        : context.tr('du {from} au {to}', {'from': date.format(spot.startsAt!), 'to': date.format(spot.endsAt!)});
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(spot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                _StateChip(label: state),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              // A spot given for nothing (a weekly prize, Pro's monthly one
              // before 139) says so — never who offered it.
              [dates, if (spot.free) context.tr('offerte')].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (running) ...[
              const SizedBox(height: 6),
              Text(
                context.tr('{seen} vues · {opened} ouvertures · {added} au panier · {ordered} commandes', {'seen': spot.seen, 'opened': spot.opened, 'added': spot.added, 'ordered': spot.ordered}),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            if (spot.status == 'requested' && sellsSpotsInApp)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(context.tr('Payer et confirmer')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (label) {
      'En cours' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'Refusée' => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(context.tr(label),
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// The store side of the sheet (142): the store's spots, and what the
/// app's purchase listener says about each purchase. The app's own comes
/// from its [StoreWatcher]; a test hands its own.
class SpotStoreSide {
  const SpotStoreSide({required this.billing, required this.notices, this.watcher});

  final SpotStoreBilling billing;
  final ValueListenable<SpotNotice?> notices;
  final StoreWatcher? watcher;

  /// The app's, when this build sells through a store.
  static SpotStoreSide? of(BuildContext context) {
    final watcher = AppScope.read(context)?.storeWatcher;
    final billing = watcher?.billing;
    if (watcher == null || billing is! SpotStoreBilling) return null;
    return SpotStoreSide(billing: billing as SpotStoreBilling, notices: watcher.spotNotice, watcher: watcher);
  }
}

/// The sheet that sells a spot: what, for 7 days, the price, how to pay.
/// Two steps in one sheet — ask, then pay — so a shop that asks and pays
/// later finds the second step on the card.
class SpotSheet {
  static Future<bool?> open(
    BuildContext context, {
    required String orgId,
    required AdminRepository admin,
    required RetailRepository? retail,
    String? productId,
    bool vitrineOnly = false,
    OrgSummary? org,
    SpotStoreSide? store,
    WavePay? pay,
    Future<Uint8List> Function(String key)? photo,
    String? channel,
  }) {
    return showMaraSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SpotSheetBody(
        orgId: orgId,
        admin: admin,
        retail: retail,
        productId: productId,
        vitrineOnly: vitrineOnly,
        org: org,
        store: store,
        pay: pay,
        photo: photo,
        channel: channel,
      ),
    );
  }

  /// Straight to the payment step of a spot already asked for.
  static Future<bool?> pay(
    BuildContext context, {
    required String orgId,
    required Promotion spot,
    required AdminRepository admin,
    OrgSummary? org,
    SpotStoreSide? store,
    WavePay? pay,
    String? channel,
  }) {
    return showMaraSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SpotSheetBody(
        orgId: orgId,
        admin: admin,
        retail: null,
        asked: spot,
        org: org,
        store: store,
        pay: pay,
        channel: channel,
      ),
    );
  }
}

class _SpotSheetBody extends StatefulWidget {
  const _SpotSheetBody({
    required this.orgId,
    required this.admin,
    required this.retail,
    this.productId,
    this.asked,
    this.vitrineOnly = false,
    this.org,
    this.store,
    this.pay,
    this.photo,
    this.channel,
  });

  final String orgId;
  final AdminRepository admin;
  final RetailRepository? retail;
  final String? productId;

  /// No article choice: the whole vitrine only (an association).
  final bool vitrineOnly;

  /// A spot already asked for: the sheet opens on its payment.
  final Promotion? asked;
  final OrgSummary? org;
  final SpotStoreSide? store;
  final WavePay? pay;
  final Future<Uint8List> Function(String key)? photo;

  /// 'apple', 'google' or 'web'; [spotChannel] unless a test says.
  final String? channel;

  @override
  State<_SpotSheetBody> createState() => _SpotSheetBodyState();
}

class _SpotSheetBodyState extends State<_SpotSheetBody> {
  SpotTerms _terms = const SpotTerms();
  List<Product> _articles = const [];
  Map<String, String> _photoKeys = const {};

  /// This business's spots, to say before the tap what is already asked
  /// or running (the server refuses a second one for the same place).
  List<Promotion> _mine = const [];

  /// The whole shop rather than one article.
  late bool _shop = widget.vitrineOnly;
  String? _productId;
  bool _busy = false;
  String? _error;
  String? _info;
  bool _preview = false;
  final _note = TextEditingController();

  /// Set once asked: the sheet moves on to paying for it.
  Promotion? _asked;
  bool _done = false;

  /// Paid through the store or by card, and programmed (not « J'ai payé »).
  bool _paidOnline = false;

  // The store side (142).
  late final String _channel = widget.channel ?? spotChannel;
  SpotStoreSide? _store;
  List<SpotStoreProduct>? _storeProducts;
  late final WavePay? _pay = widget.pay ?? AppScope.read(context)?.wavePay;

  bool get _viaStore => _channel == 'apple' || _channel == 'google';

  OrgSummary? get _org =>
      widget.org ?? AppScope.maybeOf(context)?.session.orgById(widget.orgId);

  String get _orgCurrency => _org?.currency ?? 'XOF';
  String get _profile => _org?.profile ?? (widget.vitrineOnly ? 'association' : 'retail');

  @override
  void initState() {
    super.initState();
    _productId = widget.productId;
    _asked = widget.asked;
    if (_asked != null) _shop = _asked!.isShop;
    _load();
    if (!_viaStore) {
      // The number to write to for paying, asked ahead of the tap (a browser
      // opens a chat only straight from the gesture).
      Support.warm(AppScope.maybeOf(context)?.auth.client);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viaStore && _store == null) {
      _store = widget.store ?? SpotStoreSide.of(context);
      _store?.notices.addListener(_heard);
      _store?.watcher?.attachSpot();
      unawaited(_loadStore());
    }
  }

  @override
  void dispose() {
    _store?.notices.removeListener(_heard);
    _store?.watcher?.detachSpot();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final terms = await widget.admin.spotTerms();
      final products = widget.retail == null
          ? const <Product>[]
          : await widget.retail!.products(widget.orgId);
      final photos = widget.retail == null
          ? const <String, String>{}
          : await widget.retail!.photoKeys(widget.orgId);
      final mine = await widget.admin.myPromotions(widget.orgId);
      if (!mounted) return;
      setState(() {
        _terms = terms;
        _mine = mine;
        _photoKeys = photos;
        _articles = products
            .where((p) =>
                p.isPublished &&
                !p.isIngredient &&
                p.salePrice > 0 &&
                // A service has no stock (143); not followed (131): always
                // there, as request_promotion allows.
                (p.isService || p.quantity > 0 || !p.stockTracked))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (_productId == null && _articles.isNotEmpty) {
          _productId = _articles.first.id;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadStore() async {
    final store = _store;
    if (store == null) {
      if (mounted) setState(() => _storeProducts = const []);
      return;
    }
    try {
      final products = await store.billing.spotProducts();
      if (mounted) setState(() => _storeProducts = products);
    } catch (_) {
      if (mounted) setState(() => _storeProducts = const []);
    }
  }

  /// The store listener's word on a purchase (142).
  void _heard() {
    final n = _store?.notices.value;
    if (n == null || !mounted) return;
    final asked = _asked?.id;
    if (!n.isFor(asked)) return;
    setState(() {
      switch (n.state) {
        case SpotNoticeState.done:
          _busy = false;
          _done = true;
          _paidOnline = true;
          _error = null;
          _info = null;
        case SpotNoticeState.checking:
        case SpotNoticeState.pending:
          _info = n.text(context);
          _error = null;
        case SpotNoticeState.cancelled:
          _busy = false;
          _info = null;
          _error = n.text(context);
        case SpotNoticeState.refused:
          _busy = false;
          _info = null;
          _error = n.text(context);
      }
    });
  }

  String get _storeName => _channel == 'apple' ? 'App Store' : 'Google Play';

  SpotStoreProduct? get _storeProduct {
    final kind = _shop ? 'shop' : 'article';
    final want = spotProductId(_channel, kind);
    for (final p in _storeProducts ?? const <SpotStoreProduct>[]) {
      if (p.id == want) return p;
    }
    return null;
  }

  /// The price, as this build says it: the store's own in the apps; the
  /// business's zone price on the website.
  String? _priceText({bool? shop}) {
    if (_viaStore) return _storeProduct?.price;
    final s = shop ?? _shop;
    return zonePriceText(_terms.zonePrice(_orgCurrency, shop: s), _terms.zoneCurrency(_orgCurrency),
        language: context.trLanguage);
  }

  /// The spot already asked or running for what is chosen (the vitrine, or
  /// this article): the server's « déjà demandé ou en cours », said first.
  Promotion? get _existing {
    final now = DateTime.now();
    final product = _shop ? null : _productId;
    for (final p in _mine) {
      if (p.productId != product) continue;
      if (p.status == 'requested' || p.status == 'paid_claimed') return p;
      if (p.status == 'approved' && (p.endsAt == null || p.endsAt!.isAfter(now))) {
        return p;
      }
    }
    return null;
  }

  String _day(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }

  /// The product's own name: « Un article à la une, 7 jours », « La
  /// boutique à la une, 7 jours » (a farm's and an association's in their
  /// words).
  String _productName(bool shop) => !shop
      ? context.tr('Un article à la une, 7 jours')
      : switch (_profile) {
          'farm' => context.tr('La ferme à la une, 7 jours'),
          'association' || 'church' => context.tr('L\'association à la une, 7 jours'),
          _ => context.tr('La boutique à la une, 7 jours'),
        };

  /// What the sheet says instead of the price and the button when a spot
  /// for this place already exists — and the one gesture that goes on.
  List<Widget> _existingView(ThemeData theme, Promotion e) {
    final running = e.status == 'approved';
    final title = running
        ? (e.endsAt == null
            ? context.tr('Déjà en avant')
            : context.tr('Déjà en avant jusqu\'au {date}', {'date': _day(e.endsAt!)}))
        : e.status == 'paid_claimed'
            ? context.tr('Paiement signalé : Mara le vérifie')
            : context.tr('Déjà demandée, en attente du paiement');
    return [
      KajCard(
        key: const Key('spot-existing'),
        elevation: 0,
        color: theme.colorScheme.primaryContainer,
        child: ListTile(
          leading: Icon(running ? Icons.campaign_outlined : Icons.hourglass_top),
          title: Text(title),
          subtitle: Text(running
              ? context.tr('Une seule mise en avant à la fois pour la même place. Vous pourrez la prolonger quand elle se termine.')
              : context.tr('Une seule demande à la fois pour la même place.')),
        ),
      ),
      if (e.status == 'requested') ...[
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton(
            key: const Key('spot-resume-pay'),
            onPressed: _busy ? null : () => setState(() => _asked = e),
            child: Text(context.tr('Reprendre le paiement'),
                style: const TextStyle(fontSize: 16)),
          ),
        ),
      ],
    ];
  }

  Future<Promotion?> _askOnce() async {
    final id = await widget.admin
        .requestPromotion(widget.orgId, productId: _shop ? null : _productId, days: SpotTerms.days);
    final mine = await widget.admin.myPromotions(widget.orgId);
    _mine = mine;
    return mine.where((p) => p.id == id).firstOrNull;
  }

  Future<void> _ask() async {
    // Two taps in one frame ask once.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final spot = await _askOnce();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _asked = spot;
        // A spot programmed at once (a gift): nothing to pay.
        _done = spot == null || spot.status == 'approved';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  /// Through the store (142): the spot is asked first (the server checks
  /// the article and the place), then bought; it is programmed when the
  /// Worker has verified the purchase.
  Future<void> _buyInStore() async {
    final product = _storeProduct;
    final store = _store;
    // Two taps in one frame buy once (the store's sheet opens once).
    if (product == null || store == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final notAsked = context.tr('La mise en avant n\'a pas pu être demandée.');
    try {
      final spot = _asked ?? await _askOnce();
      if (spot == null) throw StateError(notAsked);
      if (!mounted) return;
      setState(() => _asked = spot);
      await store.billing.buySpot(product, orgId: widget.orgId, promotionId: spot.id);
      if (mounted) {
        setState(() => _info ??= context.tr('Paiement en cours avec {store}…', {'store': _storeName}));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _checkAgain() async {
    setState(() {
      _error = null;
      _info = context.tr('Vérification de l\'achat auprès de {store}…', {'store': _storeName});
    });
    try {
      final watcher = _store?.watcher;
      if (watcher != null) {
        // The unfinished spots themselves (Apple's restore hands back no
        // consumable; Google's would also re-verify Mara Pro).
        await watcher.recoverSpots(again: true);
      } else {
        await _store?.billing.restore();
      }
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  /// By card on the website (142): Stripe's one-time page, in this tab.
  Future<void> _card() async {
    final pay = _pay;
    final spot = _asked;
    if (pay == null || spot == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await pay.spotByCard(spot.id);
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.platformDefault, webOnlyWindowName: kIsWeb ? '_self' : null);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paid() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.claimPromotionPaid(_asked!.id, note: _note.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            key: const Key('spot-sheet'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('Mettre en avant'), style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              if (_done)
                ..._doneView(theme)
              else if (_asked != null)
                ..._payView(theme, muted)
              else
                ..._askView(theme, muted),
              if (_info != null && !_done) ...[
                const SizedBox(height: 8),
                Text(_info!, key: const Key('spot-info'), style: muted),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, key: const Key('spot-error'), style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// « Voir à quoi ça ressemble » and, opened, the street with this spot.
  List<Widget> _previewPart(ThemeData theme) {
    final article = _shop ? null : _articles.where((a) => a.id == _productId).firstOrNull;
    final photoKey = article != null
        ? _photoKeys[article.id]
        : _articles.map((a) => _photoKeys[a.id]).whereType<String>().firstOrNull;
    final scope = AppScope.maybeOf(context);
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('spot-preview-toggle'),
          onPressed: () => setState(() => _preview = !_preview),
          icon: Icon(_preview ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          label: Text(_preview ? context.tr('Masquer l\'aperçu') : context.tr('Voir à quoi ça ressemble')),
        ),
      ),
      if (_preview) ...[
        const SizedBox(height: 4),
        SpotPreview(
          shop: _shop,
          businessName: _org?.name ?? '',
          profile: _profile,
          articleName: article?.name,
          articlePrice: article == null ? null : moneyFormat(_orgCurrency).format(article.salePrice),
          photoKey: photoKey,
          photo: widget.photo ?? scope?.capture.objectBytes,
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  List<Widget> _askView(ThemeData theme, TextStyle? muted) {
    final shop = _shop;
    final kindWord = switch (_profile) {
      'farm' => context.tr('La ferme'),
      'association' || 'church' => context.tr('L\'association'),
      _ => context.tr('La boutique'),
    };
    final price = _priceText();
    final storeLoading = _viaStore && _storeProducts == null;
    // In the apps a spot is the store's own product; before 139 is live
    // (no server check of a store payment) or before the store knows the
    // product, it is not offered.
    final storeMissing = _viaStore && !storeLoading && (_storeProduct == null || !_terms.paidOnline);
    return [
      // An association too (143): its services can be « à la une ».
      ...[
        Text(context.tr('Quoi ?'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          key: const Key('spot-what'),
          segments: [
            ButtonSegment(
                value: false,
                icon: const Icon(Icons.sell_outlined),
                label: Text(context.tr('Article ou service'))),
            ButtonSegment(
                value: true,
                icon: const Icon(Icons.storefront_outlined),
                label: Text(kindWord)),
          ],
          selected: {shop},
          onSelectionChanged: _busy
              ? null
              : (v) => setState(() => _shop = v.first),
        ),
        const SizedBox(height: 10),
      ],
      if (!shop && _articles.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.tr('Rien de prêt : mettez sur la vitrine un article (avec du stock) ou un service, avec une photo et un prix.'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      if (!shop && _articles.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          initialValue: _articles.any((a) => a.id == _productId)
              ? _productId
              : _articles.first.id,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: context.tr('Article ou service'), border: const OutlineInputBorder()),
          items: [
            for (final a in _articles)
              DropdownMenuItem(
                value: a.id,
                child: Text('${a.name} · ${moneyFormat(_orgCurrency).format(a.salePrice)}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _productId = v),
        ),
        const SizedBox(height: 10),
      ],
      Text(_productName(shop),
          key: const Key('spot-product'),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        shop
            ? context.tr('La vitrine apparaît en tête de la liste des vitrines, marquée « Sponsorisé », pendant 7 jours.')
            : context.tr('L\'article ou le service apparaît en tête de « À la une » sur la page d\'accueil, marqué « Sponsorisé », pendant 7 jours. Il lui faut une photo et un prix, et du stock pour un article.'),
        style: muted,
      ),
      ..._previewPart(theme),
      const SizedBox(height: 8),
      if (_existing != null)
        ..._existingView(theme, _existing!)
      else if (storeMissing)
        Text(
          context.tr('La mise en avant n\'est pas disponible pour le moment.'),
          key: const Key('spot-store-missing'),
          style: muted,
        )
      else ...[
        Text(
          storeLoading || price == null
              ? context.tr('Prix : …')
              : context.tr('Prix : {price}', {'price': price}),
          key: const Key('spot-price'),
          style: theme.textTheme.titleMedium,
        ),
        // The cap is on « À la une »'s articles, not on the vitrines' list.
        if (!shop)
          Text(
            context.tr('Au plus {maxLive} articles à la une en même temps : si la place est prise, votre période commence dès qu\'une se libère.', {'maxLive': _terms.maxLive}),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 14),
        // As tall as its words at the reader's text size: never cut.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: FilledButton(
            key: const Key('spot-go'),
            onPressed: _busy || storeLoading || (!shop && _productId == null)
                ? null
                : (_viaStore ? _buyInStore : _ask),
            child: Text(
                _viaStore
                    ? context.tr('Acheter · {price}', {'price': price ?? ''})
                    : context.tr('Continuer vers le paiement'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
          ),
        ),
        if (_viaStore) ...[
          const SizedBox(height: 6),
          Text(
            _channel == 'apple'
                ? context.tr('Paiement par l\'App Store. La mise en avant est programmée dès que Mara a reçu la confirmation.')
                : context.tr('Paiement par Google Play. La mise en avant est programmée dès que Mara a reçu la confirmation.'),
            key: const Key('spot-store-note'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    ];
  }

  List<Widget> _payView(ThemeData theme, TextStyle? muted) {
    final spot = _asked!;
    if (_viaStore) return _storePayView(theme, muted, spot);
    // Wave and « J'ai payé » in West African francs only: Wave takes no
    // XAF (an XAF business pays by card).
    final xof = zoneCurrencyOf(_orgCurrency) == 'XOF';
    final card = _terms.stripeOn && (_pay?.compiledIn ?? false);
    return [
      Text(context.tr('{label} · {days} jours', {'label': spot.label, 'days': spot.days}),
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(context.tr('À payer : {amount}', {'amount': zonePriceText(spot.price, spot.currency, language: context.trLanguage)}),
          key: const Key('spot-amount'),
          style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      // By card through Stripe (142), on the website.
      if (card) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: FilledButton.icon(
            key: const Key('spot-card'),
            onPressed: _busy ? null : _card,
            icon: const Icon(Icons.credit_card),
            label: Text(context.tr('Payer par carte'), style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 6),
        Text(context.tr('Visa, Mastercard. Paiement unique et sécurisé par Stripe : la mise en avant est programmée dès que le paiement est reçu.'),
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
      ],
      // Wave and by hand: in francs only, as they are today.
      if (xof) ..._handView(theme, muted, spot, card: card)
      else if (!card)
        Text(context.tr('Le paiement par carte n\'est pas encore ouvert. Revenez bientôt : votre demande est gardée.'),
            key: const Key('spot-card-soon'), style: muted),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(true),
        child: Text(context.tr('Payer plus tard')),
      ),
    ];
  }

  /// The website's older ways, unchanged (076, 071): Wave, then a number
  /// or Mara's WhatsApp, and « J'ai payé ».
  List<Widget> _handView(ThemeData theme, TextStyle? muted, Promotion spot, {required bool card}) => [
        // Paid and programmed at once, by Wave or card (076), when the
        // platform has opened it.
        WaveButtons(
          kind: 'spot',
          ref: spot.id,
          below: Text(context.tr('Ou à la main :'), style: muted),
        ),
        const SizedBox(height: 8),
        if (_terms.hasWave)
          KajCard(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: Text(_terms.wave),
              subtitle: Text(_terms.waveName.isEmpty
                  ? context.tr('Payez par Wave ou Orange Money à ce numéro')
                  : context.tr('Wave · {waveName}', {'waveName': _terms.waveName})),
              trailing: IconButton(
                tooltip: context.tr('Copier le numéro'),
                icon: const Icon(Icons.copy_outlined),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _terms.wave));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(context.tr('Numéro copié'))));
                },
              ),
            ),
          )
        else
          // No payment number set: « contactez Mara » with no way to was a
          // dead end. One tap opens Mara's WhatsApp, the message written.
          ValueListenableBuilder<SupportContacts>(
            valueListenable: Support.contacts,
            builder: (context, c, _) => c.whatsapp == null
                ? Text(
                    context.tr('Pour payer, écrivez à Mara : {email}. Le numéro de paiement vous sera donné directement.',
                        {'email': c.email}),
                    style: muted)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          context.tr('Demandez le numéro de paiement à Mara sur WhatsApp : le message est déjà écrit.'),
                          style: muted),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('spot-pay-whatsapp'),
                        onPressed: () => Support.openWhatsApp(context,
                            text: _payMessage(spot)),
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(context.tr('Demander le numéro sur WhatsApp')),
                      ),
                    ],
                  ),
          ),
        const SizedBox(height: 12),
        Text(
            context.tr('Une fois le paiement envoyé, dites-le ici : Mara le vérifie et la mise en avant commence.'),
            style: muted),
        const SizedBox(height: 10),
        TextField(
          controller: _note,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: context.tr('Précision (facultatif)'),
            hintText: context.tr('Nom Wave, référence…'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: card
              ? OutlinedButton.icon(
                  onPressed: _busy ? null : _paid,
                  icon: const Icon(Icons.done_all),
                  label: Text(context.tr('J\'ai payé'), style: const TextStyle(fontSize: 17)),
                )
              : FilledButton.icon(
                  onPressed: _busy ? null : _paid,
                  icon: const Icon(Icons.done_all),
                  label: Text(context.tr('J\'ai payé'), style: const TextStyle(fontSize: 17)),
                ),
        ),
      ];

  /// The spot asked, bought through the store (142): nothing else is
  /// offered in the apps — no Wave, no « J'ai payé », no link out.
  List<Widget> _storePayView(ThemeData theme, TextStyle? muted, Promotion spot) {
    final product = _storeProduct;
    final loading = _storeProducts == null;
    return [
      Text(spot.label, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
      Text(_productName(spot.isShop), style: muted),
      const SizedBox(height: 10),
      // Before 139 is live nothing could verify the store's payment.
      if (!loading && (product == null || !_terms.paidOnline))
        Text(context.tr('La mise en avant n\'est pas disponible pour le moment.'),
            key: const Key('spot-store-missing'), style: muted)
      else ...[
        Text(
          product == null ? context.tr('Prix : …') : context.tr('Prix : {price}', {'price': product.price}),
          key: const Key('spot-price'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: FilledButton(
            key: const Key('spot-go'),
            onPressed: _busy || product == null ? null : _buyInStore,
            child: Text(context.tr('Acheter · {price}', {'price': product?.price ?? ''}),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _channel == 'apple'
              ? context.tr('Paiement par l\'App Store. La mise en avant est programmée dès que Mara a reçu la confirmation.')
              : context.tr('Paiement par Google Play. La mise en avant est programmée dès que Mara a reçu la confirmation.'),
          key: const Key('spot-store-note'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 8),
      TextButton(
        key: const Key('spot-check-again'),
        onPressed: _checkAgain,
        child: Text(context.tr('Vérifier un achat déjà payé')),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(context.tr('Payer plus tard')),
      ),
    ];
  }

  /// What the owner sends Mara to pay for [spot]: what, how long, how
  /// much, and which business — enough for Mara to answer with the number.
  String _payMessage(Promotion spot) {
    final name = _org?.name ?? '';
    return context.tr(
        'Bonjour Mara, je veux payer une mise en avant : {label} · {days} jours · {amount}{org}. Quel numéro pour payer ?',
        {
          'label': spot.label,
          'days': spot.days,
          'amount': zonePriceText(spot.price, spot.currency, language: context.trLanguage),
          'org': name.isEmpty ? '' : ' ($name)',
        });
  }

  List<Widget> _doneView(ThemeData theme) {
    final free = !_paidOnline && _asked?.status == 'approved';
    final (title, line) = _paidOnline
        ? (
            context.tr('C\'est payé.'),
            _shop
                ? context.tr('Votre vitrine est programmée en tête de la liste pour 7 jours. Ses vues et commandes s\'affichent dans « Mettre en avant ».')
                : context.tr('Votre article est programmé à la une pour 7 jours, dès qu\'une place se libère. Ses vues et commandes s\'affichent dans « Mettre en avant ».'),
          )
        : free
            ? (
                context.tr('C\'est en ligne.'),
                context.tr('Votre article est à la une. Ses vues et commandes s\'affichent dans « Mettre en avant ».'),
              )
            : (
                context.tr('Merci, c\'est noté.'),
                context.tr('Mara vérifie le paiement et lance la mise en avant. Vous serez prévenu dans la cloche.'),
              );
    return [
      KajCard(
        key: const Key('spot-done'),
        elevation: 0,
        color: theme.colorScheme.primaryContainer,
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(title),
          subtitle: Text(line),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(context.tr('Fermer')),
      ),
    ];
  }
}

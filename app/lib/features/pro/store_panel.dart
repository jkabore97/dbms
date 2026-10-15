import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/pay/wave_pay.dart';
import '../../core/theme/kaj_theme.dart';
import 'store_billing.dart';
import 'store_watcher.dart';

/// The foot of the Pro page in the store apps once the platform sells Pro
/// through the store (130, [sellsProThroughStore]): Mara Pro's month and
/// year at the store's own price, « S'abonner », « Restaurer mes achats »
/// (Apple asks for it), « Gérer mon abonnement » (the store's page), and
/// the auto-renewal terms Apple asks to be said beside the button.
///
/// A purchase is not Pro until the payments Worker said so: the store's
/// transaction (Apple) or token (Google) is sent to /store/verify, which
/// asks the store itself; only then is the purchase completed and the page
/// reads the business again. The listening is the app's, from its start
/// ([StoreWatcher], review S3): this page draws what it says, and makes
/// one of its own only where the app has none (a test).
///
/// One store account pays Mara Pro for one business: Apple keeps one
/// running subscription per group and Apple ID — buying the other period
/// for a second business would only change the first one's (a
/// crossgrade) — and Google one purchase of `mara_pro` per account. So
/// when the owner's own purchase in this store already pays for another
/// business ([StoreStanding.elsewhereName], review S4), this page sells
/// nothing: it says which business is paid and offers « Gérer mon
/// abonnement ».
class StorePanel extends StatefulWidget {
  const StorePanel({
    super.key,
    required this.org,
    required this.billing,
    required this.verify,
    this.watcher,
    this.standing,
    this.onPro,
    this.launch,
    this.restoreWait = const Duration(seconds: 4),
  });

  final OrgSummary org;
  final StoreBilling billing;

  /// The Worker's /store/verify for one purchase (WavePay.verifyStore),
  /// for the page's own listener when the app has none.
  final Future<StoreVerdict> Function(StorePurchase purchase) verify;

  /// The app's purchase listener (main.dart); null in a test.
  final StoreWatcher? watcher;

  /// Where this business's store subscription stands (my_store_subscription).
  final Future<StoreStanding?> Function()? standing;

  /// The business is on Pro now: read it again.
  final VoidCallback? onPro;

  /// Opens the store's subscriptions page (the platform's launcher unless
  /// a test gives one).
  final Future<bool> Function(Uri uri)? launch;

  /// How long « Restaurer » waits for the store before saying it found
  /// nothing.
  final Duration restoreWait;

  @override
  State<StorePanel> createState() => _StorePanelState();
}

class _StorePanelState extends State<StorePanel> {
  late final StoreWatcher _watcher;
  late final bool _ownWatcher;
  List<StoreProduct>? _products;
  bool _unavailable = false;

  /// The period whose « S'abonner » was tapped, while its purchase runs
  /// (132): only that button says it is busy; the other stays as it is,
  /// only not tappable.
  String? _buying;
  bool _restoring = false;
  StoreStanding? _standing;

  /// The Mara Pro subscriptions this store account holds (132).
  List<StoreOwned> _owned = const [];

  bool get _busy => _buying != null;

  String get _store => widget.billing.platform == 'apple' ? 'App Store' : 'Google Play';

  @override
  void initState() {
    super.initState();
    _ownWatcher = widget.watcher == null;
    _watcher = widget.watcher ??
        StoreWatcher(billing: widget.billing, verify: widget.verify, onPro: widget.onPro);
    if (_ownWatcher) _watcher.start();
    _watcher.attach(widget.org.id);
    _watcher.notice.addListener(_onNotice);
    _load();
  }

  @override
  void dispose() {
    _watcher.notice.removeListener(_onNotice);
    _watcher.detach(widget.org.id);
    if (_ownWatcher) _watcher.dispose();
    super.dispose();
  }

  void _onNotice() {
    if (mounted) setState(() => _buying = null);
  }

  /// What the store account holds; nothing when the store cannot say.
  Future<List<StoreOwned>> _readOwned() async {
    try {
      return await widget.billing.owned();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _load() async {
    try {
      final standing = widget.standing == null ? null : await widget.standing!();
      if (!await widget.billing.available()) {
        if (mounted) setState(() => _unavailable = true);
        return;
      }
      final products = await widget.billing.products();
      final owned = await _readOwned();
      if (mounted) {
        setState(() {
          _products = products;
          _standing = standing;
          _owned = owned;
          _unavailable = products.isEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  void _say(String Function(BuildContext context) text) {
    _watcher.notice.value = StoreNotice(text, orgId: widget.org.id);
  }

  Future<void> _buy(StoreProduct product) async {
    setState(() => _buying = product.period);
    _watcher.notice.value = null;
    try {
      await widget.billing.buy(product, orgId: widget.org.id);
    } on PlatformException catch (e) {
      // StoreKit 2 says its refusal here, not on the purchase stream (the
      // iPhone's « storekit2_failed_to_fetch_product » among them): its
      // code is said and reported (132).
      _failed(product, e.code, e.message, e.details?.toString());
    } catch (e) {
      _failed(product, e.runtimeType.toString(), '$e', null);
    }
  }

  void _failed(StoreProduct product, String? code, String? message, String? details) {
    if (!storeCancelled(code, message)) {
      _watcher.log?.call(storeErrorLine(widget.billing.platform, product.id, code, message, details));
    }
    _say((context) => storeErrorText(context, code, message, _store));
    if (mounted) setState(() => _buying = null);
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final before = _watcher.heard;
    _say((context) => context.tr('Recherche de vos achats sur {store}…', {'store': _store}));
    try {
      await widget.billing.restore();
      await Future<void>.delayed(widget.restoreWait);
      final owned = await _readOwned();
      if (mounted) setState(() => _owned = owned);
      if (_watcher.heard == before) {
        _say((context) => context.tr('Aucun abonnement Marakaj Pro à restaurer sur ce compte {store}.', {'store': _store}));
      }
    } catch (_) {
      _say((context) => context.tr('{store} n\'a pas répondu. Réessayez dans un moment.', {'store': _store}));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _manage() async {
    final uri = widget.billing.manageUrl;
    final launch = widget.launch;
    if (launch != null) {
      await launch(uri);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = widget.org;
    final muted = theme.textTheme.bodySmall?.copyWith(color: kMist);
    final products = _products;
    StoreProduct? of(String period) {
      for (final p in products ?? const <StoreProduct>[]) {
        if (p.period == period) return p;
      }
      return null;
    }

    final month = of('month');
    final year = of('year');
    final elsewhere = _standing?.elsewhereName;
    // S4: the owner's purchase in THIS store already pays for another
    // business — nothing to buy here (on Apple, the other period would
    // only crossgrade that one).
    final paidElsewhere = elsewhere != null &&
        elsewhere.isNotEmpty &&
        (_standing?.elsewherePlatform == null || _standing!.elsewherePlatform == widget.billing.platform);
    // « Gérer » opens this store's page: offered where this store holds
    // the subscription in question, never for a Pro paid by card or in
    // the other store.
    final manageable = org.isPro
        ? _standing?.platform == widget.billing.platform
        : org.isAdmin;
    // 132: this store account already holds Mara Pro — for another
    // business, or one the Worker refused (a test purchase for a business
    // that may not have one): the store would refuse a second purchase
    // (Google: « You're already subscribed »). Nothing to buy: manage it
    // in the store first.
    final ownedElsewhere = _owned.any((o) => o.orgId != org.id || _watcher.refusedOwned(o));
    // For this very business, not yet read by Mara: restore it.
    final ownedHere = !ownedElsewhere && _owned.any((o) => o.orgId == org.id);
    // Only this business's notices (132): never another business's
    // purchase, refused or not, on this page.
    final notice = _watcher.notice.value;
    final message = notice != null && notice.isFor(org.id) ? notice.text(context) : null;
    final good = notice?.good ?? false;

    return Column(
      key: const Key('store-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!org.isPro && !org.isAdmin)
          Text(context.tr('Seul un administrateur de l\'entreprise peut l\'abonner à Marakaj Pro.'),
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium)
        else if (!org.isPro) ...[
          if (products == null && !_unavailable)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_unavailable)
            Text(
              context.tr('{store} ne propose pas Marakaj Pro sur cet appareil pour le moment. Réessayez plus tard.', {'store': _store}),
              key: const Key('store-unavailable'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            )
          else if (paidElsewhere) ...[
            Text(
              context.tr('Votre abonnement {store} paie déjà Marakaj Pro pour « {name} ». Un abonnement couvre une seule entreprise : il ne peut pas payer aussi celle-ci depuis ce compte {store}. Pour changer d\'entreprise, ou l\'arrêter, gérez-le dans {store}.', {'name': elsewhere, 'store': _store}),
              key: const Key('store-elsewhere'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ]
          else if (ownedElsewhere) ...[
            Text(
              context.tr('Ce compte {account} a déjà un abonnement Marakaj Pro, pour une autre entreprise ou refusé. Gérez-le ou annulez-le dans {store}, puis réessayez.', {
                'account': widget.billing.platform == 'apple' ? 'Apple' : 'Google Play',
                'store': widget.billing.platform == 'apple' ? context.tr('l\'App Store') : 'Google Play',
              }),
              key: const Key('store-owned-elsewhere'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ]
          else if (ownedHere) ...[
            Text(
              context.tr('Ce compte {store} a déjà un abonnement Marakaj Pro pour cette entreprise : touchez « Restaurer mes achats » pour l\'activer.', {'store': _store}),
              key: const Key('store-owned-here'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ]
          else ...[
            for (final p in [?month, ?year]) ...[
              _ProductTile(
                product: p,
                busy: _buying == p.period,
                locked: _busy && _buying != p.period,
                onBuy: () => _buy(p),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
        if (message != null) ...[
          const SizedBox(height: 4),
          Container(
            key: const Key('store-message'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: good ? kInk : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(message,
                style: theme.textTheme.bodyMedium?.copyWith(color: good ? kPaper : kInk)),
          ),
          const SizedBox(height: 10),
        ],
        if (org.isAdmin || org.isPro) ...[
          OutlinedButton.icon(
            key: const Key('store-restore'),
            onPressed: _restoring || _busy ? null : _restore,
            icon: const Icon(Icons.restore),
            label: Text(context.tr('Restaurer mes achats')),
          ),
          if (manageable || paidElsewhere || ownedElsewhere || ownedHere) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              key: const Key('store-manage'),
              onPressed: _manage,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(context.tr('Gérer mon abonnement')),
            ),
          ],
        ],
        const SizedBox(height: 10),
        Text(
          context.tr('Marakaj Pro est un abonnement à renouvellement automatique{prices}. Le paiement est débité sur votre compte {store} à la confirmation de l\'achat. L\'abonnement se renouvelle automatiquement au même prix et pour la même durée, sauf s\'il est annulé au moins 24 heures avant la fin de la période en cours. Gérez-le ou annulez-le à tout moment dans les réglages de votre compte {store}.', {
            'store': _store,
            'prices': [
              if (month != null) context.tr(' : 1 mois à {price}', {'price': month.price}),
              if (year != null)
                month == null
                    ? context.tr(' : 1 an à {price}', {'price': year.price})
                    : context.tr(', ou 1 an à {price}', {'price': year.price}),
            ].join(),
          }),
          key: const Key('store-legal'),
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              key: const Key('store-terms'),
              onPressed: () => context.push(Routes.terms),
              child: Text(context.tr('Conditions d\'utilisation')),
            ),
            TextButton(
              key: const Key('store-privacy'),
              onPressed: () => context.push(Routes.privacy),
              child: Text(context.tr('Politique de confidentialité')),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.busy,
    required this.locked,
    required this.onBuy,
  });

  final StoreProduct product;

  /// This product's purchase runs: its button says so.
  final bool busy;

  /// The other product's purchase runs: this button looks as it always
  /// does, only it does not answer (132 — « both buttons react »).
  final bool locked;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final year = product.period == 'year';
    return Container(
      key: Key('store-product-${product.period}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: year ? kInk : theme.dividerColor, width: year ? 2 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(year ? context.tr('Marakaj Pro · 1 an') : context.tr('Marakaj Pro · 1 mois'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  year
                      ? context.tr('{price} par an', {'price': product.price})
                      : context.tr('{price} par mois', {'price': product.price}),
                  key: Key('store-price-${product.period}'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            key: Key('store-buy-${product.period}'),
            onPressed: busy || locked ? null : onBuy,
            // Disabled, it keeps its colours: only the spinner says which
            // purchase is running.
            style: FilledButton.styleFrom(
              backgroundColor: kInk,
              foregroundColor: kPaper,
              disabledBackgroundColor: kInk,
              disabledForegroundColor: kPaper,
            ),
            // The word stays (hidden) under the spinner: the button keeps
            // its width.
            child: busy
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(opacity: 0, child: Text(context.tr('S\'abonner'))),
                      const SizedBox(
                        key: Key('store-buy-busy'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kPaper),
                      ),
                    ],
                  )
                : Text(context.tr('S\'abonner')),
          ),
        ],
      ),
    );
  }
}

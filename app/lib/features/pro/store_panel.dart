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

/// The foot of the Pro page in the store apps once the platform sells Pro
/// through the store (130, [sellsProThroughStore]): Mara Pro's month and
/// year at the store's own price, « S'abonner », « Restaurer mes achats »
/// (Apple asks for it), « Gérer mon abonnement » (the store's page), and
/// the auto-renewal terms Apple asks to be said beside the button.
///
/// A purchase is not Pro until the payments Worker said so: the store's
/// transaction (Apple) or token (Google) is sent to /store/verify, which
/// asks the store itself; only then is the purchase completed and the page
/// reads the business again. A Worker that cannot be reached leaves the
/// purchase open — the store hands it back on the next visit or on
/// « Restaurer mes achats ».
///
/// One store account pays Mara Pro for one business: Apple keeps one
/// running subscription per group and Apple ID, Google one purchase of
/// `mara_pro` per account. A second business of the same owner says so
/// ([StoreStanding.elsewhereName]) and the store refuses a second.
class StorePanel extends StatefulWidget {
  const StorePanel({
    super.key,
    required this.org,
    required this.billing,
    required this.verify,
    this.standing,
    this.onPro,
    this.launch,
    this.restoreWait = const Duration(seconds: 4),
  });

  final OrgSummary org;
  final StoreBilling billing;

  /// The Worker's /store/verify for one purchase (WavePay.verifyStore).
  final Future<StoreVerdict> Function(StorePurchase purchase) verify;

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
  StreamSubscription<List<StorePurchase>>? _sub;
  List<StoreProduct>? _products;
  bool _unavailable = false;
  bool _busy = false;
  bool _restoring = false;
  bool _heard = false;
  String? _message;
  bool _good = false;
  StoreStanding? _standing;

  String get _store => widget.billing.platform == 'apple' ? 'App Store' : 'Google Play';

  @override
  void initState() {
    super.initState();
    _sub = widget.billing.purchases.listen(_onPurchases);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final standing = widget.standing == null ? null : await widget.standing!();
      if (!await widget.billing.available()) {
        if (mounted) setState(() => _unavailable = true);
        return;
      }
      final products = await widget.billing.products();
      if (mounted) {
        setState(() {
          _products = products;
          _standing = standing;
          _unavailable = products.isEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  void _say(String Function(BuildContext context) text, {bool good = false}) {
    if (!mounted) return;
    setState(() {
      _message = text(context);
      _good = good;
    });
  }

  Future<void> _onPurchases(List<StorePurchase> list) async {
    for (final p in list) {
      _heard = true;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          _say((context) => context.tr('Achat en attente : {store} doit encore le confirmer (accord parental, paiement en cours). Mara Pro s\'activera dès qu\'il sera confirmé.', {'store': _store}));
        case StorePurchaseStatus.canceled:
          await _completeQuietly(p);
          _say((context) => context.tr('Achat annulé : rien n\'a été prélevé.'));
        case StorePurchaseStatus.error:
          await _completeQuietly(p);
          _say((context) => _errorText(context, p.errorCode, p.errorMessage));
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          await _verify(p);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  String _errorText(BuildContext context, String? code, String? message) {
    final all = '${code ?? ''} ${message ?? ''}';
    if (all.contains('itemAlreadyOwned') || all.contains('alreadyOwned')) {
      return context.tr('Ce compte {store} paie déjà Mara Pro, sans doute pour une autre de vos entreprises : un abonnement couvre une seule entreprise.', {'store': _store});
    }
    if (all.contains('userCancel') || all.contains('canceled')) {
      return context.tr('Achat annulé : rien n\'a été prélevé.');
    }
    return context.tr('L\'achat n\'a pas pu se faire : {store} n\'a rien prélevé. Réessayez dans un moment.', {'store': _store});
  }

  Future<void> _completeQuietly(StorePurchase p) async {
    if (!p.needsCompletion) return;
    try {
      await widget.billing.complete(p);
    } catch (_) {}
  }

  Future<void> _verify(StorePurchase p) async {
    if (!mounted) return;
    {
      setState(() {
        _busy = true;
        _message = context.tr('Vérification de l\'achat auprès de {store}…', {'store': _store});
        _good = false;
      });
    }
    try {
      final verdict = await widget.verify(p);
      await _completeQuietly(p);
      if (verdict.pro) {
        widget.onPro?.call();
        _say((context) => context.tr('Merci ! Mara Pro est actif.'), good: true);
      } else {
        _say((context) => switch (verdict.state) {
          'expired' => context.tr('Cet abonnement est terminé : il ne donne plus Mara Pro.'),
          'revoked' => context.tr('Cet abonnement a été remboursé : il ne donne plus Mara Pro.'),
          'on_hold' || 'paused' => context.tr('Le paiement de cet abonnement est en attente chez {store} : mettez à jour votre moyen de paiement dans {store}.', {'store': _store}),
          'pending' => context.tr('Achat en attente : {store} doit encore le confirmer (accord parental, paiement en cours). Mara Pro s\'activera dès qu\'il sera confirmé.', {'store': _store}),
          _ => context.tr('Cet achat ne donne pas Mara Pro à cette entreprise.'),
        });
      }
    } on StoreVerifyRefused catch (e) {
      // Real, but not this business's (or not Mara Pro): the store is told
      // it was handled, so it stops offering it back.
      await _completeQuietly(p);
      _say((_) => e.message);
    } catch (_) {
      // The Worker was not reached: the purchase stays open, the store
      // hands it back.
      _say((context) => context.tr('Le paiement est fait, mais Mara n\'a pas encore pu le vérifier. Gardez une connexion et touchez « Restaurer mes achats » : rien ne sera prélevé deux fois.'));
    }
  }

  Future<void> _buy(StoreProduct product) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.billing.buy(product, orgId: widget.org.id);
    } on PlatformException catch (e) {
      _say((context) => _errorText(context, e.code, e.message));
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      _say((context) => _errorText(context, null, null));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _heard = false;
      _message = context.tr('Recherche de vos achats sur {store}…', {'store': _store});
      _good = false;
    });
    try {
      await widget.billing.restore();
      await Future<void>.delayed(widget.restoreWait);
      if (!_heard) {
        _say((context) => context.tr('Aucun abonnement Mara Pro à restaurer sur ce compte {store}.', {'store': _store}));
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

    return Column(
      key: const Key('store-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!org.isPro && !org.isAdmin)
          Text(context.tr('Seul un administrateur de l\'entreprise peut l\'abonner à Mara Pro.'),
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium)
        else if (!org.isPro) ...[
          if (products == null && !_unavailable)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_unavailable)
            Text(
              context.tr('{store} ne propose pas Mara Pro sur cet appareil pour le moment. Réessayez plus tard.', {'store': _store}),
              key: const Key('store-unavailable'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            if (elsewhere != null && elsewhere.isNotEmpty) ...[
              Text(
                context.tr('Votre abonnement Mara Pro paie déjà pour « {name} ». Un abonnement {store} couvre une seule entreprise.', {'name': elsewhere, 'store': _store}),
                key: const Key('store-elsewhere'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
            for (final p in [?month, ?year]) ...[
              _ProductTile(
                product: p,
                busy: _busy,
                onBuy: () => _buy(p),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
        if (_message != null) ...[
          const SizedBox(height: 4),
          Container(
            key: const Key('store-message'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _good ? kInk : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_message!,
                style: theme.textTheme.bodyMedium?.copyWith(color: _good ? kPaper : kInk)),
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
          const SizedBox(height: 6),
          TextButton.icon(
            key: const Key('store-manage'),
            onPressed: _manage,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(context.tr('Gérer mon abonnement')),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          context.tr('Mara Pro est un abonnement à renouvellement automatique{prices}. Le paiement est débité sur votre compte {store} à la confirmation de l\'achat. L\'abonnement se renouvelle automatiquement au même prix et pour la même durée, sauf s\'il est annulé au moins 24 heures avant la fin de la période en cours. Gérez-le ou annulez-le à tout moment dans les réglages de votre compte {store}.', {
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
  const _ProductTile({required this.product, required this.busy, required this.onBuy});

  final StoreProduct product;
  final bool busy;
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
                Text(year ? context.tr('Mara Pro · 1 an') : context.tr('Mara Pro · 1 mois'),
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
            onPressed: busy ? null : onBuy,
            style: FilledButton.styleFrom(backgroundColor: kInk, foregroundColor: kPaper),
            child: Text(context.tr('S\'abonner')),
          ),
        ],
      ),
    );
  }
}

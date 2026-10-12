import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/pay/wave_pay.dart';
import 'store_billing.dart';

/// What the store purchase listener has to say, drawn in the reader's
/// language wherever it lands (the Pro page, or a snackbar elsewhere).
class StoreNotice {
  const StoreNotice(this.text, {this.good = false, this.orgId});

  final String Function(BuildContext context) text;

  /// Mara Pro is on: said in the app's ink, not as a warning.
  final bool good;

  /// The business the purchase it is about names (132): only that
  /// business's Pro page draws it — never another's, so a refusal of one
  /// business's purchase is not shown on the next business's page. Null:
  /// any page (the page's own action, a purchase that names nobody).
  final String? orgId;

  /// Whether the Pro page of [org] draws it.
  bool isFor(String org) => orgId == null || orgId == org;
}

/// The Worker's refusals that no retry will change (review S3): the
/// purchase is finished (completed), its reason said and logged. Every
/// other refusal — an expired session, a caller who is not (yet) an
/// administrator, a server error, no network — leaves the purchase open:
/// the store hands it back at the next launch or « Restaurer mes achats »,
/// and Google does not refund what was never acknowledged in vain.
const storeRefusalsForGood = {
  'wrong_org', 'no_org', 'replayed', 'product', 'bundle', 'base_plan',
  'transaction', 'token', 'sandbox', 'platform', 'org',
};

/// The Worker's refusal, in the reader's language: by its code, never
/// the server's raw French (review nit).
String storeRefusalText(BuildContext context, StoreVerifyRefused e, String store) => switch (e.code) {
      'wrong_org' => context.tr('Cet achat a été fait pour une autre entreprise.'),
      'no_org' => context.tr('Cet achat ne dit pas pour quelle entreprise il a été fait.'),
      'replayed' => context.tr('Cet abonnement est déjà celui d\'une autre entreprise.'),
      'product' || 'base_plan' => context.tr('Cet achat n\'est pas Mara Pro.'),
      'bundle' => context.tr('Cet achat n\'est pas pour Mara.'),
      'transaction' || 'token' || 'platform' || 'org' => context.tr('Cet achat n\'a pas pu être lu par Mara.'),
      'sandbox' => context.tr('Achat de test refusé : un achat fait avec un compte de test (sandbox, TestFlight) n\'active Mara Pro que pour les comptes de test de Mara.'),
      'not_admin' => context.tr('Seul un administrateur de l\'entreprise peut l\'abonner à Mara Pro.'),
      'session' => context.tr('Votre session a expiré : reconnectez-vous, puis touchez « Restaurer mes achats ». Rien ne sera prélevé deux fois.'),
      _ => context.tr('Le paiement est fait, mais Mara n\'a pas encore pu le vérifier. Gardez une connexion et touchez « Restaurer mes achats » : rien ne sera prélevé deux fois.'),
    };

/// Every purchase the store reports, from the app's start (review S3) —
/// not only while the Pro page is open: Ask to Buy approved later, a
/// payment that was pending, Play's purchasesUpdated after the page was
/// left, a purchase left unfinished by an earlier run. One per app run in
/// the store builds (main.dart); the Pro page draws what it says.
///
/// Each purchase is verified for the business it was bought for — the
/// org id the store keeps with it ([StorePurchase.orgId]: Apple's
/// appAccountToken, Google's obfuscatedAccountId), or, when the store
/// does not say, the one the Worker reads from the store itself — never
/// the page that happens to be open. It is completed only on the Worker's
/// yes, or on a refusal for good ([storeRefusalsForGood]), said and
/// logged.
class StoreWatcher {
  StoreWatcher({
    required this.billing,
    required this.verify,
    this.onPro,
    this.log,
    this.outside,
  });

  final StoreBilling billing;

  /// The Worker's /store/verify (WavePay.verifyStore, with the purchase's
  /// own business).
  final Future<StoreVerdict> Function(StorePurchase purchase) verify;

  /// A business is on Pro now: read the session again.
  VoidCallback? onPro;

  /// Where a refusal is written (the crash reporter and the console in
  /// the app) — its code and product, never a token.
  final void Function(String line)? log;

  /// Shows a notice when no Pro page is open (a snackbar in the app).
  final void Function(StoreNotice notice)? outside;

  /// The last thing to say, for the Pro page.
  final notice = ValueNotifier<StoreNotice?>(null);

  /// Purchases heard so far (« Restaurer » says when it found none).
  int heard = 0;

  StreamSubscription<List<StorePurchase>>? _sub;

  /// The businesses whose Pro page is open (one entry per page).
  final List<String?> _pages = [];

  /// The purchases the Worker refused for good this run (132), by
  /// transaction or token: the store account still holds them, so the Pro
  /// page says so rather than offering a purchase the store will refuse.
  final Set<String> refused = {};

  /// Whether the store's subscription [owned] is one the Worker refused.
  bool refusedOwned(StoreOwned owned) =>
      refused.contains(owned.transactionId) || refused.contains(owned.token);

  String get _store => billing.platform == 'apple' ? 'App Store' : 'Google Play';

  /// Starts listening; once. The store hands back, at once, what an
  /// earlier run left unfinished.
  void start() {
    _sub ??= billing.purchases.listen((list) => unawaited(handle(list)), onError: (_) {});
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    notice.dispose();
  }

  /// A Pro page of [orgId] is open and draws its notices itself.
  void attach([String? orgId]) => _pages.add(orgId);
  void detach([String? orgId]) => _pages.remove(orgId);

  void _say(StoreNotice n) {
    notice.value = n;
    // No page open that draws it: said outside (a snackbar).
    final shown = _pages.any((page) => page == null || n.isFor(page));
    if (!shown) outside?.call(n);
  }

  Future<void> handle(List<StorePurchase> list) async {
    for (final p in list) {
      heard++;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          _say(StoreNotice((context) => context.tr('Achat en attente : {store} doit encore le confirmer (accord parental, paiement en cours). Mara Pro s\'activera dès qu\'il sera confirmé.', {'store': _store}), orgId: p.orgId));
        case StorePurchaseStatus.canceled:
          await _complete(p);
          _say(StoreNotice((context) => context.tr('Achat annulé : rien n\'a été prélevé.'), orgId: p.orgId));
        case StorePurchaseStatus.error:
          await _complete(p);
          // A cancel the store reports as an error says nothing alarming
          // and is not worth a report.
          if (!storeCancelled(p.errorCode, p.errorMessage)) {
            log?.call(storeErrorLine(billing.platform, p.productId, p.errorCode, p.errorMessage, p.errorDetails));
          }
          _say(StoreNotice((context) => storeErrorText(context, p.errorCode, p.errorMessage, _store), orgId: p.orgId));
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          await _verify(p);
      }
    }
  }

  Future<void> _complete(StorePurchase p) async {
    if (!p.needsCompletion) return;
    try {
      await billing.complete(p);
    } catch (_) {}
  }

  Future<void> _verify(StorePurchase p) async {
    final org = p.orgId;
    _say(StoreNotice((context) => context.tr('Vérification de l\'achat auprès de {store}…', {'store': _store}), orgId: org));
    try {
      final verdict = await verify(p);
      await _complete(p);
      final settled = verdict.orgId?.toLowerCase() ?? org;
      if (verdict.pro) {
        onPro?.call();
        _say(StoreNotice((context) => context.tr('Merci ! Mara Pro est actif.'), good: true, orgId: settled));
      } else {
        _say(StoreNotice(orgId: settled, (context) => switch (verdict.state) {
              'expired' => context.tr('Cet abonnement est terminé : il ne donne plus Mara Pro.'),
              'revoked' => context.tr('Cet abonnement a été remboursé : il ne donne plus Mara Pro.'),
              'on_hold' || 'paused' => context.tr('Le paiement de cet abonnement est en attente chez {store} : mettez à jour votre moyen de paiement dans {store}.', {'store': _store}),
              'pending' => context.tr('Achat en attente : {store} doit encore le confirmer (accord parental, paiement en cours). Mara Pro s\'activera dès qu\'il sera confirmé.', {'store': _store}),
              _ => context.tr('Cet achat ne donne pas Mara Pro à cette entreprise.'),
            }));
      }
    } on StoreVerifyRefused catch (e) {
      final forGood = storeRefusalsForGood.contains(e.code);
      // Logged either way: a refusal for good is a purchase Mara keeps
      // nothing of; a passing one that repeats is worth seeing too.
      log?.call('store purchase refused (${e.code.isEmpty ? e.status : e.code}, '
          '${forGood ? 'finished' : 'left open'}) ${billing.platform} ${p.productId}');
      if (forGood) {
        for (final key in [p.transactionId, p.token]) {
          if (key != null && key.isNotEmpty) refused.add(key);
        }
        await _complete(p);
      }
      _say(StoreNotice((context) => storeRefusalText(context, e, _store), orgId: org));
    } catch (_) {
      // The Worker was not reached: the purchase stays open, the store
      // hands it back.
      _say(StoreNotice((context) => context.tr('Le paiement est fait, mais Mara n\'a pas encore pu le vérifier. Gardez une connexion et touchez « Restaurer mes achats » : rien ne sera prélevé deux fois.'), orgId: org));
    }
  }
}

/// Whether what the store said is the person's own « Annuler » (132):
/// nothing alarming is said, and nothing reported.
bool storeCancelled(String? code, String? message) {
  final all = '${code ?? ''} ${message ?? ''}'.toLowerCase();
  return all.contains('usercancel') || all.contains('canceled') || all.contains('cancelled');
}

/// The store's own reason, short (132): Google's BillingResponse
/// (« itemAlreadyOwned »), StoreKit's code (« storekit2_failed_to_fetch_product »)
/// — what is said beside the friendly line, so a failure can be read
/// back. Null when the store gave nothing.
String? storeErrorCode(String? code, String? message) {
  String clean(String s) => s.replaceFirst('BillingResponse.', '').trim();
  final c = clean(code ?? '');
  final m = clean(message ?? '');
  // Google's generic code says nothing: its BillingResponse does.
  final picked = (c.isEmpty || c == 'purchase_error') && m.isNotEmpty && m.length <= 60 ? m : c;
  if (picked.isEmpty) return null;
  return picked.length > 60 ? '${picked.substring(0, 57)}…' : picked;
}

/// The line written to the crash reporter for a store failure (132): the
/// store, the product, its code, its words and details — never a token.
String storeErrorLine(String platform, String productId, String? code, String? message, [String? details]) =>
    'store purchase failed $platform $productId: code=${code ?? ''} message=${message ?? ''}'
    '${details == null || details.isEmpty ? '' : ' details=${details.length > 300 ? details.substring(0, 300) : details}'}';

/// A purchase the store itself refused, in the reader's language: the
/// friendly line, then the store's own code on a line of its own (132)
/// — « (App Store : storekit2_failed_to_fetch_product) ».
String storeErrorText(BuildContext context, String? code, String? message, String store) {
  final all = '${code ?? ''} ${message ?? ''}';
  if (storeCancelled(code, message)) {
    return context.tr('Achat annulé : rien n\'a été prélevé.');
  }
  final why = storeErrorCode(code, message);
  final line = all.contains('itemAlreadyOwned') || all.contains('alreadyOwned')
      ? context.tr('Ce compte {store} paie déjà Mara Pro, sans doute pour une autre de vos entreprises : un abonnement couvre une seule entreprise.', {'store': store})
      : context.tr('L\'achat n\'a pas pu se faire : {store} n\'a rien prélevé. Réessayez dans un moment.', {'store': store});
  return why == null ? line : '$line\n${context.tr('({store} : {code})', {'store': store, 'code': why})}';
}

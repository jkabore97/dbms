import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

/// Mara Pro inside the store apps (130): App Store In-App Purchase on the
/// iPhone (StoreKit 2), Google Play Billing on Android — the one file that
/// touches the `in_app_purchase` plugin, behind [StoreBilling] so the Pro
/// page and its tests never do.
///
/// The products, as created in each store (inactive until review):
///
/// * Apple — group « Mara Pro » (22464773): `bf.kaj.app.pro.monthly`
///   (1 month) and `bf.kaj.app.pro.yearly` (1 year), both level 1;
/// * Google — subscription `mara_pro`, base plans `monthly` (P1M) and
///   `yearly` (P1Y).
///
/// The price shown is always the store's own localized string, never one
/// written here: Apple and Google set it per country.
///
/// Pro is per business. The business's id rides inside the purchase —
/// Apple's appAccountToken (a UUID: the org id is one) and Google's
/// obfuscatedAccountId — so the payments Worker can check, with the store,
/// that the purchase it is shown was made for that business.
abstract class StoreBilling {
  /// 'apple' or 'google'.
  String get platform;

  Future<bool> available();

  /// Mara Pro's month and year, as this store sells them here.
  Future<List<StoreProduct>> products();

  /// Every purchase the store reports: new, restored, pending, failed —
  /// including those left unfinished by an earlier run.
  Stream<List<StorePurchase>> get purchases;

  Future<void> buy(StoreProduct product, {required String orgId});

  /// Apple's « Restaurer mes achats »; on Google Play, the purchases the
  /// account already holds.
  Future<void> restore();

  /// Tells the store the purchase is delivered — only after the Worker
  /// said so. Until then the store keeps offering it back.
  Future<void> complete(StorePurchase purchase);

  /// The store's own page where the subscription is changed or cancelled.
  Uri get manageUrl;
}

/// One of Mara Pro's two periods.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.period,
    required this.price,
    this.title = '',
    this.native,
  });

  /// Apple's product id, or Google's `mara_pro:<base plan>`.
  final String id;

  /// 'month' or 'year'.
  final String period;

  /// The store's localized price (« 4,99 $ », « 2 900 F CFA »).
  final String price;
  final String title;

  /// The plugin's own object, for [StoreBilling.buy].
  final Object? native;
}

enum StorePurchaseStatus { pending, purchased, restored, canceled, error }

class StorePurchase {
  const StorePurchase({
    required this.status,
    required this.productId,
    this.transactionId,
    this.token,
    this.errorCode,
    this.errorMessage,
    this.needsCompletion = false,
    this.native,
  });

  final StorePurchaseStatus status;
  final String productId;

  /// Apple: the transaction id the Worker asks the App Store about.
  final String? transactionId;

  /// Google: the purchase token the Worker asks Google Play about.
  final String? token;

  /// The plugin's error code and words, for [StorePurchaseStatus.error]
  /// (Google's « BillingResponse.itemAlreadyOwned » among them).
  final String? errorCode;
  final String? errorMessage;
  final bool needsCompletion;
  final Object? native;
}

const appleProducts = {
  'bf.kaj.app.pro.monthly': 'month',
  'bf.kaj.app.pro.yearly': 'year',
};
const googleProduct = 'mara_pro';
const googleBasePlans = {'monthly': 'month', 'yearly': 'year'};

/// The plugin, for real.
class PluginStoreBilling implements StoreBilling {
  PluginStoreBilling(this.platform);

  @override
  final String platform;

  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Future<bool> available() => _iap.isAvailable();

  @override
  Future<List<StoreProduct>> products() async {
    final ids = platform == 'apple' ? appleProducts.keys.toSet() : {googleProduct};
    final response = await _iap.queryProductDetails(ids);
    final out = <StoreProduct>[];
    for (final p in response.productDetails) {
      if (platform == 'apple') {
        final period = appleProducts[p.id];
        if (period != null) {
          out.add(StoreProduct(id: p.id, period: period, price: p.price, title: p.title, native: p));
        }
      } else if (p is GooglePlayProductDetails) {
        final index = p.subscriptionIndex;
        final offers = p.productDetails.subscriptionOfferDetails;
        if (index == null || offers == null) continue;
        final offer = offers[index];
        // The base plan itself, not a promotional offer on it.
        if (offer.offerId != null) continue;
        final period = googleBasePlans[offer.basePlanId];
        if (period == null) continue;
        out.add(StoreProduct(
          id: '$googleProduct:${offer.basePlanId}',
          period: period,
          price: p.price,
          title: p.title,
          native: p,
        ));
      }
    }
    out.sort((a, b) => a.period == 'month' ? -1 : (b.period == 'month' ? 1 : 0));
    return out;
  }

  @override
  Stream<List<StorePurchase>> get purchases =>
      _iap.purchaseStream.map((list) => [for (final p in list) _of(p)]);

  StorePurchase _of(PurchaseDetails p) {
    final status = switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      PurchaseStatus.error => StorePurchaseStatus.error,
    };
    return StorePurchase(
      status: status,
      productId: p.productID,
      transactionId: platform == 'apple' ? p.purchaseID : null,
      token: platform == 'google' ? p.verificationData.serverVerificationData : null,
      errorCode: p.error?.code,
      errorMessage: p.error?.message,
      needsCompletion: p.pendingCompletePurchase,
      native: p,
    );
  }

  @override
  Future<void> buy(StoreProduct product, {required String orgId}) async {
    final details = product.native as ProductDetails;
    final PurchaseParam param;
    if (platform == 'apple') {
      // StoreKit 2: applicationUserName becomes the appAccountToken.
      param = Sk2PurchaseParam(productDetails: details, applicationUserName: orgId);
    } else {
      final g = details as GooglePlayProductDetails;
      param = GooglePlayPurchaseParam(
        productDetails: g,
        offerToken: g.offerToken,
        // Play's obfuscatedAccountId.
        applicationUserName: orgId,
      );
    }
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(StorePurchase purchase) async {
    final native = purchase.native;
    if (native is PurchaseDetails && native.pendingCompletePurchase) {
      await _iap.completePurchase(native);
    }
  }

  @override
  Uri get manageUrl => platform == 'apple'
      ? Uri.parse('https://apps.apple.com/account/subscriptions')
      : Uri.parse('https://play.google.com/store/account/subscriptions'
          '?sku=$googleProduct&package=bf.kaj.app');
}

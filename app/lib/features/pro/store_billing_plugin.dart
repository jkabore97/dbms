import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import 'store_billing.dart';

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
    final orgId = switch (p) {
      SK2PurchaseDetails(:final appAccountToken) => appAccountToken,
      GooglePlayPurchaseDetails(:final billingClientPurchase) => billingClientPurchase.obfuscatedAccountId,
      _ => null,
    };
    return StorePurchase(
      status: status,
      productId: p.productID,
      transactionId: platform == 'apple' ? p.purchaseID : null,
      token: platform == 'google' ? p.verificationData.serverVerificationData : null,
      errorCode: p.error?.code,
      errorMessage: p.error?.message,
      needsCompletion: p.pendingCompletePurchase,
      orgId: orgId == null || orgId.isEmpty ? null : orgId.toLowerCase(),
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

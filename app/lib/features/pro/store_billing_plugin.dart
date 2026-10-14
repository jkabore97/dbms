import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart' show PurchaseStateWrapper;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart' show SK2Transaction;

import 'store_billing.dart';

/// The plugin, for real: Mara Pro (130) and the spots (142).
class PluginStoreBilling implements StoreBilling, SpotStoreBilling {
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
      errorDetails: p.error?.details?.toString(),
      needsCompletion: p.pendingCompletePurchase,
      orgId: orgId == null || orgId.isEmpty ? null : orgId.toLowerCase(),
      // A spot's promotion, on Google (142).
      profileId: p is GooglePlayPurchaseDetails ? _org(p.billingClientPurchase.obfuscatedProfileId) : null,
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
  Future<List<StorePurchase>> unfinishedSpots() async {
    if (platform == 'apple') {
      // StoreKit 2's Transaction.unfinished: a consumable paid but never
      // finished (the Worker never said yes) — « Vérifier un achat déjà
      // payé » on the iPhone, where restorePurchases hands back no
      // consumable. Finished by [complete] on the Worker's word.
      final left = await SK2Transaction.unfinishedTransactions();
      return [
        for (final t in left)
          if (appleSpotProducts.containsKey(t.productId))
            StorePurchase(
              status: StorePurchaseStatus.restored,
              productId: t.productId,
              transactionId: t.id,
              needsCompletion: true,
              orgId: _org(t.appAccountToken),
              native: t,
            ),
      ];
    }
    final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final past = await addition.queryPastPurchases();
    return [
      for (final p in past.pastPurchases)
        if (googleSpotProducts.containsKey(p.productID) && p.status != PurchaseStatus.pending &&
            p.billingClientPurchase.purchaseState == PurchaseStateWrapper.purchased)
          _of(p..status = PurchaseStatus.restored),
    ];
  }

  @override
  Future<List<SpotStoreProduct>> spotProducts() async {
    final ids = platform == 'apple' ? appleSpotProducts : googleSpotProducts;
    final response = await _iap.queryProductDetails(ids.keys.toSet());
    return [
      for (final p in response.productDetails)
        if (ids[p.id] case final kind?)
          SpotStoreProduct(
            id: p.id,
            kind: kind,
            price: p.price,
            rawPrice: p.rawPrice,
            currencyCode: p.currencyCode,
            native: p,
          ),
    ];
  }

  @override
  Future<void> buySpot(SpotStoreProduct product,
      {required String orgId, required String promotionId}) async {
    final details = product.native as ProductDetails;
    if (platform == 'apple') {
      // StoreKit 2: the spot rides as the appAccountToken (a UUID). A
      // consumable is finished (« consumed ») when the app completes it,
      // after the Worker's yes.
      await _iap.buyConsumable(
          purchaseParam: Sk2PurchaseParam(productDetails: details, applicationUserName: promotionId));
    } else {
      // Google: the business and the spot ride with the purchase. Not
      // consumed here: the Worker consumes it once the spot is programmed
      // (a purchase consumed before would be lost if the check failed).
      await _iap.buyConsumable(
          purchaseParam: GooglePlayPurchaseParam(
            productDetails: details as GooglePlayProductDetails,
            applicationUserName: orgId,
            obfuscatedProfileId: promotionId,
          ),
          autoConsume: false);
    }
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    final native = purchase.native;
    if (native is PurchaseDetails && native.pendingCompletePurchase) {
      await _iap.completePurchase(native);
    } else if (native is SK2Transaction) {
      // An unfinished spot read by [unfinishedSpots].
      final id = int.tryParse(native.id);
      if (id != null) await SK2Transaction.finish(id);
    }
  }

  @override
  Future<List<StoreOwned>> owned() async {
    if (platform == 'google') {
      final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      return [
        for (final p in response.pastPurchases)
          if (p.productID == googleProduct)
            StoreOwned(
              productId: p.productID,
              orgId: _org(p.billingClientPurchase.obfuscatedAccountId),
              token: p.verificationData.serverVerificationData,
            ),
      ];
    }
    // Apple: every transaction of the app (Transaction.all), the ones of
    // Mara Pro still running — a current entitlement.
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <StoreOwned>[];
    for (final t in await SK2Transaction.transactions()) {
      if (!appleProducts.containsKey(t.productId)) continue;
      final ends = int.tryParse(t.expirationDate ?? '');
      if (ends == null || ends <= now) continue;
      out.add(StoreOwned(productId: t.productId, orgId: _org(t.appAccountToken), transactionId: t.id));
    }
    return out;
  }

  static String? _org(String? id) => id == null || id.isEmpty ? null : id.toLowerCase();

  @override
  Uri get manageUrl => platform == 'apple'
      ? Uri.parse('https://apps.apple.com/account/subscriptions')
      : Uri.parse('https://play.google.com/store/account/subscriptions'
          '?sku=$googleProduct&package=bf.kaj.app');
}

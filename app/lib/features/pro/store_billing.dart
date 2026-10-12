/// Mara Pro inside the store apps (130): App Store In-App Purchase on the
/// iPhone (StoreKit 2), Google Play Billing on Android — behind
/// [StoreBilling] so the Pro page and its tests never touch the plugin;
/// store_billing_plugin.dart is the one file that does (loaded deferred,
/// so the web's first bundle carries none of it).
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

  /// The Mara Pro subscriptions this store account holds now (132):
  /// Google Play's purchases owned (queryPastPurchases), the App Store's
  /// current entitlements. One store account holds one, whatever the
  /// business: while it holds one, the store refuses a second purchase
  /// (Google: « You're already subscribed »; Apple would only change the
  /// one it has).
  Future<List<StoreOwned>> owned();
}

/// A Mara Pro subscription the store account holds (132).
class StoreOwned {
  const StoreOwned({required this.productId, this.orgId, this.transactionId, this.token});

  final String productId;

  /// The business it was bought for (appAccountToken / obfuscatedAccountId),
  /// null when the store does not say.
  final String? orgId;
  final String? transactionId;
  final String? token;
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
    this.errorDetails,
    this.needsCompletion = false,
    this.orgId,
    this.native,
  });

  final StorePurchaseStatus status;
  final String productId;

  /// The business the purchase was made for, as the store keeps it with
  /// the purchase (review S3): Apple's appAccountToken, Google's
  /// obfuscatedAccountId — the org id [StoreBilling.buy] passed. Null when
  /// the store does not say (an old purchase): the Worker then reads it
  /// from the store itself. Never the page that happens to be open.
  final String? orgId;

  /// Apple: the transaction id the Worker asks the App Store about.
  final String? transactionId;

  /// Google: the purchase token the Worker asks Google Play about.
  final String? token;

  /// The plugin's error code and words, for [StorePurchaseStatus.error]
  /// (Google's « BillingResponse.itemAlreadyOwned » among them).
  final String? errorCode;
  final String? errorMessage;

  /// The plugin's details (Google's debug message, StoreKit's own), for the
  /// log only.
  final String? errorDetails;
  final bool needsCompletion;
  final Object? native;
}

const appleProducts = {
  'bf.kaj.app.pro.monthly': 'month',
  'bf.kaj.app.pro.yearly': 'year',
};
const googleProduct = 'mara_pro';
const googleBasePlans = {'monthly': 'month', 'yearly': 'year'};

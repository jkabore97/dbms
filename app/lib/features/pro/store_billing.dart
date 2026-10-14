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
    this.profileId,
    this.native,
  });

  /// Google's obfuscatedProfileId (142): a spot bought in the Play app
  /// names its promotion there, beside the business in [orgId]. Apple has
  /// one appAccountToken: a spot's is its promotion, read from [orgId].
  final String? profileId;

  /// A spot (« Mettre en avant », 142), not Mara Pro.
  bool get isSpot => isSpotProduct(productId);

  /// The spot this purchase was made for (142): Google's profile id,
  /// Apple's appAccountToken. Null for Mara Pro or when the store does
  /// not say.
  String? get spotId => !isSpot ? null : (googleSpotProducts.containsKey(productId) ? profileId : orgId);

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

/// « Mettre en avant » in the stores (142), 7 days each: an article at the
/// head of « À la une », the whole vitrine at the top of the street — the
/// product ids the owner creates (Play Console: one-time consumable
/// products; App Store Connect: Consumable in-app purchases), their value
/// the spot's kind.
const googleSpotProducts = {
  'mara_spot_article_7': 'article',
  'mara_spot_shop_7': 'shop',
};
const appleSpotProducts = {
  'bf.kaj.app.spot.article7': 'article',
  'bf.kaj.app.spot.shop7': 'shop',
};

bool isSpotProduct(String id) =>
    googleSpotProducts.containsKey(id) || appleSpotProducts.containsKey(id);

/// The spot's product in [platform]'s store, for a spot of [kind].
String spotProductId(String platform, String kind) => platform == 'apple'
    ? (kind == 'shop' ? 'bf.kaj.app.spot.shop7' : 'bf.kaj.app.spot.article7')
    : (kind == 'shop' ? 'mara_spot_shop_7' : 'mara_spot_article_7');

/// One of the two spots, as this store sells it here (142).
class SpotStoreProduct {
  const SpotStoreProduct({
    required this.id,
    required this.kind,
    required this.price,
    this.rawPrice,
    this.currencyCode,
    this.native,
  });

  final String id;

  /// 'article' or 'shop'.
  final String kind;

  /// The store's localized price — what is shown and charged on Android
  /// and iPhone (ProductDetails.price), never a Mara price.
  final String price;

  /// The same, as a number and its currency (shown only: the Worker never
  /// takes a price from the app).
  final double? rawPrice;
  final String? currencyCode;
  final Object? native;
}

/// The spots through the store (142): beside [StoreBilling], so Mara Pro's
/// fakes in the tests need nothing new.
abstract class SpotStoreBilling {
  /// 'apple' or 'google'.
  String get platform;

  /// The two spots as this store sells them; empty when the store does
  /// not know them (not yet created, not yet approved).
  Future<List<SpotStoreProduct>> spotProducts();

  /// Buys [product] for the spot [promotionId] of [orgId]: Google keeps
  /// the business as obfuscatedAccountId and the spot as
  /// obfuscatedProfileId; Apple keeps the spot as appAccountToken. A
  /// consumable: Google's is consumed by the Worker once the spot is
  /// programmed, Apple's finished by the app.
  Future<void> buySpot(SpotStoreProduct product, {required String orgId, required String promotionId});

  /// What the store still holds unfinished (Google: an unconsumed spot),
  /// handed back to the listener to be verified again.
  Future<void> restore();

  /// The spots bought but never finished: Google's unconsumed purchases,
  /// Apple's unfinished transactions (StoreKit 2) — what a connection lost
  /// after paying left behind, verified again at the next start and on
  /// « Vérifier un achat déjà payé ».
  Future<List<StorePurchase>> unfinishedSpots();
}

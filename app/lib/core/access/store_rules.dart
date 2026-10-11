import 'package:flutter/foundation.dart' show visibleForTesting;

import '../update/update_check.dart' show installStore;

/// Whether this build may offer to buy Mara's digital goods: Mara Pro (the
/// subscription) and the paid spots on the street (« Mettre en avant »).
///
/// False in the iPhone app (`--dart-define=STORE=appstore`, codemagic.yaml),
/// true everywhere else (Google Play, the GitHub APK, the web). Apple's App
/// Review guideline 3.1.1 lets an iPhone app sell digital goods only
/// through Apple's in-app purchase, and forbids steering — a link, a
/// button or a sentence sending people to buy elsewhere. Mara Pro
/// and the spots are sold by card (Stripe) and Wave, so the iPhone app
/// sells neither and says nothing about where they are sold (125):
///
/// * no price of Pro or of a spot, no buy, pay or « Bientôt disponible »
///   panel, no « Passer à Pro » invitation, no Stripe page;
/// * what Pro includes is still described, a locked tool still says
///   « Cette fonction fait partie de Mara Pro. », a business already on
///   Pro shows « Active » with every tool open;
/// * cauris unlocks stay: cauris are earned, never bought;
/// * the « Mettre en avant » entry is gone; a spot already running still
///   shows as sponsored in the street.
///
/// What is not touched: shoppers paying shops for orders and delivery
/// (Wave, cash, card) — physical goods and services, which Apple allows to
/// be paid outside (3.1.3(e)); and the platform's own console.
///
/// Every screen asks here, never `installStore` itself, so the rule has
/// one place to change.
bool get sellsDigitalInApp =>
    debugSellsDigitalInApp ?? installStore != 'appstore';

/// A test's stand-in for the build flag (a `--dart-define` cannot change
/// inside one test run). Null: the build decides. Reset it in tearDown.
@visibleForTesting
bool? debugSellsDigitalInApp;

/// The store that sells Mara Pro inside this build (130): 'apple' in the
/// iPhone app (STORE=appstore), 'google' in the Play build (STORE=play),
/// null on the web and the GitHub APK — which keep Stripe and Wave.
String? get storeBillingPlatform =>
    debugStoreBillingPlatform ??
    switch (installStore) {
      'appstore' => 'apple',
      'play' => 'google',
      _ => null,
    };

@visibleForTesting
String? debugStoreBillingPlatform;

/// The platform's switch, plan_terms().store_billing_on (128), as the
/// session last read it: until the owner turns it on — once Apple and
/// Google both answer the payments Worker — the store apps keep the
/// behaviour above. Written by the session only (and by tests).
bool storeBillingOn = false;

/// Mara Pro is sold here through the store's own purchase — App Store
/// In-App Purchase, Google Play Billing (130): never Stripe or Wave beside
/// it. The spots (« Mettre en avant ») are not sold through the stores:
/// they keep [sellsDigitalInApp].
bool get sellsProThroughStore => storeBillingPlatform != null && storeBillingOn;

/// Whether this build may offer Mara Pro at all: through the store when
/// [sellsProThroughStore], by card and Wave where [sellsDigitalInApp].
/// Every « Passer à Pro » asks here.
bool get sellsProInApp => sellsProThroughStore || sellsDigitalInApp;

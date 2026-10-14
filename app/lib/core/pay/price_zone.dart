import 'package:intl/intl.dart';

import '../l10n/tr.dart' show intlLocale;

/// The three price zones of Mara's own prices — the spots (« Mettre en
/// avant ») and Mara Pro — as the owner types them in Réglages (139):
///
/// * XOF — the CFA franc. A business in XAF (Cameroon, Gabon…) pays the
///   same number, said « FCFA », and is charged in XAF;
/// * EUR — the euro area;
/// * USD — everywhere else.
///
/// The zone is the business's own currency (orgs.default_currency): the
/// database decides it the same way (price_zone, zone_currency), and is
/// the only one that charges — what is here is what the screens say.
///
/// Kept apart from core/format/money.dart on purpose: that file writes a
/// business's own money (no decimals, its own code); this one writes what
/// Mara charges, where a euro or a dollar has its cents.
enum PriceZone { xof, eur, usd }

PriceZone priceZoneOf(String? currency) {
  final c = (currency ?? '').trim().toUpperCase();
  if (c.isEmpty || c == 'XOF' || c == 'XAF') return PriceZone.xof;
  if (c == 'EUR') return PriceZone.eur;
  return PriceZone.usd;
}

/// The key the server's zones use: 'XOF', 'EUR', 'USD'.
String zoneKey(PriceZone zone) => switch (zone) {
      PriceZone.xof => 'XOF',
      PriceZone.eur => 'EUR',
      PriceZone.usd => 'USD',
    };

/// The currency a business of [currency] is charged in: its own CFA franc
/// (XOF or XAF, the same number), the euro, or the dollar.
String zoneCurrencyOf(String? currency) {
  final c = (currency ?? '').trim().toUpperCase();
  return switch (priceZoneOf(c)) {
    PriceZone.xof => c == 'XAF' ? 'XAF' : 'XOF',
    PriceZone.eur => 'EUR',
    PriceZone.usd => 'USD',
  };
}

/// What Mara charges, written for the reader: « 1 000 FCFA » (XOF and
/// XAF alike), « 1,99 € » / « €1.99 », « 4,99 \$ US » / « \$4.99 ». A
/// whole euro or dollar has no « ,00 ».
String zonePriceText(num amount, String currency, {String? language}) {
  final code = currency.trim().toUpperCase();
  final en = (language ?? '') == 'en' || (language == null && intlLocale() == 'en');
  final locale = en ? 'en_US' : 'fr_FR';
  if (code == 'XOF' || code == 'XAF') {
    // Grouped as it is written by hand here, whatever the language.
    return '${NumberFormat.decimalPattern('fr_FR').format(amount.round())} FCFA';
  }
  final whole = amount == amount.roundToDouble();
  final symbol = switch (code) {
    'EUR' => '€',
    'USD' => en ? r'$' : r'$ US',
    _ => code,
  };
  return NumberFormat.currency(locale: locale, symbol: symbol, decimalDigits: whole ? 0 : 2)
      .format(amount);
}

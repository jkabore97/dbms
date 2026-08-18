import 'package:intl/intl.dart';

/// The owner's exchange rates (039), and the little arithmetic around them.
///
/// One rule keeps everybody unlost: the business's home currency is the only
/// currency in the books. A rate here answers exactly one question — "the
/// customer holds dollars; how many do I collect?" — and one more at stock
/// entry: "I paid in cedis; what did that cost in francs?". Nothing in this
/// file touches a ledger.

/// One row of the rate table: 1 [currency] = [rate] in the home currency.
class CurrencyRate {
  const CurrencyRate({required this.currency, required this.rate});

  final String currency;
  final double rate;

  factory CurrencyRate.fromRow(Map<String, dynamic> r) => CurrencyRate(
        currency: r['currency'] as String,
        rate: (r['rate'] as num).toDouble(),
      );

  /// The home-currency value of [amount] in this currency.
  double toHome(double amount) => amount * rate;

  /// What to collect in this currency for a home-currency [total]. Kept at two
  /// decimals — the precision foreign cash actually has.
  double fromHome(double total) =>
      rate == 0 ? 0 : double.parse((total / rate).toStringAsFixed(2));
}

/// The currencies the picker offers, named in French. A code not listed can
/// still be typed — the list is a convenience, not a wall.
const knownCurrencies = <String, String>{
  'USD': 'Dollar américain',
  'EUR': 'Euro',
  'GHS': 'Cedi ghanéen',
  'NGN': 'Naira nigérian',
  'GBP': 'Livre sterling',
  'CAD': 'Dollar canadien',
  'XAF': 'Franc CFA (CEMAC)',
  'MAD': 'Dirham marocain',
  'CNY': 'Yuan chinois',
};

/// The CFA franc's fixed peg to the euro — the one rate that is law rather
/// than market. Offered as the pre-fill when a XOF business adds EUR; the
/// owner may still prefer their bank's effective rate.
const double eurXofPeg = 655.957;

/// Foreign amounts print with their own code and two decimals ("15,38 USD"),
/// never with the home currency's habits — 15 USD and 15 F must not look alike.
NumberFormat foreignMoneyFormat(String currency) => NumberFormat.currency(
      locale: 'fr_FR',
      symbol: currency,
      decimalDigits: 2,
    );

/// "1 USD = 600 F" — the one line a rate is ever shown as. Not moneyFormat:
/// amounts have no centimes here but a *rate* keeps its decimals, or the EUR
/// peg would print as 656 F and quietly disagree with the arithmetic.
String rateLabel(String currency, double rate, String homeCurrency) {
  final symbol = homeCurrency == 'XOF' ? 'F' : homeCurrency;
  final fmt = NumberFormat('#,##0.###', 'fr_FR');
  return '1 $currency = ${fmt.format(rate)} $symbol';
}

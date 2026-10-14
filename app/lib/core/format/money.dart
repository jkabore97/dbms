import 'package:intl/intl.dart';

import 'currencies.dart';

// Re-exported so a screen holding a `NumberFormat get _money` needs only this
// file, not its own intl import.
export 'package:intl/intl.dart' show NumberFormat;
export 'currencies.dart' show currencyDecimals, currencyName;

/// The one way money is written in this app.
///
/// Every amount on every screen goes through here, so a business that chose
/// its currency sees that currency everywhere — the sale sheet, the carnet,
/// the tontine, the payslip, the books — and not three different answers.
/// Before this, some screens showed the raw code ("XOF"), some showed nothing
/// at all, and some hardcoded "FCFA" regardless of what the business picked.
///
/// The rules:
///   * XOF and XAF both print as "FCFA" (144: the West African franc of
///     UEMOA and the Central African one of CEMAC are both « le franc CFA »
///     to the people who use them — a Douala shop read « 12 000 XAF »);
///     pickers still tell them apart by name (currencies.dart). Every other
///     currency prints as its own code (« 12,50 EUR »).
///   * The currency's own decimals (144, ISO 4217's minor units — see
///     currencies.dart): none for the franc CFA, the yen, the won… — a
///     centime of CFA franc does not exist, and a column of ",00" is a
///     column of noise —, two for the euro, the dollar, the real, the
///     naira, the cedi (and, while the books' columns keep two, the
///     dinars ISO gives three). Before 144 every
///     currency lost its cents, and « 12,50 EUR » read « 13 EUR ».
///   * fr_FR grouping, so 1 200 000 reads the way it is written by hand here.
NumberFormat moneyFormat(String currency) => NumberFormat.currency(
      locale: 'fr_FR',
      symbol: currencySymbol(currency),
      decimalDigits: currencyDecimals(currency),
    );

/// The symbol moneyFormat writes after an amount — for the places that
/// show it alone, such as an amount field's suffix. Never add it after
/// moneyFormat(...).format(...): the amount already carries it (UI audit
/// C-1, A-2: « 160 000 FCFA XOF »).
String currencySymbol(String currency) => isFrancCfa(currency) ? 'FCFA' : currency;

/// One of the two francs CFA — XOF (UEMOA) or XAF (CEMAC): no centimes,
/// written « FCFA », pegged to the euro at 655,957.
bool isFrancCfa(String currency) => currency == 'XOF' || currency == 'XAF';

/// What a person typed as an amount — the one reader of every amount and
/// quantity field (144: FlowNumberField.read is this too, so the same
/// text is the same number everywhere). Null when it is not a number.
///
/// Thousands are written here with a space, a dot or a comma, decimals
/// with a comma or a dot:
///   * « 1 000 », « 45.000 », « 1.000.000 » — thousands;
///   * « 12,50 », « 12.50 », « 2,5 » — decimals;
///   * both marks: the last is the decimal one — « 1.000,50 » and
///     « 1,000.50 » are a thousand and a half;
///   * one comma before exactly three digits (« 12,500 ») is thousands in
///     a money without centimes or with no money given (« 45,000 »), but
///     decimals in a money with them: in euros the person typed the comma
///     as the decimal mark, « 12,500 » is 12,5 — never 12 500.
///   * « 0.500 », « 0,500 » — decimals (no number starts with a 0 group).
///
/// Given the [currency], the amount must fit its money: a franc CFA has no
/// centimes, so « 12,50 » in FCFA is refused (null), not saved as 12,5 F;
/// the euro two decimals (« 12,505 » is refused; « 12,500 » is 12,5). The
/// value is then rounded to the money's decimals.
double? parseAmount(String text, {String? currency}) {
  var t = text.trim().replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
  if (t.isEmpty) return null;
  final negative = t.startsWith('-');
  if (negative) t = t.substring(1);
  if (!RegExp(r'^[0-9.,]+$').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) return null;
  final decimals = currency == null ? null : currencyDecimals(currency);
  final dots = '.'.allMatches(t).length, commas = ','.allMatches(t).length;
  String whole, fraction = '';
  if (dots > 0 && commas > 0) {
    final mark = t.lastIndexOf('.') > t.lastIndexOf(',') ? '.' : ',';
    final group = mark == '.' ? ',' : '.';
    final at = t.lastIndexOf(mark);
    if (mark.allMatches(t).length > 1) return null;
    whole = t.substring(0, at);
    fraction = t.substring(at + 1);
    if (whole.contains(mark) || !RegExp('^\\d{1,3}(\\$group\\d{3})*\$').hasMatch(whole)) return null;
    whole = whole.replaceAll(group, '');
  } else if (dots + commas == 0) {
    whole = t;
  } else {
    final mark = dots > 0 ? '.' : ',';
    final grouping = RegExp('^[1-9]\\d{0,2}(\\$mark\\d{3})+\$').hasMatch(t);
    final count = dots + commas;
    if (count > 1) {
      if (!grouping) return null;
      whole = t.replaceAll(mark, '');
    } else if (grouping && (mark == '.' || decimals == null || decimals == 0)) {
      whole = t.replaceAll(mark, '');
    } else {
      final at = t.indexOf(mark);
      whole = t.substring(0, at);
      fraction = t.substring(at + 1);
    }
  }
  if (whole.isEmpty) whole = '0';
  final value = double.tryParse(fraction.isEmpty ? whole : '$whole.$fraction');
  if (value == null) return null;
  final signed = negative ? -value : value;
  if (decimals == null) return signed;
  final places = fraction.replaceFirst(RegExp(r'0+$'), '').length;
  if (places > decimals) return null;
  return roundToCurrency(signed, currency!);
}

/// [value] rounded to [currency]'s decimals (144): 18,9 yen is 19 yen,
/// a franc CFA has no centimes — what is saved is what the money has.
double roundToCurrency(double value, String currency) {
  final d = currencyDecimals(currency);
  return double.parse(value.toStringAsFixed(d));
}

/// [value] as it is put back in an amount field, in [currency]'s own
/// decimals (144): « 13 » for 12,6 francs CFA, « 12,50 » for 12,5 euros —
/// never rounded to the unit, which made a 12,50 € invoice's payment
/// « 13 », more than is owed.
String amountField(double value, String currency) => amountFieldIn(value, currencyDecimals(currency));

/// [amountField] with the decimals given (a NumberFormat's own).
String amountFieldIn(double value, int decimals) =>
    decimals <= 0 ? value.round().toString() : value.toStringAsFixed(decimals).replaceAll('.', ',');

/// Why [text] is not an amount in [currency] (144), or null when it is
/// one (or is empty): no centimes in a money without, no more decimals
/// than the money has. Said under the field, in French (translated where
/// shown).
String? amountProblem(String text, String currency) {
  final t = text.trim();
  if (t.isEmpty || parseAmount(t, currency: currency) != null) return null;
  if (parseAmount(t) == null) return 'Ce n\'est pas un montant';
  final d = currencyDecimals(currency);
  return d == 0
      ? 'Pas de centimes en {money}'
      : 'Au plus {n} chiffres après la virgule';
}

import 'package:intl/intl.dart';

// Re-exported so a screen holding a `NumberFormat get _money` needs only this
// file, not its own intl import.
export 'package:intl/intl.dart' show NumberFormat;

/// The one way money is written in this app.
///
/// Every amount on every screen goes through here, so a business that chose
/// its currency sees that currency everywhere — the sale sheet, the carnet,
/// the tontine, the payslip, the books — and not three different answers.
/// Before this, some screens showed the raw code ("XOF"), some showed nothing
/// at all, and some hardcoded "FCFA" regardless of what the business picked.
///
/// The rules, unchanged from what the accounting screens already did:
///   * XOF prints as "FCFA", the name people actually use for the franc here;
///     every other currency prints as its own code.
///   * No decimals — a centime of CFA franc does not exist, and a column of
///     ",00" is a column of noise. (A business on EUR or USD loses the
///     centime too; acceptable until a decimal currency is a real user.)
///   * fr_FR grouping, so 1 200 000 reads the way it is written by hand here.
NumberFormat moneyFormat(String currency) => NumberFormat.currency(
      locale: 'fr_FR',
      symbol: currency == 'XOF' ? 'FCFA' : currency,
      decimalDigits: 0,
    );

/// What a person typed as an amount. Thousands are written here with a
/// space, a dot or a comma — « 45 000 », « 45.000 », « 45,000 » are all
/// forty-five thousand — while « 2,5 » and « 2.5 » are two and a half.
/// Null when it is not a number.
double? parseAmount(String text) {
  final t = text.trim().replaceAll(RegExp(r'[\s\u00A0\u202F]'), '');
  if (t.isEmpty) return null;
  if (RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(t)) {
    return double.tryParse(t.replaceAll(RegExp(r'[.,]'), ''));
  }
  return double.tryParse(t.replaceAll(',', '.'));
}

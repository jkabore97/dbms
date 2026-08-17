import 'package:intl/intl.dart';

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

import '../l10n/tr.dart';

/// Stock never goes below zero (101). The server refuses at the point the
/// count is written — the till, a credit sale, a vitrine order accepted, a
/// production, a farm's feed — with one sentence naming the article and
/// what is left. The app says the same sentence before it asks, so the
/// person reads one rule wherever they meet it.

/// A count as the server writes it: 3, not 3.000; 2.5 stays 2.5.
String stockQty(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  return q
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// « Il ne reste que 3 Savon », or « Plus de Savon en stock » when nothing
/// is left — 101's stock_short_message(), in [language].
String stockShortMessage(String language, String name, double left) =>
    left <= 0
        ? translate(language, 'Plus de {name} en stock', {'name': name})
        : translate(language, 'Il ne reste que {n} {name}',
            {'n': stockQty(left), 'name': name});

/// The server's sentence read back in [language]; null for any other.
String? stockShortText(String language, String message) {
  final left = RegExp(r'^Il ne reste que (\S+) (.+)$').firstMatch(message);
  if (left != null) {
    return translate(language, 'Il ne reste que {n} {name}',
        {'n': left.group(1), 'name': left.group(2)});
  }
  final none = RegExp(r'^Plus de (.+) en stock$').firstMatch(message);
  if (none != null) {
    return translate(language, 'Plus de {name} en stock', {'name': none.group(1)});
  }
  return null;
}

/// Whether [message] is the server refusing for want of stock: a refusal
/// that retrying will not change, so a queued sale stops being retried.
bool isStockRefusal(String message) => stockShortText('fr', message) != null;

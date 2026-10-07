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

/// The SQLSTATE every stock refusal carries (101), so the outbox knows a
/// refusal from a lost signal by its code before it reads the words.
const stockRefusalCode = 'MA001';

/// French elides « de » before a vowel or an h: « Plus d'Aliment », « Plus
/// d'huile » — as the server's sentence does.
final _elides = RegExp(r'^[AEIOUYHÀÂÄÉÈÊËÎÏÔÖÙÛÜŒÆaeiouyhàâäéèêëîïôöùûüœæ]');

String _nothingLeft(String language, String name) => _elides.hasMatch(name)
    ? translate(language, 'Plus d\'{name} en stock', {'name': name})
    : translate(language, 'Plus de {name} en stock', {'name': name});

/// « Il ne reste que 3 Savon », or « Plus de Savon en stock » when nothing
/// is left — 101's stock_short_message(), in [language].
String stockShortMessage(String language, String name, double left) =>
    left <= 0
        ? _nothingLeft(language, name)
        : translate(language, 'Il ne reste que {n} {name}',
            {'n': stockQty(left), 'name': name});

final _leftPattern = RegExp(r'^Il ne reste que (\S+) (.+)$');
final _nonePattern = RegExp(r"^Plus d(?:e |')(.+) en stock$");

/// The server's sentence read back in [language]; null for any other.
String? stockShortText(String language, String message) {
  final left = _leftPattern.firstMatch(message);
  if (left != null) {
    return translate(language, 'Il ne reste que {n} {name}',
        {'n': left.group(1), 'name': left.group(2)});
  }
  final none = _nonePattern.firstMatch(message);
  if (none != null) return _nothingLeft(language, none.group(1)!);
  return null;
}

/// The article and what is left, read from the server's sentence: what a
/// refused sale's « Corriger le stock » opens on. Null for any other text.
({String name, double left})? stockShortItem(String message) {
  final left = _leftPattern.firstMatch(message);
  if (left != null) {
    return (
      name: left.group(2)!,
      left: double.tryParse(left.group(1)!) ?? 0,
    );
  }
  final none = _nonePattern.firstMatch(message);
  if (none != null) return (name: none.group(1)!, left: 0);
  return null;
}

/// Whether [message] is the server refusing for want of stock: a refusal
/// that retrying will not change, so a queued sale stops being retried.
/// The words are the fallback; [code] (the SQLSTATE) is asked first.
bool isStockRefusal(String message, {String? code}) =>
    code == stockRefusalCode || stockShortText('fr', message) != null;

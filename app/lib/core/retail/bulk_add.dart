/// Parsing for the multi-line quick add: one product per line, typed or
/// pasted, twenty articles in one save.
///
/// The format is what somebody would naturally write in a hurry:
///
///     nom quantité prix_de_vente [coût]
///     Savon 20 300
///     Sucre 1kg 10 600 450
///     Huile 2,5 1500
///
/// The rule, stated once and tested: tokens split on whitespace, and up to
/// three *trailing* numeric tokens are read back-to-front as quantity,
/// sale price, and optional cost. Everything before them is the name —
/// which is why "Sucre 1kg" survives intact: "1kg" is not a number, so the
/// walk stops there. Comma decimals are accepted ("2,5"), because that is
/// how a French keyboard writes them.
library;

/// One parsed line: either a product ready to save, or the reason it is not.
class BulkLine {
  const BulkLine({
    required this.lineNumber,
    required this.raw,
    this.name,
    this.quantity,
    this.salePrice,
    this.costPrice,
    this.error,
  });

  final int lineNumber;
  final String raw;
  final String? name;
  final double? quantity;
  final double? salePrice;
  final double? costPrice;

  /// French, shown beside the line. Null means the line is good.
  final String? error;

  bool get ok => error == null;
}

double? _num(String token) =>
    double.tryParse(token.replaceAll(',', '.').replaceAll(' ', ''));

/// Parses the whole box. Blank lines are skipped; every non-blank line
/// comes back either good or with the sentence that fixes it.
List<BulkLine> parseBulkLines(String text) {
  final out = <BulkLine>[];
  final lines = text.split('\n');
  // Names already claimed by a good line above, lowercased the same way
  // ensure_product() matches them (011). A second line with the same name is
  // not a second article: the server would fold it into the first, and the
  // quantity typed on this line would silently stack onto the other's. That is
  // the "I typed ten, only eight appeared" report — commonest when two
  // products differ only by a size the parser reads as a quantity ("Sac ciment
  // 50 8000" and "Sac ciment 25 5000" are both "Sac ciment"). Caught here so
  // the person renames one rather than losing it.
  final seenNames = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty) continue;
    final lineNumber = i + 1;

    final tokens = raw.split(RegExp(r'\s+'));
    final numbers = <double>[];
    var nameEnd = tokens.length;
    while (nameEnd > 0 && numbers.length < 3) {
      final n = _num(tokens[nameEnd - 1]);
      if (n == null) break;
      numbers.insert(0, n);
      nameEnd--;
    }
    final name = tokens.take(nameEnd).join(' ').trim();

    if (name.isEmpty) {
      out.add(BulkLine(
          lineNumber: lineNumber, raw: raw, error: 'Il manque le nom.'));
      continue;
    }
    if (numbers.length < 2) {
      out.add(BulkLine(
          lineNumber: lineNumber,
          raw: raw,
          error: 'Il faut au moins la quantité et le prix : '
              '« $name 10 600 ».'));
      continue;
    }

    final quantity = numbers[0];
    final salePrice = numbers[1];
    final costPrice = numbers.length > 2 ? numbers[2] : null;

    if (quantity <= 0) {
      out.add(BulkLine(
          lineNumber: lineNumber,
          raw: raw,
          error: 'La quantité doit être supérieure à zéro.'));
      continue;
    }
    if (salePrice < 0 || (costPrice != null && costPrice < 0)) {
      out.add(BulkLine(
          lineNumber: lineNumber,
          raw: raw,
          error: 'Un prix ne peut pas être négatif.'));
      continue;
    }
    final key = name.toLowerCase();
    if (!seenNames.add(key)) {
      out.add(BulkLine(
          lineNumber: lineNumber,
          raw: raw,
          error: 'Doublon : « $name » est déjà plus haut. '
              'Renommez-le (ex. « $name 25kg ») ou retirez la ligne.'));
      continue;
    }

    out.add(BulkLine(
      lineNumber: lineNumber,
      raw: raw,
      name: name,
      quantity: quantity,
      salePrice: salePrice,
      costPrice: costPrice,
    ));
  }
  return out;
}

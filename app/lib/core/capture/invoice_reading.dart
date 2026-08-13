/// A photographed delivery note, turned into lines a shopkeeper can confirm.
///
/// This is the piece M5's demo actually stands on: *she photographs a delivery
/// invoice and the products are in the system without typing.* A reading that
/// only fills in a caption does not do that. Neither does one that offers a
/// single product when the paper has nine on it.
///
/// **Arithmetic is what makes this safe.** A line on an invoice is a name and
/// two or three numbers, and which number is which is genuinely ambiguous —
/// `Savon 12 500` is either twelve at five hundred or one at twelve thousand
/// five hundred. Guessing wrong puts a wrong count and a wrong cost into the
/// books, and the shopkeeper finds out weeks later when the shelf and the
/// stock disagree.
///
/// So the rule is: **a line is only offered when the numbers check out.**
/// `quantity × unitPrice == total` is a coincidence that does not happen by
/// accident on a misread line, and where there is no total to check against,
/// the reading is offered with a quantity of one — a shape a person corrects
/// in one tap instead of a number they have to notice is wrong.
///
/// Everything here is pure and static so it can be tested against real labels
/// with no camera, no phone and no plugin. The intended way to fix a bad
/// reading is to paste the invoice that failed into the test file.
library;

/// One line of a delivery note: what arrived, how many, what each cost.
class InvoiceLine {
  const InvoiceLine({
    required this.name,
    required this.quantity,
    required this.unitCost,
    this.checked = false,
  });

  final String name;
  final double quantity;

  /// What the shop paid per unit. Cost, never a shelf price: this is a
  /// *delivery* note, and treating a supplier's price as the selling price
  /// would put the shop's margin at zero without saying so.
  final double unitCost;

  /// True when `quantity × unitCost` matched a total printed on the line.
  /// The confirm screen shows the unchecked ones differently, because those
  /// are the ones worth a second look.
  final bool checked;

  double get lineTotal => quantity * unitCost;

  InvoiceLine copyWith({String? name, double? quantity, double? unitCost}) =>
      InvoiceLine(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitCost: unitCost ?? this.unitCost,
        checked: checked,
      );
}

class InvoiceReading {
  const InvoiceReading._();

  /// Pulls every line that looks like a delivered product out of raw OCR text.
  ///
  /// Returns an empty list rather than a guess when nothing is confidently
  /// readable. An empty list is a good outcome: the photograph is still filed,
  /// and the person types what they would have typed anyway.
  static List<InvoiceLine> parse(String? text) {
    if (text == null || text.trim().isEmpty) return const [];

    final lines = <InvoiceLine>[];
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = _parseLine(raw.trim());
      if (line != null) lines.add(line);
    }
    return lines;
  }

  /// A line is read twice, because `Savon 12 500` is genuinely two different
  /// deliveries.
  ///
  /// French writes twelve thousand five hundred as `12 500`, and a column of
  /// figures writes twelve at five hundred the same way. No amount of staring
  /// at one line settles it — but a line that also carries a total does
  /// settle it, because only one of the two readings multiplies out.
  ///
  /// So both tokenisations are tried and the one whose arithmetic checks is
  /// taken. When neither checks, the French reading wins: a shop's invoice is
  /// written by a person in French, and columns on a real delivery note are
  /// separated by several spaces rather than one, which the grouped reading
  /// leaves alone anyway.
  static InvoiceLine? _parseLine(String raw) {
    final grouped = _read(raw, groupThousands: true);
    if (grouped != null && grouped.checked) return grouped;

    final split = _read(raw, groupThousands: false);
    if (split != null && split.checked) return split;

    return grouped ?? split;
  }

  static InvoiceLine? _read(String raw, {required bool groupThousands}) {
    if (raw.isEmpty || raw.length > 120) return null;
    if (_isHeaderOrFooter(raw)) return null;

    // "2 x Riz 25kg 9000" — the quantity announces itself, which is the one
    // unambiguous shape and so is checked first.
    final leading = RegExp(r'^(\d{1,4})\s*[x×*]\s*(.+)$', caseSensitive: false)
        .firstMatch(raw);
    if (leading != null) {
      final quantity = double.parse(leading.group(1)!);
      final rest = leading.group(2)!;
      final numbers = _numbersIn(rest, groupThousands: groupThousands);
      final name = _nameIn(rest);
      if (name == null || numbers.isEmpty) return null;

      // With a total as well, the unit price is the one that multiplies to it.
      if (numbers.length >= 2 && _close(quantity * numbers[0], numbers[1])) {
        return InvoiceLine(
            name: name,
            quantity: quantity,
            unitCost: numbers[0],
            checked: true);
      }
      return InvoiceLine(
          name: name, quantity: quantity, unitCost: numbers.last);
    }

    final numbers = _numbersIn(raw, groupThousands: groupThousands);
    final name = _nameIn(raw);
    if (name == null || name.length < 3 || numbers.isEmpty) return null;

    // Three numbers: quantity, unit, total — but only if they multiply. The
    // same three numbers that do not multiply are a reference, a weight and a
    // price, and offering them as a delivery would be inventing stock.
    if (numbers.length >= 3) {
      for (var i = 0; i + 2 < numbers.length; i++) {
        final q = numbers[i];
        final u = numbers[i + 1];
        final t = numbers[i + 2];
        if (q > 0 && q == q.roundToDouble() && q <= 10000 && _close(q * u, t)) {
          return InvoiceLine(
              name: name, quantity: q, unitCost: u, checked: true);
        }
      }
    }

    // Two numbers that multiply into nothing checkable. If the first is a
    // plausible whole count it is a quantity and the second a unit price;
    // otherwise this is a name and a price, quantity one.
    if (numbers.length == 2) {
      final q = numbers[0];
      if (q > 0 && q == q.roundToDouble() && q <= 500 && numbers[1] > 0) {
        return InvoiceLine(name: name, quantity: q, unitCost: numbers[1]);
      }
      return InvoiceLine(name: name, quantity: 1, unitCost: numbers.last);
    }

    // One number: a price, and one of them.
    if (numbers.length == 1 && numbers[0] > 0) {
      return InvoiceLine(name: name, quantity: 1, unitCost: numbers[0]);
    }

    return null;
  }

  /// Lines that are about the invoice rather than about a product. Left in,
  /// they arrive as products called "TOTAL" and "Merci de votre confiance".
  static bool _isHeaderOrFooter(String line) {
    const words = [
      'total', 'sous-total', 'sous total', 'montant', 'net à payer',
      'net a payer', 'tva', 'facture', 'bon de livraison', 'client',
      'fournisseur', 'date', 'merci', 'signature', 'reference', 'référence',
      'designation', 'désignation', 'qte', 'qté', 'quantite', 'quantité',
      'prix unitaire', 'p.u', 'pu ', 'remise', 'acompte', 'solde',
      'telephone', 'téléphone', 'adresse', 'nif', 'rccm',
    ];
    final lower = line.toLowerCase();
    return words.any((w) => lower.startsWith(w) || lower == w.trim());
  }

  /// Every number on the line, in order, with thousands separators removed.
  ///
  /// A date is skipped rather than read as three numbers — a delivery note
  /// almost always carries one, and 12/08/2026 becoming a quantity of twelve
  /// at a price of eight is exactly the kind of nonsense that arithmetic
  /// checking cannot catch because it very nearly works.
  static List<double> _numbersIn(String line, {required bool groupThousands}) {
    var cleaned = line.replaceAll(
        RegExp(r'\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\b'), ' ');

    // "25kg" is a size, not a price or a count. Left in, it becomes the unit
    // cost of a sack of rice and the arithmetic never checks out again.
    cleaned = cleaned.replaceAll(
        RegExp(r'\d+(?:[.,]\d+)?\s*(kg|g|l|ml|cl|pcs?|pi[eè]ces?)\b',
            caseSensitive: false),
        ' ');

    final pattern = groupThousands
        ? RegExp(r'\d{1,3}(?:[  .]\d{3})+|\d+(?:[.,]\d{1,2})?')
        : RegExp(r'\d+(?:,\d{1,2})?');

    final numbers = <double>[];
    for (final match in pattern.allMatches(cleaned)) {
      final text = match.group(0)!;
      // A grouped number ("12 500") has its separators stripped; a plain one
      // may carry a decimal comma.
      final normalised = RegExp(r'[  .]\d{3}').hasMatch(text)
          ? text.replaceAll(RegExp(r'[  .]'), '')
          : text.replaceAll(',', '.');
      final value = double.tryParse(normalised);
      if (value != null) numbers.add(value);
    }
    return numbers;
  }

  /// The words on the line, with the numbers and the units taken out.
  static String? _nameIn(String line) {
    var text = line.replaceAll(
        RegExp(r'\b\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}\b'), ' ');

    // Units first, so "25kg" does not leave a bare "kg" behind.
    text = text.replaceAll(
        RegExp(r'\d+(?:[.,]\d+)?\s*(kg|g|l|ml|cl|pcs?|pi[eè]ces?|cartons?|sacs?)\b',
            caseSensitive: false),
        ' ');
    text = text.replaceAll(RegExp(r'\d{1,3}(?:[  .]\d{3})+|\d+(?:[.,]\d{1,2})?'), ' ');
    text = text.replaceAll(RegExp(r'\b[x×*]\b', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'\b(f\s?cfa|fcfa|xof|frs?|€|eur)\b',
        caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'[|:;=]+'), ' ');
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    // A name has to be mostly letters. What is left of a line of reference
    // numbers after the digits are removed is punctuation, not a product.
    final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(text).length;
    if (letters < 3 || letters < text.length * 0.5) return null;

    return text;
  }

  /// Within one unit, or one part in a thousand for larger amounts. OCR reads
  /// a 0 as an 8 often enough that exact equality would reject half the lines
  /// that are perfectly readable by eye.
  static bool _close(double a, double b) {
    if (a == b) return true;
    final tolerance = b.abs() < 1000 ? 1.0 : b.abs() * 0.001;
    return (a - b).abs() <= tolerance;
  }
}

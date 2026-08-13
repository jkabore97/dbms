import 'text_reader_stub.dart' if (dart.library.io) 'text_reader_mobile.dart'
    as impl;

/// Reading the words off a photograph, on the device, with no connection.
///
/// **This is an accelerator and nothing else.** It pre-fills a form that a
/// person then confirms. Nothing it produces is ever written to a product, a
/// price or an expiry date on its own — a misread date that silently became
/// `products.expires_on` is the exact loss the retail module exists to
/// prevent, with the app's name on it. `013_capture.sql` says the same thing
/// from the other side: nothing in the schema reads `ocr_text`.
///
/// Android only. ML Kit has no web implementation, so the plugin import lives
/// in `text_reader_mobile.dart` and is reached through a conditional import —
/// the web build compiles `text_reader_stub.dart` instead and never sees the
/// package at all. [isAvailable] is checked again at runtime because
/// `dart.library.io` is also true in a Dart VM, which is where the tests run.
class TextReader {
  const TextReader._();

  /// Whether this device can read text off an image.
  ///
  /// False on web, false in a test, false on anything that is not Android or
  /// iOS. Every caller must handle false as the ordinary case rather than as
  /// an error — capture works perfectly without it, which is the whole reason
  /// OCR could be added last.
  static bool get isAvailable => impl.isAvailable;

  /// The text in the image at [path], or null when nothing could be read.
  ///
  /// Never throws: a failed reading is not a failed capture, and the
  /// photograph is already safe by the time this runs.
  static Future<String?> read(String path) => impl.readText(path);
}

/// What a phone thought it saw, turned into things a form can be filled with.
///
/// Deliberately conservative. Every field is nullable and a field it is not
/// sure about is left null rather than guessed at: a blank box costs one
/// person ten seconds, and a wrong price silently accepted costs a shop money
/// for as long as nobody notices.
class ReadingSuggestions {
  const ReadingSuggestions({
    this.name,
    this.price,
    this.expiresOn,
    this.barcode,
  });

  /// The longest plausible product-name line — most of a label is the name,
  /// in the largest text, and OCR reads that most reliably.
  final String? name;

  /// A price, if exactly one line looked like one. Two candidates means
  /// neither is offered: picking the larger would be inventing a shelf price.
  final double? price;

  final DateTime? expiresOn;
  final String? barcode;

  bool get isEmpty =>
      name == null && price == null && expiresOn == null && barcode == null;

  /// Pulls what it can out of raw OCR text.
  ///
  /// Pure and static so it can be tested without a camera, a phone or a
  /// plugin — which matters, because this is the part that will be wrong in
  /// ways nobody predicted, and the only way to fix it is to add the real
  /// label that failed as a test case.
  static ReadingSuggestions parse(String? text) {
    if (text == null || text.trim().isEmpty) return const ReadingSuggestions();

    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return ReadingSuggestions(
      name: _name(lines),
      price: _price(lines),
      expiresOn: _expiry(lines),
      barcode: _barcode(lines),
    );
  }

  // ----------------------------------------------------------------

  /// The longest line that is mostly letters. A label's biggest text is its
  /// name; lines that are mostly digits are prices, weights and codes.
  static String? _name(List<String> lines) {
    String? best;
    for (final line in lines) {
      if (line.length < 3 || line.length > 60) continue;

      final letters = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(line).length;
      if (letters < line.length * 0.6) continue;

      // Words a label prints about itself rather than about the product.
      if (_isNoise(line)) continue;

      if (best == null || line.length > best.length) best = line;
    }
    return best;
  }

  static bool _isNoise(String line) {
    const noise = [
      'prix',
      'price',
      'exp',
      'expire',
      'peremption',
      'péremption',
      'fabrication',
      'lot',
      'net',
      'poids',
      'made in',
      'total',
      'tva',
    ];
    final lower = line.toLowerCase();
    return noise.any((n) => lower.startsWith(n));
  }

  /// A price, and only when there is exactly one candidate.
  ///
  /// Two numbers that both look like money — a unit price and a total, say —
  /// mean the picture is ambiguous, and offering the larger would be the app
  /// inventing a shelf price. Better to leave the box empty.
  static double? _price(List<String> lines) {
    final found = <double>{};

    for (final line in lines) {
      // Anchored at both ends, and that is the whole of it. Unanchored, this
      // pulled 2026 out of "EXP 04/2026" and a 3 out of "M4RS3ILL3" — a price
      // invented from a date and from a misread letter.
      //
      // So: either a labelled line ("PRIX 500", "TOTAL 1500 F") or a bare
      // amount alone on its line ("500", "1 500 FCFA"). A number in the
      // middle of anything else is not a price. `total` and `montant` are
      // here not to be offered but to be *counted* — a label showing both a
      // unit price and a total is ambiguous, and the rule below is that
      // ambiguity offers nothing.
      final match = RegExp(
        r'^(?:(?:prix|price|pu|total|montant)\s*)?[:=]?\s*'
        r'(\d{1,3}(?:[ .,]\d{3})*|\d+)(?:[.,](\d{1,2}))?'
        r'\s*(?:f\s?cfa|fcfa|xof|f|€|eur)?$',
        caseSensitive: false,
      ).firstMatch(line.toLowerCase());
      if (match == null) continue;

      final whole = match.group(1)!.replaceAll(RegExp(r'[ .,]'), '');
      final cents = match.group(2);
      final value = double.tryParse(cents == null ? whole : '$whole.$cents');

      // A price of zero is not a price, and six figures on a shelf label in
      // XOF is far more likely to be a phone number or a barcode fragment.
      if (value == null || value <= 0 || value > 99999999) continue;

      // A bare number with no currency and no label, that is also 8+ digits,
      // is a code rather than money.
      if (whole.length >= 8) continue;

      found.add(value);
    }

    return found.length == 1 ? found.first : null;
  }

  /// An expiry date in any of the shapes a label prints one.
  ///
  /// Day-first throughout: this app is used in Burkina Faso and the ambiguous
  /// 03/04/2026 is the third of April there. Guessing the American reading
  /// would move an expiry by up to eleven months, which is the one error this
  /// module cannot afford to make quietly — and is why the date is shown for
  /// confirmation and never applied on its own.
  static DateTime? _expiry(List<String> lines) {
    for (final line in lines) {
      final lower = line.toLowerCase();

      // dd/mm/yyyy, dd-mm-yy, dd.mm.yyyy
      final full =
          RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})').firstMatch(lower);
      if (full != null) {
        final date = _build(
          int.parse(full.group(1)!),
          int.parse(full.group(2)!),
          int.parse(full.group(3)!),
        );
        if (date != null) return date;
      }

      // mm/yyyy — common on tins, and means the end of that month.
      final month = RegExp(r'(?:exp|péremption|peremption|dlc|dluo)[^0-9]{0,6}'
              r'(\d{1,2})[/.\-](\d{2,4})')
          .firstMatch(lower);
      if (month != null) {
        final m = int.parse(month.group(1)!);
        final y = _year(int.parse(month.group(2)!));
        if (m >= 1 && m <= 12) {
          // The last day of the month: a tin marked 04/2026 is good through
          // April, not until the first of it.
          return DateTime(y, m + 1, 0);
        }
      }
    }
    return null;
  }

  static DateTime? _build(int day, int month, int rawYear) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final year = _year(rawYear);
    final date = DateTime(year, month, day);
    // Rejects 31/02: DateTime rolls it forward rather than failing.
    if (date.day != day || date.month != month) return null;
    return date;
  }

  static int _year(int raw) => raw >= 100 ? raw : 2000 + raw;

  /// 8, 12 or 13 digits on a line of their own — EAN-8, UPC-A, EAN-13.
  /// Anything else is a lot number or a phone number.
  static String? _barcode(List<String> lines) {
    for (final line in lines) {
      final digits = line.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length != line.replaceAll(' ', '').length) continue;
      if (digits.length == 8 || digits.length == 12 || digits.length == 13) {
        return digits;
      }
    }
    return null;
  }
}

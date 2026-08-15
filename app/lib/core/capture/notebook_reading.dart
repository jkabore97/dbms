import 'dart:convert';

import 'invoice_reading.dart';

/// Parsing for the handwriting reader's response.
///
/// The Worker's /read-page returns `{"lines": [{"name", "quantity",
/// "unit_price"}]}`, already sanitised — but this parser trusts nothing
/// anyway: an entry missing a field, a non-positive quantity, or a body
/// that is not the expected shape all degrade to "no lines" rather than a
/// crash. The person retakes the photo, which is the fix either way.
List<InvoiceLine> parseNotebookLines(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  if (decoded is! Map || decoded['lines'] is! List) return const [];

  final out = <InvoiceLine>[];
  for (final entry in decoded['lines'] as List) {
    if (entry is! Map) continue;
    final name = entry['name'];
    final quantity = entry['quantity'];
    final unitPrice = entry['unit_price'];
    if (name is! String || name.trim().isEmpty) continue;
    if (quantity is! num || quantity <= 0) continue;
    if (unitPrice is! num || unitPrice < 0) continue;
    out.add(InvoiceLine(
      name: name.trim(),
      quantity: quantity.toDouble(),
      unitCost: unitPrice.toDouble(),
      // The reader's arithmetic was never printed on the page, so nothing
      // here is "checked" — the confirm screen shows every line as worth a
      // second look, which for handwriting is the truth.
    ));
  }
  return out;
}

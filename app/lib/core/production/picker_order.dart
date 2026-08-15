import '../retail/models.dart';

/// Orders the shelf for the production picker.
///
/// At two hundred articles an alphabetical list buries the ten things a
/// maker actually cooks with. This puts them on top instead: what recent
/// runs consumed first, then everything flagged as an ingredient, then the
/// rest — alphabetically inside each band. The interface stays small
/// however large the catalogue grows, with no folders for anybody to
/// maintain.
///
/// [recentNames] are lowercased, trimmed ingredient names from the run
/// history — the caller already holds the history, so recency costs no
/// extra fetch and no schema.
List<Product> orderForPicking(List<Product> products, Set<String> recentNames) {
  int band(Product p) {
    if (recentNames.contains(p.name.trim().toLowerCase())) return 0;
    if (p.isIngredient) return 1;
    return 2;
  }

  final sorted = [...products];
  sorted.sort((a, b) {
    final byBand = band(a) - band(b);
    if (byBand != 0) return byBand;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return sorted;
}

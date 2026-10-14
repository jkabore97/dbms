import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/storefront/status_articles.dart';

/// A service shared from a shop that also sells goods is called a service
/// (the browser run: « Annonce : Tresses » under « ARTICLES »).
void main() {
  const pagne = PublicItem(id: 'a', name: 'Pagne wax', price: 15000, inStock: true);
  const tresses = PublicItem(
      id: 's', name: 'Tresses', price: 5000, inStock: true, isService: true);
  const both = [pagne, tresses];

  test('the chosen service alone: services', () {
    expect(StatusArticlesSheet.speaksServices(both, ['s']), isTrue);
  });

  test('an article among the chosen: articles', () {
    expect(StatusArticlesSheet.speaksServices(both, ['s', 'a']), isFalse);
  });

  test('nothing chosen: as the catalogue is', () {
    expect(StatusArticlesSheet.speaksServices(both, const []), isFalse);
    expect(StatusArticlesSheet.speaksServices([tresses], const []), isTrue);
  });
}

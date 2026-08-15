import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/production/picker_order.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/retail/models.dart';

/// The client half of the transformation tool: rows parse, the payload keys
/// match what record_production() expects, and a build with no server says
/// so instead of crashing.
///
/// The SQL half — the cost arithmetic, the counts, the refusals, the
/// privacy — is proven by test_production.sql.
void main() {
  group('a run parses what the server sends', () {
    test('a run with its ingredient list', () {
      final run = ProductionRun.fromRow({
        'run_id': 'r1',
        'product_name': 'Gâteau',
        'quantity': 40,
        'total_cost': 4500,
        'unit_cost': 112.5,
        'occurred_at': '2026-08-15T08:00:00Z',
        'inputs': [
          {'name': 'Farine', 'quantity': 5},
          {'name': 'Huile', 'quantity': 2},
        ],
      });
      expect(run.productName, 'Gâteau');
      expect(run.quantity, 40);
      expect(run.unitCost, 112.5);
      expect(run.inputs, hasLength(2));
      expect(run.inputs.first.name, 'Farine');
      expect(run.inputs.first.quantity, 5);
    });

    test('a run with no inputs does not crash the list', () {
      final run = ProductionRun.fromRow({
        'run_id': 'r1',
        'product_name': 'Savon',
        'quantity': 10,
        'total_cost': 0,
        'unit_cost': 0,
        'occurred_at': '2026-08-15T08:00:00Z',
        'inputs': null,
      });
      expect(run.inputs, isEmpty);
    });
  });

  group('the payload matches record_production()', () {
    // The SQL reads {product_id, quantity} from each element of p_inputs;
    // a drifted key would fail on somebody's phone days later, not here.
    test('an input draft serializes with the SQL keys', () {
      final draft =
          const ProductionInputDraft(productId: 'p1', quantity: 2.5).toJson();
      expect(draft, {'product_id': 'p1', 'quantity': 2.5});
    });
  });

  group('the picker keeps a big shelf small', () {
    // Two hundred articles must not bury the ten things the maker actually
    // cooks with: recently used first, then flagged ingredients, then the
    // rest — alphabetical inside each band.
    test('recently cooked with floats above flags, flags above the rest', () {
      final products = [
        const Product(id: '1', name: 'Zeste'),
        const Product(id: '2', name: 'Farine', isIngredient: true),
        const Product(id: '3', name: 'Ampoule'),
        const Product(id: '4', name: 'Huile', isIngredient: true),
        const Product(id: '5', name: 'Sucre'),
      ];
      final ordered = orderForPicking(products, {'sucre', 'huile'});
      expect(ordered.map((p) => p.name).toList(),
          ['Huile', 'Sucre', 'Farine', 'Ampoule', 'Zeste']);
    });

    test('with no history, flagged ingredients lead alphabetically', () {
      final products = [
        const Product(id: '1', name: 'Savon'),
        const Product(id: '2', name: 'Karité', isIngredient: true),
      ];
      final ordered = orderForPicking(products, const {});
      expect(ordered.first.name, 'Karité');
    });
  });

  group('a build with no server says so', () {
    test('production refuses politely', () {
      final production = ProductionRepository(null);
      expect(production.isConfigured, isFalse);
      expect(() => production.history('org'), throwsStateError);
    });
  });
}

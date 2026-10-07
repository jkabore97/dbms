import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/sale_sheet.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Three bugs of the audit, each caught where a person meets it.
///
///   * The till sold past the shelf in silence (ELIM SHOP: 7 articles below
///     zero). Since 101 it does not sell past the shelf at all: it says
///     what is left and records nothing.
///   (The association's dial and the courier's page: association_dial_test
///   and courier_recheck_test.)
class _Till extends RetailRepository {
  _Till() : super(null);

  int recorded = 0;

  @override
  Future<String> recordSale({
    required String orgId,
    required List<SaleLineDraft> lines,
    String method = 'cash',
    String? note,
    String? clientUuid,
    String? deviceId,
    String? customerName,
    String? customerPhone,
  }) async {
    recorded++;
    return 'sale-$recorded';
  }
}

Widget _fr(Widget home) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('the till', () {
    Future<_Till> sell(WidgetTester tester, Product product, String qty) async {
      tester.view.physicalSize = const Size(700, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final till = _Till();
      await tester.pumpWidget(_fr(Scaffold(
        body: SaleSheet(orgId: 'o1', retail: till, products: [product]),
      )));
      await tester.pump();
      await tester.tap(find.text(product.name).first);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Quantité'), qty);
      await tester.pump();
      await tester.tap(find.text('Ajouter au panier'));
      await tester.pump();
      final save = find.text('Enregistrer la vente');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      return till;
    }

    testWidgets('selling past the shelf is blocked, with what is left (101)',
        (tester) async {
      final till = await sell(
          tester,
          const Product(id: 'p1', name: 'Savon', salePrice: 450, quantity: 2),
          '5');
      expect(find.text('Il ne reste que 2 Savon'), findsOneWidget);
      expect(till.recorded, 0, reason: 'nothing is sold past the shelf');
    });

    testWidgets('nothing on the shelf: nothing sold (101)', (tester) async {
      final till = await sell(
          tester,
          const Product(id: 'p1', name: 'Pain', salePrice: 150, quantity: 0),
          '20');
      expect(find.text('Plus de Pain en stock'), findsOneWidget);
      expect(till.recorded, 0);
    });

    testWidgets('within stock: no word at all', (tester) async {
      final till = await sell(
          tester,
          const Product(id: 'p1', name: 'Sucre', salePrice: 750, quantity: 9),
          '3');
      expect(find.textContaining('Il ne reste'), findsNothing);
      expect(till.recorded, 1);
    });

    testWidgets('a service has no stock to run out of', (tester) async {
      final till = await sell(
          tester,
          const Product(
              id: 'p1', name: 'Coiffure', salePrice: 2000, isService: true),
          '2');
      expect(till.recorded, 1);
    });
  });

}

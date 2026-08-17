import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/production/production_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The tap-to-edit half of editable production: a run is listed, "Modifier"
/// opens the correction sheet, and the fix is sent to update_production_run.
/// The server's re-derivation of the unit cost and its refusals are proven by
/// test_production_edit.sql; this proves the screen sends the correction.
class _FakeProduction extends ProductionRepository {
  _FakeProduction() : super(null);

  final List<Map<String, Object?>> updates = [];

  @override
  Future<List<ProductionRun>> history(String orgId) async => [
        ProductionRun(
          runId: 'run-1',
          productName: 'Gâteau',
          quantity: 20,
          totalCost: 500,
          unitCost: 25,
          occurredAt: DateTime(2026, 8, 1),
        ),
      ];

  @override
  Future<void> updateRun(String runId,
      {double? quantity, String? productName, String? note}) async {
    updates.add({'id': runId, 'quantity': quantity, 'name': productName});
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  testWidgets('a production run is corrected in place', (tester) async {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final production = _FakeProduction();

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: ProductionScreen(
        org: const OrgSummary(
            id: 'o1', name: 'Atelier', profile: 'retail', roles: ['owner']),
        production: production,
        retail: RetailRepository(null),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('20 × Gâteau'), findsOneWidget);

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Corriger la production'), findsOneWidget);

    // It was 40, not 20.
    await tester.enterText(
        find.widgetWithText(TextField, 'Quantité produite'), '40');
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();

    expect(production.updates.single['id'], 'run-1');
    expect(production.updates.single['quantity'], 40.0);
    expect(production.updates.single['name'], 'Gâteau');
  });
}

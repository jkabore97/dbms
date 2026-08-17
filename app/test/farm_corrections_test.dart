import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/features/farm/farm_corrections.dart';

/// The tap-to-edit half of editable farm entries: a wrong count is listed,
/// long-pressed, and corrected through update_herd_event. The server refusals
/// (observer, zero harvest) are proven by test_farm_edits.sql; this proves the
/// sheet reads the entries and sends the correction.
class _FakeFarm extends FarmRepository {
  _FakeFarm() : super(null);

  final List<Map<String, Object?>> updates = [];

  @override
  Future<List<Map<String, dynamic>>> herdEvents(String herdId) async => [
        {
          'id': 'he-1',
          'kind': 'mortality',
          'quantity': 70, // a fat-fingered 70
          'note': null,
          'occurred_on': '2026-08-01',
        },
      ];

  @override
  Future<void> updateHerdEvent(
    String eventId, {
    double? quantity,
    String? kind,
    String? note,
    DateTime? occurredOn,
  }) async {
    updates.add({'id': eventId, 'quantity': quantity, 'kind': kind});
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  testWidgets('a herd entry is listed and corrected in place', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final farm = _FakeFarm();

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showFarmCorrections(
                context,
                title: 'Troupeau A',
                farm: farm,
                kind: FarmEntryKind.herd,
                subjectId: 'herd-1',
                canWrite: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The entry is listed with its (wrong) count.
    expect(find.textContaining('Mortalité · 70'), findsOneWidget);

    // Long-press opens the correction sheet with the value prefilled.
    await tester.longPress(find.textContaining('Mortalité · 70'));
    await tester.pumpAndSettle();
    expect(find.text('Corriger l’entrée'), findsOneWidget);

    // Fix 70 -> 7 and save.
    await tester.enterText(find.byType(TextField).first, '7');
    await tester.tap(find.text('Enregistrer la correction'));
    await tester.pumpAndSettle();

    expect(farm.updates.single['id'], 'he-1');
    expect(farm.updates.single['quantity'], 7.0);
    expect(farm.updates.single['kind'], 'mortality');
  });
}

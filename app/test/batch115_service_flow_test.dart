import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/services/service_flow.dart';
import 'package:kaj_app/features/services/services_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// « Service », one entry at a time (115, W1) — the shop's, the farm's and
/// the association's (legacy church included).
class _Books extends RetailRepository {
  _Books() : super(null);
  final created = <String>[];
  final saved = <Map<String, Object?>>[];
  final durations = <String>[];

  @override
  Future<void> setServiceDuration(String productId, int? minutes, {String? description}) async =>
      durations.add('$productId $minutes $description');

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async => const [];

  @override
  Future<Map<String, String>> photoKeys(String orgId) async => const {};

  @override
  Future<String> ensureProduct({
    required String orgId,
    required String name,
    double? salePrice,
    double? costPrice,
    String? barcode,
    DateTime? expiresOn,
    bool isService = false,
  }) async {
    created.add('$name service=$isService price=$salePrice');
    return 's-${created.length}';
  }

  @override
  Future<void> updateProduct(
    String productId, {
    String? name,
    double? salePrice,
    double? costPrice,
    DateTime? expiresOn,
    double? lowStockAt,
    bool? isActive,
    bool? isIngredient,
    bool? isPublished,
    String? description,
    String? unit,
    DateTime? availableFrom,
    bool clearAvailableFrom = false,
    double? quantity,
    bool? isService,
    bool? priceFrom,
    bool? stockTracked,
  }) async =>
      saved.add({
        'unit': unit,
        'published': isPublished,
        'description': description,
        'service': isService,
        'from': priceFrom,
      });
}

void main() {
  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
  }

  for (final kind in ['retail', 'farm', 'association', 'church']) {
    testWidgets('$kind: name → price « à partir de » → duration → vitrine → saved as a service',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final books = _Books();
      final org = OrgSummary(id: 'o1', name: 'X', profile: kind, roles: const ['owner']);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: ServicesScreen(org: org, retail: books),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('services-add')));
      await tester.pumpAndSettle();
      expect(find.text('Quel service ?'), findsOneWidget, reason: 'no camera: no photo step');
      expect(find.byKey(const Key('flow-next')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('service-flow-name')), 'Cours de couture');
      await tester.pump();
      await next(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed, isNull,
          reason: 'a price first');
      await tester.tap(find.byKey(const Key('flow-option-true')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('service-flow-price')), '2000');
      await tester.tap(find.byKey(const ValueKey('service-flow-unit-séance')));
      await tester.pump();
      await next(tester);
      expect(find.text('Combien de temps ?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('duration-120')));
      await tester.pump();
      await next(tester);
      expect(find.text('Décrivez-le en quelques mots'), findsOneWidget);
      expect(find.text('Passer'), findsOneWidget, reason: 'empty: « Passer »');
      await tester.enterText(find.byKey(const Key('service-flow-description')), 'Fil et tissu fournis');
      await tester.pump();
      expect(find.text('Suivant'), findsOneWidget);
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-option-false')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.textContaining('À partir de'), findsOneWidget);
      expect(find.text('2\u00a0h'), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pumpAndSettle();
      expect(books.created, ['Cours de couture service=true price=2000.0']);
      expect(books.saved, [
        {
          'unit': 'séance',
          'published': false,
          'description': null,
          'service': true,
          'from': true,
        },
        // The words their own write (136): a refusal never takes the name,
        // the price and the vitrine with it.
        {'unit': null, 'published': null, 'description': 'Fil et tissu fournis', 'service': null, 'from': null},
      ]);
      expect(books.durations, ['s-1 120 Fil et tissu fournis'],
          reason: 'its own field since 136, not the description');
      expect(find.text('Cours de couture ajouté'), findsOneWidget);
      await tester.tap(find.byKey(const Key('service-another')));
      await tester.pumpAndSettle();
      expect(find.text('Quel service ?'), findsOneWidget);
    });
  }

  testWidgets('no duration: the description is left alone', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final books = _Books();
    await tester.pumpWidget(MaterialApp(
      home: ServiceFlow(
          org: const OrgSummary(id: 'o1', name: 'X', profile: 'retail', roles: ['owner']),
          retail: books,
          store: MemoryFlowStore()),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('service-flow-name')), 'Coupe');
    await tester.pump();
    await next(tester);
    await tester.enterText(find.byKey(const Key('service-flow-price')), '1500');
    await tester.pump();
    await next(tester);
    await next(tester);
    await next(tester); // 136: no description
    await next(tester);
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(books.saved.single['description'], isNull);
    expect(books.durations, isEmpty);
    expect(books.saved.single['published'], isTrue, reason: 'on the vitrine by default, as before');
  });
}

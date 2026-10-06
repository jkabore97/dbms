import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/association/trust_repository.dart';
import 'package:kaj_app/features/church/trust_screen.dart';

/// The association's trust level (088): the card on the home, the five
/// pillars each with what to do, and Mara's switch for its admins only.
class _Trust extends TrustRepository {
  _Trust() : super(null);

  bool verified = false;
  final calls = <bool>[];

  @override
  Future<TrustLevel?> trust(String orgId) async => TrustLevel.fromJson({
        'level': verified ? 'Exemplaire' : 'Fiable',
        'met': verified ? 5 : 4,
        'verified_at': verified ? '2026-10-01T10:00:00Z' : null,
        'pillars': [
          {'key': 'verified', 'met': verified},
          {'key': 'regular', 'met': true, 'value': 7, 'target': 6},
          {'key': 'justified', 'met': true, 'value': 9, 'of': 10},
          {'key': 'clean', 'met': true, 'value': 1, 'of': 30},
          {'key': 'lasting', 'met': true, 'value': 200, 'target': 182},
        ],
      });

  @override
  Future<void> setVerified(String orgId, bool v) async {
    calls.add(v);
    verified = v;
  }
}

void main() {
  Future<void> pumpFor(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the card on the home says the level and opens the pillars',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrustCard(orgId: 'a1', repository: _Trust()))));
    await pumpFor(tester);
    expect(find.text('NIVEAU DE CONFIANCE'), findsOneWidget);
    expect(find.byKey(const Key('trust-level')), findsOneWidget);
    expect(find.text('Fiable'), findsOneWidget);

    await tester.tap(find.byKey(const Key('trust-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pillar-verified')), findsOneWidget);
    expect(find.text('Des dépenses justifiées'), findsOneWidget);
    expect(find.text('9 dépenses sur 10 ont leur reçu.'), findsOneWidget);
    expect(find.textContaining('Demandez-le à votre contact Mara'), findsOneWidget);
    expect(find.byKey(const Key('trust-verify')), findsNothing,
        reason: 'only Mara verifies');
  });

  testWidgets('a platform admin ticks « Vérifiée par Mara »', (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _Trust();
    await tester.pumpWidget(MaterialApp(
        home: TrustScreen(orgId: 'a1', repository: repo, platformAdmin: true)));
    await pumpFor(tester);
    await tester.tap(find.byKey(const Key('trust-verify')));
    await pumpFor(tester);
    expect(repo.calls, [true]);
    expect(find.text('Exemplaire'), findsOneWidget);
    expect(find.text('Mara a vérifié qui vous êtes.'), findsOneWidget);
  });

  testWidgets('nothing at all when the server has no level', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TrustCard(orgId: 'a1'))));
    await pumpFor(tester);
    expect(find.byKey(const Key('trust-card')), findsNothing);
  });
}

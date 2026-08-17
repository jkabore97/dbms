import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/features/admin/trainers_screen.dart';

/// The console's trainer roster (038). A fake repository answers from memory so
/// the screen pumps with no server.
class _FakeConsole extends ConsoleRepository {
  _FakeConsole(this._trainers) : super(null);
  final List<Trainer> _trainers;

  @override
  Future<List<Trainer>> trainers() async => _trainers;
}

void main() {
  Widget host(ConsoleRepository console) =>
      MaterialApp(home: TrainersScreen(console: console));

  testWidgets('lists trainers with their assignment counts', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(_FakeConsole(const [
      Trainer(
          userId: 'u1',
          fullName: 'Fatou Kaboré',
          phone: '+22670000001',
          assignments: 3),
      Trainer(
          userId: 'u2', fullName: null, phone: '+22670000002', assignments: 0),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('Fatou Kaboré'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // A trainer with no name falls back to the phone as its label.
    expect(find.text('+22670000002'), findsWidgets);
    expect(find.text('Ajouter un formateur'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no trainers',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(_FakeConsole(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Aucun formateur pour le moment'), findsOneWidget);
  });
}

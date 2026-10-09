import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The shared one-entry-at-a-time flow (115, W1).
class _Flow extends StatefulWidget {
  const _Flow({required this.store, required this.saved});
  final FlowStore store;
  final List<String> saved;
  @override
  State<_Flow> createState() => _FlowState();
}

class _FlowState extends State<_Flow> {
  final _name = TextEditingController();
  bool _credit = false;
  final _who = TextEditingController();
  final _flow = StepFlowController();

  @override
  Widget build(BuildContext context) => StepFlow(
        title: 'Essai',
        controller: _flow,
        store: widget.store,
        draft: FlowDraft(
          key: 'test',
          save: () => {'name': _name.text, 'credit': _credit, 'who': _who.text},
          restore: (a) => setState(() {
            _name.text = (a['name'] as String?) ?? '';
            _credit = a['credit'] == true;
            _who.text = (a['who'] as String?) ?? '';
          }),
        ),
        steps: [
          FlowStep(
            id: 'name',
            title: 'Quel nom ?',
            isValid: () => _name.text.trim().isNotEmpty,
            builder: (_) => TextField(
                key: const Key('name'),
                controller: _name,
                onChanged: (_) => setState(() {})),
          ),
          FlowStep(
            id: 'pay',
            title: 'Comment ?',
            builder: (_) => FlowChoice<bool>(
              options: const [
                FlowOption(false, 'Espèces'),
                FlowOption(true, 'Crédit'),
              ],
              value: _credit,
              onChanged: (v) => setState(() => _credit = v),
            ),
          ),
          FlowStep(
            id: 'who',
            title: 'Qui ?',
            shown: () => _credit,
            isValid: () => _who.text.trim().isNotEmpty,
            builder: (_) => TextField(
                key: const Key('who'),
                controller: _who,
                onChanged: (_) => setState(() {})),
          ),
        ],
        summary: (_) => FlowSummary(rows: [
          FlowSummaryRow('Nom', _name.text, step: 'name'),
          FlowSummaryRow('Paiement', _credit ? 'Crédit' : 'Espèces'),
        ]),
        onSave: () async {
          if (_name.text == 'boom') throw StateError('Refusé par le serveur');
          widget.saved.add(_name.text);
          return true;
        },
        done: (_) => FlowDone(
          message: '${_name.text} enregistré',
          actions: [
            FlowAction(
              key: const Key('again'),
              label: 'Un autre',
              icon: Icons.add,
              onPressed: () {
                setState(() {
                  _name.clear();
                  _credit = false;
                });
                _flow.restart();
              },
            ),
          ],
        ),
      );
}

Widget _host(FlowStore store, List<String> saved, List<bool?> closed) =>
    MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                closed.add(await StepFlow.push(context, _Flow(store: store, saved: saved))),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  bool nextEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('flow-next'))).onPressed != null;

  testWidgets('one question per screen, Suivant only when valid, summary, save, done',
      (tester) async {
    final saved = <String>[];
    final closed = <bool?>[];
    await tester.pumpWidget(_host(MemoryFlowStore(), saved, closed));
    await open(tester);

    expect(find.text('Quel nom ?'), findsOneWidget);
    expect(find.text('Étape 1 sur 3'), findsOneWidget, reason: '2 shown steps + summary');
    expect(nextEnabled(tester), isFalse);
    await tester.enterText(find.byKey(const Key('name')), 'Awa');
    await tester.pump();
    expect(nextEnabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();

    // A step that comes with an answer is counted once it is shown.
    expect(find.text('Comment ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-option-true')));
    await tester.pumpAndSettle();
    expect(find.text('Étape 2 sur 4'), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
    expect(find.text('Qui ?'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('who')), 'Moussa');
    await tester.pump();
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flow-summary')), findsOneWidget);
    expect(find.text('Vérifiez avant d\'enregistrer'), findsOneWidget);
    // « Modifier » goes back to the step.
    await tester.tap(find.byKey(const Key('flow-edit-name')));
    await tester.pumpAndSettle();
    expect(find.text('Quel nom ?'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(saved, ['Awa']);
    expect(find.text('C\'est fait'), findsOneWidget);
    expect(find.text('Awa enregistré'), findsOneWidget);

    // « Un autre »: back to step 1, empty.
    await tester.tap(find.byKey(const Key('again')));
    await tester.pumpAndSettle();
    expect(find.text('Quel nom ?'), findsOneWidget);
    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('back is the previous step; on step 1 it asks before leaving',
      (tester) async {
    final closed = <bool?>[];
    await tester.pumpWidget(_host(MemoryFlowStore(), [], closed));
    await open(tester);
    await tester.enterText(find.byKey(const Key('name')), 'Awa');
    await tester.pump();
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();

    // The system back (Android, or 114's browser back): previous step.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Quel nom ?'), findsOneWidget);
    expect(find.byKey(const Key('unsaved-dialog')), findsNothing);

    // On step 1 with something typed: asked; Rester stays.
    await tester.tap(find.byKey(const Key('flow-back')));
    await tester.pumpAndSettle();
    expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('unsaved-stay')));
    await tester.pumpAndSettle();
    expect(find.text('Quel nom ?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('flow-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsaved-leave')));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(closed, [false]);
  });

  testWidgets('nothing typed: step 1 back leaves without asking', (tester) async {
    final closed = <bool?>[];
    await tester.pumpWidget(_host(MemoryFlowStore(), [], closed));
    await open(tester);
    await tester.tap(find.byKey(const Key('flow-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unsaved-dialog')), findsNothing);
    expect(closed, [false]);
  });

  testWidgets('interrupted: the answers and the step come back; Tout effacer empties',
      (tester) async {
    final store = MemoryFlowStore();
    await tester.pumpWidget(_host(store, [], []));
    await open(tester);
    await tester.enterText(find.byKey(const Key('name')), 'Awa');
    await tester.pump();
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flow-option-true')));
    await tester.pumpAndSettle();
    // The app goes to the background (a call): the step's answer is kept.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(store.values['step_flow:test'], contains('"credit":true'));

    // The app is killed: a new start.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(store, [], []));
    await open(tester);
    expect(find.byKey(const Key('flow-resumed')), findsOneWidget);
    expect(find.text('Comment ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
    expect(find.text('Qui ?'), findsOneWidget, reason: 'credit came back');

    await tester.tap(find.byKey(const Key('flow-start-over')));
    await tester.pumpAndSettle();
    expect(find.text('Quel nom ?'), findsOneWidget);
    expect(find.byKey(const Key('flow-resumed')), findsNothing);
    expect(store.values.containsKey('step_flow:test'), isFalse);
  });

  testWidgets('a refused save is said under the button and the summary stays',
      (tester) async {
    final store = MemoryFlowStore();
    await tester.pumpWidget(_host(store, [], []));
    await open(tester);
    await tester.enterText(find.byKey(const Key('name')), 'boom');
    await tester.pump();
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flow-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flow-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flow-error')), findsOneWidget);
    expect(find.byKey(const Key('flow-summary')), findsOneWidget);
    expect(store.values.containsKey('step_flow:test'), isTrue,
        reason: 'not saved: the draft is kept');
  });

  testWidgets('wide screen: centred, phone-wide', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(MemoryFlowStore(), [], []));
    await open(tester);
    final next = tester.getRect(find.byKey(const Key('flow-next')));
    expect(next.width, lessThanOrEqualTo(560));
    expect((next.center.dx - 640).abs(), lessThan(2));
  });
}

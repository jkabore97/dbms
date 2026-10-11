// Batch 130 §3: « Supprimer mon compte » for every account.
//
//   * an owner of a shop, a farm and an association: the confirmation
//     names the three, what each loses (members, orders, the Google Play
//     and card subscriptions), the App Store subscription only the owner
//     can cancel, and the business only left; the list sent back is the
//     one shown, after the typed word;
//   * a member: nothing of a business goes, said so;
//   * a refusal (an order on the road, a platform account): said, with
//     nothing to type.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/features/account/account_deletion.dart';

void main() {
  tearDown(() => debugSellsDigitalInApp = null);

  Future<void> open(WidgetTester tester, AccountDeletionPlan plan,
      {required List<List<String>> sent, required List<int> out}) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => askAccountDeletion(context,
                plan: () async => plan,
                delete: (orgs) async => sent.add(orgs),
                signOut: () async => out.add(1)),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  final owner = AccountDeletionPlan.fromJson({
    'blocked': null,
    'businesses': [
      {'id': 's1', 'name': 'Boutique Fin', 'profile': 'retail', 'members': 1, 'orders': 1,
       'store': [{'platform': 'google', 'state': 'active'}], 'stripe': false},
      {'id': 'a1', 'name': 'Entraide Fin', 'profile': 'association', 'members': 3, 'orders': 0,
       'store': [{'platform': 'apple', 'state': 'active', 'auto_renew': true}]},
      {'id': 'f1', 'name': 'Ferme Fin', 'profile': 'farm', 'members': 0, 'orders': 2, 'store': [], 'stripe': true},
    ],
    'leaves': [{'id': 'x1', 'name': 'À Deux'}],
    'apple_store': 1,
  });

  testWidgets('an owner: the three businesses, what each loses, the App Store warning, the list sent back',
      (tester) async {
    debugSellsDigitalInApp = true;
    final sent = <List<String>>[];
    final out = <int>[];
    await open(tester, owner, sent: sent, out: out);
    expect(find.byKey(const Key('deletion-summary')), findsOneWidget);
    String line(String id) {
      final w = tester.widget<Text>(find.byKey(Key('deletion-business-$id')));
      return w.textSpan!.toPlainText();
    }
    expect(line('s1'), 'Boutique Fin — boutique · 1 membre redevient simple client · 1 commande en cours annulée, le client prévenu · l\'abonnement Google Play arrêté');
    expect(line('a1'), 'Entraide Fin — association · 3 membres redeviennent simples clients');
    expect(line('f1'), 'Ferme Fin — ferme · 2 commandes en cours annulées, les clients prévenus · l\'abonnement par carte arrêté');
    expect(find.byKey(const Key('deletion-apple-store')), findsOneWidget);
    expect(find.textContaining('Mara ne peut pas l\'annuler pour vous'), findsOneWidget);
    expect(find.text('Vous quittez aussi : À Deux.'), findsOneWidget);
    expect(find.text('Supprimer définitivement'), findsOneWidget);

    // Nothing before the word.
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    await tester.enterText(find.byKey(const Key('delete-word')), 'SUPPRIMER');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(sent, [
      ['s1', 'a1', 'f1']
    ]);
    expect(out, [1], reason: 'signed out after');
    expect(find.text('Votre compte est supprimé. Au revoir !'), findsOneWidget);
  });

  testWidgets('the iPhone app says nothing of a card subscription', (tester) async {
    debugSellsDigitalInApp = false;
    await open(tester, owner, sent: [], out: []);
    final w = tester.widget<Text>(find.byKey(const Key('deletion-business-f1')));
    expect(w.textSpan!.toPlainText(), isNot(contains('carte')));
  });

  testWidgets('a member: no business goes, and the dialog says so', (tester) async {
    final sent = <List<String>>[];
    await open(
        tester,
        AccountDeletionPlan.fromJson({
          'businesses': [],
          'leaves': [{'id': 'y1', 'name': 'Ferme Y'}],
        }),
        sent: sent,
        out: []);
    expect(find.textContaining('Vous quittez les activités dont vous faites partie'), findsOneWidget);
    expect(find.text('Vous quittez aussi : Ferme Y.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('delete-word')), 'supprimer');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(sent, [<String>[]]);
  });

  testWidgets('a refusal is said, with nothing to type', (tester) async {
    final sent = <List<String>>[];
    await open(
        tester,
        AccountDeletionPlan.fromJson({
          'blocked': 'Une livraison est en cours : terminez-la, puis supprimez votre compte.',
          'businesses': [],
          'leaves': [],
        }),
        sent: sent,
        out: []);
    expect(find.byKey(const Key('deletion-blocked')), findsOneWidget);
    expect(find.text('Une livraison est en cours : terminez-la, puis supprimez votre compte.'), findsOneWidget);
    expect(find.byKey(const Key('delete-word')), findsNothing);
    expect(sent, isEmpty);
  });
}

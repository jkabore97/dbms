// Batch 130 §3: « Supprimer mon compte » for every account.
//
//   * an owner of a shop, a farm and an association: the confirmation
//     names the three, what each loses (members, orders, the Google Play
//     and card subscriptions), the App Store subscription only the owner
//     can cancel, and the business only left; the list sent back is the
//     one shown, after the typed word;
//   * a member: nothing of a business goes, said so;
//   * a refusal (an order on the road, a platform account): said, with
//     nothing to type — by its code, in the reader's language;
//   * review S8: a sign-in older than ten minutes — the server's « reauth »
//     — is said in French and « Me reconnecter » signs the person out to
//     sign in again; B1: a subscription Mara could not stop — said, named,
//     nothing deleted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/store_rules.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/features/account/account_deletion.dart';
import 'package:kaj_app/l10n/strings.dart';

void main() {
  tearDown(() => debugSellsDigitalInApp = null);

  Future<void> open(WidgetTester tester, AccountDeletionPlan plan,
      {required List<List<String>> sent, required List<int> out, Object? refuse, Locale? locale}) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: locale == null ? null : Strings.localizationsDelegates,
      supportedLocales: locale == null ? const [Locale('en', 'US')] : Strings.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => askAccountDeletion(context,
                plan: () async => plan,
                delete: (orgs) async {
                  if (refuse != null) throw refuse;
                  sent.add(orgs);
                },
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

  testWidgets('a refusal by its code: the business named, in English too', (tester) async {
    final plan = AccountDeletionPlan.fromJson({
      'blocked': 'Mara doit encore verser à « Boutique Fin » … (the server\'s French)',
      'blocked_code': 'payout',
      'blocked_shop': 'Boutique Fin',
      'businesses': [],
      'leaves': [],
    });
    await open(tester, plan, sent: [], out: []);
    expect(find.textContaining('Mara doit encore verser à « Boutique Fin » l\'argent d\'une commande payée par Wave'),
        findsOneWidget);
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();
    await open(tester, plan, sent: [], out: [], locale: const Locale('en'));
    expect(find.textContaining('Mara still owes “Boutique Fin” the money of an order paid by Wave'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await open(
        tester,
        AccountDeletionPlan.fromJson({
          'blocked': 'Une commande de « Boutique Fin » est en route ou déjà payée en ligne : livrez-la ou remboursez-la, puis supprimez votre compte.',
          'blocked_code': 'business_order',
          'blocked_shop': 'Boutique Fin',
        }),
        sent: [],
        out: [],
        locale: const Locale('en'));
    expect(find.text('An order of “Boutique Fin” is on its way or already paid online: deliver or refund it, then delete your account.'),
        findsOneWidget);
  });

  testWidgets('S8: an old sign-in — said in French, « Me reconnecter » signs out to sign in again', (tester) async {
    final out = <int>[];
    final sent = <List<String>>[];
    await open(tester, owner, sent: sent, out: out,
        refuse: AccountRefused('Par sécurité, reconnectez-vous…', code: 'reauth'));
    await tester.enterText(find.byKey(const Key('delete-word')), 'SUPPRIMER');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Par sécurité, reconnectez-vous avant de supprimer votre compte : la connexion doit dater de moins de 10 minutes.'),
        findsOneWidget);
    expect(sent, isEmpty);
    expect(out, isEmpty, reason: 'nothing until the person chooses');
    await tester.ensureVisible(find.byKey(const Key('delete-reauth')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-reauth')));
    await tester.pumpAndSettle();
    expect(out, [1], reason: 'signed out, to sign in again');
    expect(find.byKey(const Key('delete-word')), findsNothing, reason: 'the dialog is closed');
    expect(find.text('Votre compte est supprimé. Au revoir !'), findsNothing);
  });

  testWidgets('B1: a subscription Mara could not stop — named, nothing deleted, the dialog stays', (tester) async {
    final out = <int>[];
    await open(tester, owner, sent: [], out: out,
        refuse: AccountRefused('Nous n\'avons pas pu arrêter …', code: 'not_stopped', name: 'Ferme Fin'));
    await tester.enterText(find.byKey(const Key('delete-word')), 'SUPPRIMER');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Nous n\'avons pas pu arrêter l\'abonnement de « Ferme Fin » : rien n\'a été supprimé. Réessayez dans un moment ou écrivez à l\'aide.'),
        findsOneWidget);
    expect(find.byKey(const Key('delete-reauth')), findsNothing);
    expect(find.byKey(const Key('delete-word')), findsOneWidget, reason: 'still open, to try again');
    expect(out, isEmpty);
  });
}

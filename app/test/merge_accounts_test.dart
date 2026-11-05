import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/features/admin/merge_accounts_sheet.dart';

/// The owner (168): « some people sign in with Apple, then with Google, and
/// it looks like two accounts — I want to merge them ». From Awa's sheet the
/// platform admin finds her other account, reads both, types the absorbed
/// one's email back, and merges; nothing merges before that.
class _Console extends ConsoleRepository {
  _Console() : super(null);

  final calls = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<List<PlatformPerson>> searchPeople(String? query, {int limit = 50, int offset = 0}) async => const [
        PlatformPerson(userId: 'a', isPlatformAdmin: false, businessCount: 1, fullName: 'Awa', email: 'awa@gmail.com'),
        PlatformPerson(userId: 'b', isPlatformAdmin: false, businessCount: 2, email: 'x7@privaterelay.appleid.com'),
      ];

  @override
  Future<AccountMergePreview> mergePreview({required String keepId, required String absorbId}) async {
    calls.add('preview:$keepId<-$absorbId');
    Map<String, dynamic> card(String id) => id == 'a'
        ? {'id': 'a', 'email': 'awa@gmail.com', 'name': 'Awa', 'providers': ['google'], 'password': false,
           'businesses': [{'org': 'Boutique Awa', 'role': 'admin'}]}
        : {'id': 'b', 'email': 'x7@privaterelay.appleid.com', 'providers': ['apple'], 'password': false,
           'businesses': [{'org': 'Ferme Awa', 'role': 'owner'}]};
    return AccountMergePreview.fromJson({
      'keep': card(keepId),
      'absorb': card(absorbId),
      'rows': {'memberships.user_id': 1, 'journal_entries.created_by': 3},
    });
  }

  @override
  Future<void> mergeAccounts({required String keepId, required String absorbId, required String confirm}) async {
    calls.add('merge:$keepId<-$absorbId ($confirm)');
  }
}

void main() {
  testWidgets('find the other account, read both, type the email back, merge', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final console = _Console();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MergeAccountsSheet(
          console: console,
          person: const PlatformPerson(userId: 'a', isPlatformAdmin: false, businessCount: 1, fullName: 'Awa', email: 'awa@gmail.com'),
        ),
      ),
    ));
    await tester.enterText(find.byKey(const Key('merge-search')), 'awa');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('merge-pick-a')), findsNothing, reason: 'never the same account');
    await tester.tap(find.byKey(const Key('merge-pick-b')));
    await tester.pumpAndSettle();
    expect(console.calls, ['preview:a<-b']);
    expect(find.text('Ferme Awa · Propriétaire'), findsNothing); // role words come from roleLabel
    expect(find.textContaining('Ferme Awa'), findsOneWidget);
    expect(find.textContaining('4 élément(s)'), findsOneWidget);

    final go = find.byKey(const Key('merge-go'));
    expect(tester.widget<FilledButton>(go).onPressed, isNull, reason: 'not before the email is typed back');
    await tester.enterText(find.byKey(const Key('merge-confirm')), 'X7@privaterelay.appleid.com');
    await tester.pump();
    await tester.ensureVisible(go);
    await tester.tap(go);
    await tester.pumpAndSettle();
    expect(console.calls.last, 'merge:a<-b (X7@privaterelay.appleid.com)');
  });
}

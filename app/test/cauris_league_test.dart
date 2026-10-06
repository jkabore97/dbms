import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/cauris_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/cauris/league_screen.dart';

/// The weekly race (086): the podium, your place and the gap, the share
/// card for the top 3, the two switches — and the vitrine's badge.
class _Cauris extends CaurisRepository {
  _Cauris(this.json) : super(null);

  Map<String, dynamic> json;
  final prefs = <String>[];

  @override
  Future<LeagueBoard?> board(String orgId) async => LeagueBoard.fromJson(json);

  @override
  Future<void> setBoardPrefs(String orgId, {bool? hidden, bool? notify}) async {
    prefs.add('hidden=$hidden notify=$notify');
    json = {...json, 'hidden': hidden ?? json['hidden'], 'notify': notify ?? json['notify']};
  }
}

const _org = OrgSummary(
    id: 'o1', name: 'Delta', profile: 'retail', roles: ['owner'], slug: 'delta');

Map<String, dynamic> _board({int rank = 4, int score = 30, int? gap = 31}) => {
      'label': 'Boutiques · Ouagadougou · petites',
      'rank': rank,
      'score': score,
      'gap': gap,
      'size': 12,
      'top': [
        {'rank': 1, 'name': 'Alpha', 'score': 120, 'me': rank == 1},
        {'rank': 2, 'name': 'Une boutique de Ouagadougou', 'score': 90, 'me': false},
        {'rank': 3, 'name': 'Charlie', 'score': 60, 'me': false},
      ],
      'hidden': false,
      'notify': true,
      'last_week': {'rank': 2, 'score': 140},
    };

void main() {
  Future<void> open(WidgetTester tester, _Cauris c) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: LeagueScreen(org: _org, cauris: c)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the podium, your place and what the next one costs',
      (tester) async {
    await open(tester, _Cauris(_board()));
    expect(find.text('BOUTIQUES · OUAGADOUGOU · PETITES'), findsOneWidget);
    expect(find.byKey(const Key('league-podium')), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Une boutique de Ouagadougou'), findsOneWidget);
    expect(find.text('4e'), findsOneWidget);
    expect(find.text('Encore 31 cauris pour la place devant.'), findsOneWidget);
    expect(find.text('La semaine dernière : 2e de votre ligue.'), findsOneWidget);
    expect(find.byKey(const Key('league-share')), findsNothing,
        reason: 'the card to share is for the podium');
  });

  testWidgets('on the podium: proud, and a card to send', (tester) async {
    await open(tester, _Cauris(_board(rank: 1, score: 120, gap: null)));
    expect(find.text('1er'), findsOneWidget);
    expect(find.text('En tête : gardez-la !'), findsOneWidget);
    expect(find.byKey(const Key('league-share')), findsOneWidget);
  });

  testWidgets('the owner turns the messages off and hides the name',
      (tester) async {
    final c = _Cauris(_board());
    await open(tester, c);
    await tester.tap(find.byKey(const Key('league-notify')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('league-hidden')));
    await tester.pump();
    await tester.pump();
    expect(c.prefs, ['hidden=null notify=false', 'hidden=true notify=null']);
  });

  test('the vitrine reads last week\'s podium', () {
    final s = StorefrontStyle.fromJson(const {
      'top_week': {'rank': 1, 'league': 'Boutiques · Ouagadougou · petites'},
    });
    expect(s.topWeekRank, 1);
    expect(s.topWeekLeague, 'Boutiques · Ouagadougou · petites');
    expect(StorefrontStyle.fromJson(const {}).topWeekRank, isNull);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/cauris_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/cauris/chemin_screen.dart';
import 'package:kaj_app/features/cauris/path_card.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Le Chemin (097): one spine in place of the path card, the vitrine guide,
/// the checklist meter, the Académie and Mes cauris.

/// path_state(), exactly as the contract spells it.
const _contract = {
  'stage': 2,
  'stages': [
    {'n': 1, 'title': 'Ouvrir', 'done': true},
    {'n': 2, 'title': 'Remplir', 'done': false},
    {'n': 3, 'title': 'Vendre', 'done': false},
    {'n': 4, 'title': 'Grandir', 'done': false},
  ],
  'next': 'articles',
  'steps': [
    {
      'key': 'first_article', 'stage': 1, 'title': 'Mon premier article',
      'line': 'Un article en vente, et la vitrine a quelque chose à montrer.',
      'go': 'produits', 'progress': 1, 'live': 0, 'goal': 1, 'done': true,
      'reward': 5, 'opens': null,
    },
  ],
  'tools': {
    'invoices': true, 'production': false, 'credits': false,
    'second_business': false,
  },
  'balance': 35,
  'week': 10,
  'league_open': false,
};

Map<String, dynamic> _step(String key, int stage, String title,
        {int progress = 0, int? live, int goal = 1, bool done = false,
        int reward = 10, String go = 'produits', String? opens, String? line}) =>
    {
      'key': key, 'stage': stage, 'title': title,
      'line': line ?? 'Pourquoi : $title.', 'go': go,
      'progress': done ? goal : progress,
      'live': live ?? (done ? goal : progress),
      'goal': goal, 'done': done, 'reward': reward, 'opens': opens,
    };

/// A shop at [stage]: every step before it done, the stage's first step
/// next, the ones after it ahead. [allBut] leaves only those steps of the
/// stage undone.
PathState _shop(int stage,
    {bool leagueOpen = false, Set<String>? allBut, bool admin = true}) {
  bool done(int s) => s < stage;
  final steps = [
    _step('first_article', 1, 'Mon premier article', done: done(1), reward: 5),
    _step('vitrine_open', 1, 'Ouvrir ma vitrine', done: done(1), reward: 5),
    _step('contact', 1, 'Mon téléphone et mon adresse', goal: 2, done: done(1), reward: 5),
    _step('articles', 2, '8 articles en vente', progress: done(2) ? 8 : 3, goal: 8,
        done: done(2), reward: 20),
    _step('photos', 2, 'Trois articles en photo', progress: done(2) ? 3 : 1, goal: 3,
        done: done(2), reward: 20, opens: 'invoices'),
    _step('blurb', 2, 'Une phrase de présentation', done: true),
    _step('pin', 2, 'Ma position sur la carte', done: done(2)),
    _step('first_sale', 2, 'Ma première vente à la caisse', done: done(2),
        go: '', opens: 'production'),
    _step('first_order', 3, 'Ma première commande acceptée', done: done(3), go: 'commandes'),
    _step('three_orders', 3, 'Trois commandes terminées', goal: 3, done: done(3),
        reward: 20, go: 'commandes', opens: 'credits'),
    _step('first_unlock', 4, 'Mon premier outil avec mes cauris', done: done(4), go: 'chemin'),
    _step('referral', 4, 'Parrainer une entreprise', done: done(4), go: 'chemin',
        line: 'Une entreprise vous nomme parrain. Quand elle décolle, +200 cauris de plus.'),
    _step('podium', 4, 'Dans le top 3 de la semaine', done: done(4), go: 'classement'),
  ];
  if (allBut != null) {
    for (final s in steps) {
      if (s['stage'] == stage) {
        final d = !allBut.contains(s['key']);
        s['done'] = d;
        if (d) s['progress'] = s['live'] = s['goal'];
      }
    }
  }
  final next = steps.where((s) => s['done'] != true).firstOrNull?['key'];
  return PathState.fromJson({
    'stage': stage,
    'stages': [
      for (final (i, t) in const ['Ouvrir', 'Remplir', 'Vendre', 'Grandir'].indexed)
        {'n': i + 1, 'title': t, 'done': i + 1 < stage},
    ],
    'next': next,
    'steps': steps,
    'tools': {
      'invoices': stage > 2, 'production': stage > 2, 'credits': stage > 3,
      'second_business': false,
    },
    'balance': admin ? 95 : null,
    'week': admin ? 30 : null,
    'league_open': leagueOpen,
  });
}

class _Cauris extends CaurisRepository {
  _Cauris(this.path, {this.admin = true, this.missing = false}) : super(null);

  final PathState? path;
  final bool admin;

  /// A database before 097: no path_state at all.
  final bool missing;

  @override
  Future<void> milestones(String orgId) async {}

  @override
  Future<PathState?> pathState(String orgId, {void Function()? onMissing}) async {
    if (missing) onMissing?.call();
    return path;
  }

  @override
  Future<CaurisWallet?> wallet(String orgId) async => !admin
      ? null
      : CaurisWallet.fromJson({
          'balance': 95,
          'week': 30,
          'referral_code': 'boutique-awa',
          'rules': [
            {'key': 'order_done', 'points': 10, 'label': 'Commande terminée'},
          ],
        });
}

/// The till's day, empty: enough for the home to draw.
class _Till extends RetailRepository {
  _Till(super.client);

  @override
  Future<StoreDay> day(String orgId, {DateTime? on}) async => const StoreDay();

  @override
  Future<List<ExpiringProduct>> expiring(String orgId, {int within = 14}) async =>
      const [];

  @override
  Future<List<Product>> products(String orgId, {bool activeOnly = true}) async =>
      const [];

  @override
  Future<double> lossesAvoided(String orgId, {int within = 14}) async => 0;

  @override
  Future<int> pendingOrders(String orgId) async => 0;
}

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

const _owner = OrgSummary(id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
const _clerk = OrgSummary(id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['employee']);
const _church = OrgSummary(id: 'o2', name: 'Église', profile: 'church', roles: ['owner']);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<void> tall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  test('path_state reads exactly as the contract spells it', () {
    final p = PathState.fromJson(_contract);
    expect(p.stage, 2);
    expect(p.finished, isFalse);
    expect(p.stages.map((s) => s.title), ['Ouvrir', 'Remplir', 'Vendre', 'Grandir']);
    expect(p.stages.first.done, isTrue);
    expect(p.titleOf(2), 'Remplir');
    expect(p.next, 'articles');
    final s = p.steps.single;
    expect(s.key, 'first_article');
    expect(s.stage, 1);
    expect(s.title, 'Mon premier article');
    expect(s.go, 'produits');
    expect((s.progress, s.goal, s.done, s.reward, s.opens), (1, 1, true, 5, null));
    expect(s.live, 0, reason: 'done stays done; live says what is there now');
    expect(p.tools, {
      'invoices': true, 'production': false, 'credits': false,
      'second_business': false,
    });
    expect((p.balance, p.week, p.leagueOpen), (35, 10, false));
    expect(PathState.fromJson(const {'stage': 5, 'next': null}).finished, isTrue);
    // A member who is not an admin: no wallet.
    final m = PathState.fromJson({..._contract, 'balance': null, 'week': null});
    expect((m.balance, m.week), (null, null));
  });

  test('a database before 097 (PGRST202) reads no path, not an error',
      () async {
    final client = SupabaseClient('https://example.supabase.co', 'sb_publishable_test',
        httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message': 'Could not find the function public.path_state(p_org) in the schema cache',
              'details': null,
              'hint': null,
            }),
            404,
            request: request,
            headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    var missing = false;
    expect(
        await CaurisRepository(client)
            .pathState('o1', onMissing: () => missing = true),
        isNull);
    expect(missing, isTrue, reason: 'the home is told, to show its fallback');
  });

  test('the podium is never proposed while the league says « Bientôt »', () {
    final onlyPodium = _shop(4, allBut: {'podium'});
    expect(onlyPodium.next, 'podium');
    expect(onlyPodium.proposed, isNull);
    expect(PathCard.shows(_owner, onlyPodium), isFalse);
    final raced = _shop(4, allBut: {'podium'}, leagueOpen: true);
    expect(raced.proposed?.key, 'podium');
    expect(PathCard.shows(_owner, raced), isTrue);
    // Ahead of the podium, the steps that can be done are proposed.
    expect(_shop(4, allBut: {'referral', 'podium'}).proposed?.key, 'referral');
  });

  group('the store home', () {
    late SupabaseClient client;
    setUp(() => client =
        SupabaseClient('https://example.supabase.co', 'sb_publishable_test'));
    tearDown(() => client.dispose());

    Future<void> home(WidgetTester tester, OrgSummary org, PathState? p,
        {bool missing = false}) async {
      await tall(tester);
      await tester.pumpWidget(_app(StoreHomeScreen(
        org: org,
        retail: _Till(client),
        invoicing: InvoicingRepository(client),
        cauris: _Cauris(p, missing: missing),
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('a server with no path yet: the fallback card, not nothing',
        (tester) async {
      await home(tester, _owner, null, missing: true);
      expect(find.byKey(const Key('path-card')), findsNothing);
      expect(find.byKey(const Key('path-fallback')), findsOneWidget);
      expect(find.text('Voir ce qui manque'), findsOneWidget);
    });

    testWidgets('no fallback when the path simply did not load (no signal)',
        (tester) async {
      await home(tester, _owner, null);
      expect(find.byKey(const Key('path-fallback')), findsNothing);
    });

    testWidgets('an admin at stage 2 sees the card', (tester) async {
      await home(tester, _owner, _shop(2));
      expect(find.byKey(const Key('path-card')), findsOneWidget);
      expect(find.text('8 articles en vente'), findsOneWidget);
    });

    testWidgets('no card once the path is walked', (tester) async {
      await home(tester, _owner, _shop(5));
      expect(find.byKey(const Key('path-card')), findsNothing);
    });

    testWidgets('no card for a member who is not an admin', (tester) async {
      await home(tester, _clerk, _shop(2));
      expect(find.byKey(const Key('path-card')), findsNothing);
    });
  });

  testWidgets('« Faire maintenant » goes where the step is done',
      (tester) async {
    await tall(tester);
    final pushed = <String>[];
    final router = GoRouter(
      initialLocation: '/o/o1',
      routes: [
        GoRoute(
          path: '/o/:id',
          builder: (context, state) =>
              Scaffold(body: PathCard(org: _owner, state: _shop(2))),
          routes: [
            GoRoute(
              path: 'produits',
              builder: (context, state) {
                pushed.add(state.uri.toString());
                return const Scaffold(body: Text('ailleurs'));
              },
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('path-do')));
    await tester.pumpAndSettle();
    expect(pushed, [Routes.inside('o1', 'produits')]);
  });

  testWidgets('the home card: the next step, how far, what it pays and opens',
      (tester) async {
    final p = _shop(2);
    expect(PathCard.shows(_owner, p), isTrue);
    expect(PathCard.shows(_clerk, p), isFalse, reason: 'admins only');
    expect(PathCard.shows(_church, p), isFalse, reason: 'off the path');
    expect(PathCard.shows(_owner, _shop(5)), isFalse, reason: 'walked');
    expect(PathCard.shows(_owner, null), isFalse, reason: 'before 097');

    await tall(tester);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PathCard(org: _owner, state: p))));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Étape 2 sur 4 · Remplir'), findsOneWidget);
    expect(find.text('8 articles en vente'), findsOneWidget);
    // The number is said by the app, from the step's goal.
    expect(find.text('Avec 8 articles, votre vitrine se montre à tout le monde.'),
        findsOneWidget);
    expect(find.text('3 / 8'), findsOneWidget);
    expect(find.text('+20 cauris'), findsOneWidget);
    expect(find.byKey(const Key('path-opens')), findsNothing,
        reason: 'articles open nothing alone');
    expect(find.text('Faire maintenant'), findsOneWidget);

    // Once the articles are in, the photos are next — and open invoices.
    final photos = PathState.fromJson({
      ..._contract,
      'next': 'photos',
      'steps': [
        _step('photos', 2, 'Trois articles en photo', progress: 1, goal: 3,
            reward: 20, opens: 'invoices'),
      ],
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PathCard(org: _owner, state: photos))));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('ouvre : Factures'), findsOneWidget);
  });

  testWidgets('Mon chemin: stage 1 folded, stage 2 open with the next lit, '
      'the stages ahead locked, the tools and what opens them', (tester) async {
    await tall(tester);
    await tester.pumpWidget(MaterialApp(
        home: CheminScreen(org: _owner, cauris: _Cauris(_shop(2)))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('95'), findsOneWidget);
    expect(find.text('Cette semaine : +30'), findsOneWidget);
    expect(find.byKey(const Key('chemin-done-1')), findsOneWidget);
    expect(find.byKey(const Key('chemin-step-first_article')), findsNothing,
        reason: 'a walked stage is folded');
    expect(find.text('Étape 2 sur 4 · Remplir'), findsOneWidget);
    expect(find.byKey(const Key('chemin-step-articles')), findsOneWidget);
    expect(find.byKey(const Key('chemin-step-first_sale')), findsOneWidget);
    // The next step carries « Faire maintenant », the others « Faire ».
    expect(
        find.descendant(
            of: find.byKey(const Key('chemin-step-articles')),
            matching: find.byKey(const Key('chemin-go'))),
        findsOneWidget);
    expect(find.text('Faire'), findsNWidgets(3), reason: 'photos, pin, first sale');
    expect(find.text('Fait'), findsOneWidget, reason: 'the blurb');
    // Ahead: a locked line, no steps.
    expect(find.byKey(const Key('chemin-locked-3')), findsOneWidget);
    expect(find.text('Étape 3 · Vendre'), findsOneWidget);
    expect(find.byKey(const Key('chemin-locked-4')), findsOneWidget);
    expect(find.byKey(const Key('chemin-step-first_order')), findsNothing);
    // The tools, each with what opens it.
    expect(find.text('8 articles en vente et 3 en photo'), findsOneWidget);
    expect(find.text('Terminez l\'étape Remplir'), findsOneWidget);
    expect(find.text('3 commandes terminées'), findsOneWidget);
    expect(find.byKey(const Key('chemin-tool-second_business')), findsOneWidget);
    // No league before the last stage.
    expect(find.byKey(const Key('chemin-league')), findsNothing);
    expect(find.byKey(const Key('chemin-league-soon')), findsNothing);
    expect(find.byKey(const Key('referral-own-code')), findsOneWidget);
  });

  testWidgets('stage 4: the league, « Bientôt » until there is a race',
      (tester) async {
    await tall(tester);
    await tester.pumpWidget(MaterialApp(
        home: CheminScreen(org: _owner, cauris: _Cauris(_shop(4)))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    for (final n in [1, 2, 3]) {
      expect(find.byKey(Key('chemin-done-$n')), findsOneWidget);
    }
    expect(find.text('Étape 4 sur 4 · Grandir'), findsOneWidget);
    expect(find.text('Bientôt, quand votre quartier sera là'), findsOneWidget);
    expect(find.byKey(const Key('chemin-league')), findsNothing);

    await tester.pumpWidget(MaterialApp(
        home: CheminScreen(
            key: const ValueKey('raced'),
            org: _owner, cauris: _Cauris(_shop(4, leagueOpen: true)))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('chemin-league')), findsOneWidget);
  });

  testWidgets('stage 4 with the league closed: the podium says « Bientôt »',
      (tester) async {
    await tall(tester);
    await tester.pumpWidget(_app(CheminScreen(
        org: _owner, cauris: _Cauris(_shop(4, allBut: {'podium'})))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('chemin-soon-podium')), findsOneWidget);
    expect(find.byKey(const Key('chemin-go')), findsNothing,
        reason: 'nothing to do now: no « Faire maintenant »');
    expect(find.text('Faire'), findsNothing);
  });

  testWidgets('Mon chemin in English', (tester) async {
    await tall(tester);
    await tester.pumpWidget(_app(CheminScreen(org: _owner, cauris: _Cauris(_shop(2))),
        lang: 'en'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Stage 2 of 4 · Fill'), findsOneWidget);
    expect(find.text('8 items for sale'), findsOneWidget,
        reason: 'the number is said by the app');
    expect(find.text('With 8 items, your vitrine shows itself to everyone.'), findsOneWidget);
    expect(find.text('Three items with a photo'), findsOneWidget);
    expect(find.text('Stage 3 · Sell'), findsOneWidget);
    expect(find.text('Do it now'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chemin-details')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Order completed'), findsOneWidget);
    expect(find.text('Path steps: 5 to 20 cauris each'), findsOneWidget);
    expect(find.text('No cauris yet. Your first item for sale earns some.'), findsOneWidget);
  });

  testWidgets('a member who is not an admin walks the path without the wallet',
      (tester) async {
    await tall(tester);
    await tester.pumpWidget(_app(CheminScreen(
        org: _clerk, cauris: _Cauris(_shop(2, admin: false), admin: false))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('cauris-wallet')), findsNothing);
    expect(find.byKey(const Key('chemin-stage-2')), findsOneWidget);
  });

  testWidgets('a step done at the till, from Mon chemin, says where',
      (tester) async {
    await tall(tester);
    await tester.pumpWidget(_app(CheminScreen(
        org: _owner, cauris: _Cauris(_shop(2, allBut: {'first_sale'})))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('chemin-go')));
    await tester.pump();
    expect(find.text('Faites vos ventes à la caisse, sur l\'accueil.'), findsOneWidget);
  });

  testWidgets('the lock on a tool counts the steps it waits for',
      (tester) async {
    await tall(tester);
    var path = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PathGateSheet(
                org: _owner,
                feature: 'invoices',
                load: () async => _shop(2),
                onPath: () => path++))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Factures'), findsOneWidget);
    expect(find.text('Se débloque : 8 articles en vente et 3 en photo'), findsOneWidget);
    expect(find.text('3 / 8'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.byKey(const Key('path-view')), findsNothing);
    await tester.tap(find.byKey(const Key('path-go')));
    expect(path, 1, reason: 'the way there is Mon chemin');

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PathGateSheet(
                org: _owner,
                feature: 'production',
                load: () async => _shop(2),
                onPath: () {}))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Se débloque : Terminez l\'étape Remplir'), findsOneWidget);
    expect(find.text('Ma première vente à la caisse'), findsOneWidget);

    // The gate is live: photos reached once, one taken off since — the
    // sheet counts what is there now.
    final fell = PathState.fromJson({
      ..._contract,
      'steps': [
        _step('articles', 2, '8 articles en vente', goal: 8, done: true),
        _step('photos', 2, 'Trois articles en photo', goal: 3, done: true, live: 2),
      ],
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PathGateSheet(
                key: const ValueKey('fell'),
                org: _owner,
                feature: 'invoices',
                load: () async => fell,
                onPath: () {}))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Fait'), findsOneWidget, reason: 'the articles are there');
  });
}

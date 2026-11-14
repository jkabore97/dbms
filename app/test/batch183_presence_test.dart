import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/analytics/analytics_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/events/events_repository.dart';
import 'package:kaj_app/core/events/invitations_repository.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/l10n/locale_controller.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/production/production_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';
import 'package:kaj_app/features/events/events_screens.dart';
import 'package:kaj_app/features/events/presence_screen.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/storefront/my_invitations_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// 183 in the app: « Confirmer ma présence » — the card's one button opens
/// `/presence/<slug>`, signed in the guest confirms (how many, a word), then
/// adds photos; « Mes invitations » lists the cards confirmed, the day on
/// the card's own clock, « n / 5 », the add closed at five; the organiser's
/// card says the five per guest instead of a switch, and reads a confirmed
/// guest's account and number.
class _Invitations extends InvitationsRepository {
  _Invitations({this.mineList = const [], this.cardAnswer, this.refuseAfter}) : super(null, uploadsUrl: '');

  List<MyInvitation> mineList;
  final PresenceCard? cardAnswer;

  /// The server refuses the photo after so many (the five).
  final int? refuseAfter;
  final calls = <String>[];

  @override
  bool get signedIn => true;

  @override
  Future<PresenceCard?> card(String slug, String? preview) async {
    calls.add('card:$slug:$preview');
    return cardAnswer;
  }

  @override
  Future<({String title, bool first})> confirm(String slug, String? preview,
      {required int people, String? message, bool sharePhone = false}) async {
    calls.add('confirm:$slug:$preview:$people:${message?.trim()}${sharePhone ? ':phone' : ''}');
    mineList = [_inv(used: 0)];
    return (title: 'Mariage Awa', first: true);
  }

  @override
  Future<List<MyInvitation>> mine() async => mineList;

  @override
  Future<String> addPhoto(String slug, Uint8List bytes, String contentType) async {
    final n = calls.where((c) => c.startsWith('photo:')).length;
    if (refuseAfter != null && n >= refuseAfter!) {
      throw const EventsException('Vous avez déposé vos 5 photos : c\'est le maximum par invité.');
    }
    calls.add('photo:$slug:$contentType:${bytes.length}');
    return 'events/e1/$n.jpg';
  }

  @override
  String? pictureUrl(String key, {int width = 400}) => null;
}

MyInvitation _inv({int used = 0, bool allowed = true, String? preview, DateTime? at, String tz = 'Africa/Niamey'}) => MyInvitation.fromJson({
      'id': '18318318-2222-0000-0000-000000000001',
      'slug': 'mariage-awa-183',
      'preview': preview,
      'title': 'Mariage Awa',
      'starts_at': (at ?? DateTime.utc(2027, 6, 5, 10)).toIso8601String(),
      'tz': tz,
      'place': 'Ouaga 2000',
      'people': 2,
      'album_on': true,
      'album_allowed': allowed,
      'photos_used': used,
      'photos_limit': 5,
      'photos': [for (var i = 0; i < used; i++) {'key': 'events/e1/$i.jpg', 'approved': i > 0}],
    });

Future<List<PickedPhoto>> _two(int limit) async => [
      for (var i = 0; i < 2 && i < limit; i++) (bytes: Uint8List.fromList([1, 2, 3]), type: 'image/jpeg'),
    ];

Future<void> _pump(WidgetTester tester, Widget home, {String lang = 'fr'}) async {
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    // a new screen each time, never the last one's state
    key: UniqueKey(),
    locale: Locale(lang),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: home,
  ));
  await tester.pumpAndSettle();
}

class _Events extends EventsRepository {
  _Events() : super(null);

  @override
  Future<EventSummary?> find(String id) async => EventSummary(
        id: 'e1', orgId: 'o1', kind: 'mariage', card: 'come', slug: 'mariage-awa-183', previewToken: 'f00dbabef00dbabef00dbabe',
        title: 'Mariage Awa', startsAt: DateTime(2027, 6, 5, 10), place: null, content: const {}, rsvpOn: true, albumOn: true,
        published: true, createdAt: DateTime(2026, 11, 1),
      );

  @override
  Future<List<EventRsvp>> rsvps(String eventId) async => [
        EventRsvp.fromJson({
          'id': 'r1', 'event_id': 'e1', 'name': 'Nora Invitée', 'people': 3, 'answer': 'oui', 'message': 'Avec plaisir',
          'extra': {'whatsapp': '+22670183003', 'account': true, 'preview': 'f00dbabef00dbabef00dbabe'},
          'created_at': '2026-11-14T10:00:00Z',
        }),
      ];

  @override
  Future<List<EventPicture>> pictures(String eventId) async => const [];

  @override
  String? pictureUrl(String key, {int width = 400}) => null;
}

const _org = OrgSummary(id: 'o1', name: 'Awa', slug: 'awa', profile: 'events', roles: ['owner'], plan: 'pro');

/// The server, for the real router: signed out until [live] and [user].
class _Server extends AuthRepository {
  _Server() : super(null);

  bool live = false;
  User? user;
  List<OrgSummary> orgs = const [];

  @override
  bool get isConfigured => true;
  @override
  bool get hasLiveSession => live;
  @override
  User? get currentUser => user;
  @override
  Future<bool> googleAvailable() async => false;
  @override
  Future<List<OrgSummary>> fetchOrgs() async => orgs;
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<bool> isPlatformAdmin() async => false;
  @override
  Future<int> claimMyInvitations() async => 0;
  @override
  Future<PlanTerms> planTerms() async => PlanTerms.defaults;
}

const _nora = User(
  id: 'nora-183',
  appMetadata: {'provider': 'email'},
  userMetadata: {'full_name': 'Nora Invitée'},
  aud: 'authenticated',
  email: 'nora@example.com',
  createdAt: '2026-11-14T00:00:00Z',
);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('fr', null);
  });

  testWidgets('the confirmation: how many and a word, « Je confirme » asks the server, then the photos are offered', (tester) async {
    final repo = _Invitations(cardAnswer: const PresenceCard(title: 'Mariage Awa', dateFr: 'samedi 5 juin 2027 à 11 h', place: 'Ouaga 2000', album: true));
    var opened = false;
    await _pump(tester, PresenceScreen(repo: repo, slug: 'mariage-awa-183', preview: 'f00d', pick: _two, toInvitations: () => opened = true));
    expect(find.text('Confirmer ma présence à Mariage Awa'), findsOneWidget);
    expect(repo.calls, ['card:mariage-awa-183:f00d']);
    expect(find.byKey(const Key('presence-less')), findsOneWidget);
    await tester.tap(find.byKey(const Key('presence-more')));
    await tester.tap(find.byKey(const Key('presence-more')));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('presence-message')), ' Avec plaisir ');
    await tester.tap(find.byKey(const Key('presence-confirm')));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'confirm:mariage-awa-183:f00d:3:Avec plaisir');
    expect(find.byKey(const Key('presence-done')), findsOneWidget);
    expect(find.text('Votre présence est confirmée. Merci !'), findsOneWidget);
    expect(find.textContaining('Ajouter des photos · 0 / 5'), findsOneWidget);
    // the photos straight from here
    await tester.tap(find.byKey(const Key('presence-photos')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('photo:')).length, 2);
    expect(find.text('2 photos ajoutées à l’album.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('presence-invitations')));
    expect(opened, isTrue);
  });

  testWidgets('the confirmation: already confirmed, the numbers are the account\'s; ten at most; a card not open says so', (tester) async {
    final repo = _Invitations(cardAnswer: const PresenceCard(title: 'Mariage Awa', myPeople: 9, myMessage: 'À samedi'));
    await _pump(tester, PresenceScreen(repo: repo, slug: 'mariage-awa-183'));
    expect(find.text('9'), findsOneWidget);
    expect(find.text('À samedi'), findsOneWidget);
    expect(find.text('Vous avez déjà confirmé : changez le nombre ou le mot si besoin.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('presence-more')));
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(const Key('presence-more'))).onPressed, isNull, reason: 'ten at most');
    await _pump(tester, PresenceScreen(repo: _Invitations(), slug: 'x-1'));
    expect(find.byKey(const Key('presence-problem')), findsOneWidget);
    expect(find.text('Cette carte n’est pas ouverte.'), findsOneWidget);
  });

  testWidgets('« Mes invitations »: the card, its day on its own clock, the place, « n / 5 », the add; closed at five', (tester) async {
    Uri? opened;
    final repo = _Invitations(mineList: [_inv(used: 2, preview: 'f00df00df00df00df00df00d')]);
    await _pump(tester, MyInvitationsScreen(repo: repo, pick: _two, open: (u) async => opened = u, now: () => DateTime(2026, 11, 14)));
    expect(find.text('Mariage Awa'), findsOneWidget);
    expect(find.text('Ouaga 2000'), findsOneWidget);
    // 10:00 UTC in Niamey (+1): « 11:00 », whatever the phone's zone
    expect(find.text('samedi 5 juin 2027 · 11:00'), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('Vos photos'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget, reason: 'the first one waits for the organiser');
    await tester.tap(find.byKey(const ValueKey('invitation-open-18318318-2222-0000-0000-000000000001')));
    expect(opened.toString(), endsWith('/e/mariage-awa-183?apercu=f00df00df00df00df00df00d'));
    await tester.tap(find.byKey(const ValueKey('invitation-add-18318318-2222-0000-0000-000000000001')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('photo:')), ['photo:mariage-awa-183:image/jpeg:3', 'photo:mariage-awa-183:image/jpeg:3']);

    final full = _Invitations(mineList: [_inv(used: 5)]);
    await _pump(tester, MyInvitationsScreen(repo: full, pick: _two, now: () => DateTime(2026, 11, 14)));
    expect(find.text('5 / 5'), findsOneWidget);
    final add = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('invitation-add-18318318-2222-0000-0000-000000000001')));
    expect(add.onPressed, isNull, reason: 'five sent: no more');
    expect(find.text('Vous avez déposé vos 5 photos : c’est le maximum par invité.'), findsOneWidget);
  });

  testWidgets('« Mes invitations »: the server\'s five hold — the photo past them refused in its words; a free album says closed', (tester) async {
    final repo = _Invitations(mineList: [_inv(used: 4)], refuseAfter: 0);
    await _pump(tester, MyInvitationsScreen(repo: repo, pick: _two, now: () => DateTime(2026, 11, 14)));
    await tester.tap(find.byKey(const ValueKey('invitation-add-18318318-2222-0000-0000-000000000001')));
    await tester.pumpAndSettle();
    expect(find.text('Vous avez déposé vos 5 photos : c\'est le maximum par invité.'), findsOneWidget);

    await _pump(tester, MyInvitationsScreen(repo: _Invitations(mineList: [_inv(allowed: false)]), now: () => DateTime(2026, 11, 14)));
    expect(find.byKey(const ValueKey('invitation-add-18318318-2222-0000-0000-000000000001')), findsNothing);
    expect(find.text('L’album de cette carte est fermé.'), findsOneWidget);

    await _pump(tester, MyInvitationsScreen(repo: _Invitations(), now: () => DateTime(2026, 11, 14)));
    expect(find.byKey(const Key('my-invitations-empty')), findsOneWidget);
  });

  testWidgets('the organiser\'s card: the five per guest said, no switch; a confirmed guest\'s account, number and reminder', (tester) async {
    Uri? wa;
    await _pump(tester, EventScreen(events: _Events(), org: _org, eventId: 'e1', open: (u) async => wa = u));
    expect(find.byKey(const Key('event-album-limit')), findsNothing, reason: '183: the five are the rule, not a switch');
    expect(find.byKey(const Key('event-album-review')), findsOneWidget);
    expect(find.text('Les invités confirmés ajoutent jusqu’à 5 photos chacun'), findsOneWidget);
    await tester.ensureVisible(find.text('Nora Invitée'));
    expect(find.textContaining('Présence confirmée avec Marakaj'), findsOneWidget);
    expect(find.textContaining('WhatsApp : +22670183003'), findsOneWidget);
    expect(find.textContaining('account'), findsNothing);
    expect(find.textContaining('preview'), findsNothing);
    await tester.tap(find.byKey(const Key('rsvp-whatsapp-r1')));
    expect(wa?.host, 'wa.me');
    expect(wa?.path, '/22670183003');
  });

  testWidgets('the two bells: the guest\'s and the organiser\'s, French as the server wrote, English written here; where they go', (tester) async {
    final guest = NotificationRow(
        id: 'n1', kind: 'event_presence_guest', createdAt: DateTime(2026, 11, 14),
        message: 'Présence confirmée à « Mariage Awa » : vous pouvez ajouter vos photos.',
        params: const {'to': 'customer', 'slug': 'mariage-awa-183', 'title': 'Mariage Awa'});
    final org = NotificationRow(
        id: 'n2', kind: 'event_presence', createdAt: DateTime(2026, 11, 14), orgId: 'o1',
        message: 'Nora Invitée a confirmé sa présence (2 personnes) — Mariage Awa',
        params: const {'to': 'shop', 'name': 'Nora Invitée', 'people': 2, 'title': 'Mariage Awa'});
    for (final lang in ['fr', 'en']) {
      late List<String> out;
      await _pump(tester, Builder(builder: (context) {
        out = [notificationLine(context, guest), notificationLine(context, org)];
        return const SizedBox();
      }), lang: lang);
      expect(out, lang == 'fr'
          ? ['Présence confirmée à « Mariage Awa » : vous pouvez ajouter vos photos.', 'Nora Invitée a confirmé sa présence (2 personnes) — Mariage Awa']
          : ['Presence confirmed at “Mariage Awa”: you can add your photos.', 'Nora Invitée confirmed they are coming (2 people) — Mariage Awa']);
    }
    expect(notificationTarget(guest), '/invitations');
    expect(notificationTarget(org), '/o/o1/evenements/invites');
  });

  test('the router: /presence and /invitations on the street\'s half, open in every signed-in phase; a gate keeps ?apercu=', () {
    final src = File('lib/core/nav/router.dart').readAsStringSync();
    expect(src, contains("static const presence = '/presence';"));
    expect(src, contains("static const myInvitations = '/invitations';"));
    expect(RegExp(r'at\(Routes\.presence\) \|\|').allMatches(src).length, 4, reason: 'noOrg, picking, ready — and backHere');
    expect(RegExp(r'at\(Routes\.myInvitations\) \|\|').allMatches(src).length, 3, reason: 'noOrg, picking and ready');
    final street = src.substring(src.indexOf('bool _shopperPath'), src.indexOf('Future<bool>? _businessScreens'));
    expect(street, contains('Routes.presence,'));
    expect(street, contains('Routes.myInvitations,'));
    expect(src, contains('Uri(path: state.uri.path, query: state.uri.hasQuery ? state.uri.query : null).toString()'));
    expect(RegExp(r'stashReturnTo\(backHere\(\)\)').allMatches(src).length, 3, reason: 'sign-in, the code, the second step');
  });

  testWidgets('« Rappel WhatsApp la veille »: off by default, sent as chosen; hidden without a number', (tester) async {
    final repo = _Invitations(cardAnswer: const PresenceCard(title: 'Mariage Awa', hasPhone: true));
    await _pump(tester, PresenceScreen(repo: repo, slug: 'mariage-awa-183', toInvitations: () {}));
    final sw = find.byKey(const Key('presence-share-phone'));
    expect(sw, findsOneWidget);
    expect(find.text('Rappel WhatsApp la veille'), findsOneWidget);
    expect(find.text('L’organisateur verra votre numéro pour vous écrire.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(sw).value, isFalse, reason: 'off by default');
    await tester.tap(find.byKey(const Key('presence-confirm')));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'confirm:mariage-awa-183:null:1:', reason: 'not shared');

    final on = _Invitations(cardAnswer: const PresenceCard(title: 'Mariage Awa', hasPhone: true));
    await _pump(tester, PresenceScreen(repo: on, slug: 'mariage-awa-183', toInvitations: () {}));
    await tester.tap(find.byKey(const Key('presence-share-phone')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('presence-confirm')));
    await tester.pumpAndSettle();
    expect(on.calls.last, 'confirm:mariage-awa-183:null:1::phone', reason: 'shared by choice');

    // a confirmation of before that shared it starts on
    await _pump(tester, PresenceScreen(
        repo: _Invitations(cardAnswer: const PresenceCard(title: 'Mariage Awa', hasPhone: true, myPeople: 2, mySharePhone: true)),
        slug: 'mariage-awa-183'));
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('presence-share-phone'))).value, isTrue);

    // no number on the account: no switch
    await _pump(tester, PresenceScreen(repo: _Invitations(cardAnswer: const PresenceCard(title: 'Mariage Awa')), slug: 'mariage-awa-183'));
    expect(find.byKey(const Key('presence-share-phone')), findsNothing);
  });

  testWidgets('answers closed, already confirmed: the photos and « Mes invitations », pushed so Back returns', (tester) async {
    final repo = _Invitations(
      cardAnswer: const PresenceCard(title: 'Mariage Awa', open: false, album: true, myPeople: 2),
      mineList: [_inv(used: 1)],
    );
    tester.view.physicalSize = const Size(420, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: '/presence/mariage-awa-183', routes: [
      GoRoute(path: '/presence/:slug', builder: (_, state) => PresenceScreen(repo: repo, slug: state.pathParameters['slug']!, pick: _two)),
      GoRoute(path: '/invitations', builder: (_, _) => const Scaffold(body: Text('page invitations'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presence-done')), findsOneWidget);
    expect(find.text('Vous avez confirmé votre présence.'), findsOneWidget);
    expect(find.text('Les réponses sont fermées pour cet événement.'), findsOneWidget);
    expect(find.textContaining('Ajouter des photos · 1 / 5'), findsOneWidget);
    expect(find.byKey(const Key('presence-confirm')), findsNothing);
    await tester.tap(find.byKey(const Key('presence-invitations')));
    await tester.pumpAndSettle();
    expect(find.text('page invitations'), findsOneWidget);
    expect(router.canPop(), isTrue, reason: 'pushed, not gone to');
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('presence-done')), findsOneWidget);

    // a cancelled card says so, confirmed or not
    await _pump(tester, PresenceScreen(
        repo: _Invitations(cardAnswer: const PresenceCard(title: 'Gala', open: false, cancelled: true, myPeople: 1)), slug: 'gala'));
    expect(find.byKey(const Key('presence-cancelled')), findsOneWidget);
    expect(find.byKey(const Key('presence-done')), findsNothing);
  });

  testWidgets('more photos chosen than are left (a browser\'s picker): the first sent, and said', (tester) async {
    final repo = _Invitations(mineList: [_inv(used: 4)]);
    Future<List<PickedPhoto>> three(int limit) async => [
          for (var i = 0; i < 3; i++) (bytes: Uint8List.fromList([1, 2, 3]), type: 'image/jpeg'),
        ];
    await _pump(tester, MyInvitationsScreen(repo: repo, pick: three, now: () => DateTime(2026, 11, 14)));
    await tester.tap(find.byKey(const ValueKey('invitation-add-18318318-2222-0000-0000-000000000001')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('photo:')).length, 1);
    expect(find.textContaining('Seules vos 1 premières photos sont envoyées (5 par invité).'), findsOneWidget);
  });

  group('the real router (183): signed out at /presence/x?apercu=t, back there after sign-in', () {
    late LocalDb db;
    setUp(() async {
      db = await LocalDb.open(path: inMemoryDatabasePath);
    });
    tearDown(() => db.close());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<(SessionController, GoRouter, _Server)> app(WidgetTester tester, {List<OrgSummary> orgs = const []}) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final server = _Server()..orgs = orgs;
      final s = SessionController(db: db, auth: server, admin: _Admin(), accounting: AccountingRepository(null));
      await tester.runAsync(s.boot);
      expect(s.phase, SessionPhase.signedOut);
      final router = buildRouter(s);
      await tester.pumpWidget(AppScope(
        session: s,
        localeController: LocaleController(db),
        db: db,
        auth: s.auth,
        admin: s.admin,
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
        credit: CreditRepository(null),
        tontine: TontineRepository(null),
        production: ProductionRepository(null),
        notify: NotificationsRepository(null),
        analytics: AnalyticsRepository(null),
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('fr'),
          localizationsDelegates: Strings.localizationsDelegates,
          supportedLocales: Strings.supportedLocales,
        ),
      ));
      await settle(tester);
      return (s, router, server);
    }

    for (final ready in [false, true]) {
      testWidgets(ready ? 'a member of a business (ready)' : 'a guest with no business (noOrg)', (tester) async {
        final (s, router, server) = await app(tester,
            orgs: ready ? const [OrgSummary(id: 'shop-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner'])] : const []);
        router.go('/presence/x?apercu=t');
        await settle(tester);
        expect(router.state.uri.path, Routes.signIn, reason: 'signed out: the sign-in first');
        server
          ..live = true
          ..user = _nora;
        await tester.runAsync(() => s.handleSignedIn(_nora));
        await settle(tester);
        if (s.phase == SessionPhase.choosingPin) {
          // a business on the phone: its code chosen first (108), then back
          await tester.runAsync(() => s.setPin('2580'));
          await settle(tester);
        }
        expect(s.phase, ready ? SessionPhase.ready : SessionPhase.noOrg);
        expect(router.state.uri.toString(), '/presence/x?apercu=t');
        await tester.pump(const Duration(minutes: 2));
      });
    }

    test('the page kept on the device: a new account by e-mail, signed in after a reload, comes back to it — once', () async {
      final before = SessionController(db: db, auth: _Server(), admin: _Admin(), accounting: AccountingRepository(null));
      before.stashReturnTo('/presence/x?apercu=t');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // the reload: memory gone, the device's copy stays
      final server = _Server()
        ..live = true
        ..user = _nora;
      final after = SessionController(db: db, auth: server, admin: _Admin(), accounting: AccountingRepository(null));
      expect(after.takeReturnTo(), isNull);
      await after.handleSignedIn(_nora);
      expect(after.phase, SessionPhase.noOrg);
      expect(after.takeReturnTo(), '/presence/x?apercu=t');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await db.readPref('return_to_after_sign_in'), isNull, reason: 'cleared once used');
      // any other page is memory only, and clears a page of before
      before.stashReturnTo('/achat-billets/gala-1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      before.stashReturnTo('/o/shop-1/produits');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await db.readPref('return_to_after_sign_in'), isNull);
    });
  });
}

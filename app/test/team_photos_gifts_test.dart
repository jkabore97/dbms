import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/access/org_access.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/team.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/cauris/cauris_repository.dart';
import 'package:kaj_app/core/cauris/feature_states.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/core/format/money.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/features/account/compte_screen.dart';
import 'package:kaj_app/features/admin/cauris_gifts_screen.dart';
import 'package:kaj_app/features/admin/team_screen.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/retail/photo_quota.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 100, the server's half in the app: the Équipe screen and its seat,
/// a salary recorded, the photo counter and its slot, the platform's gift
/// sheet, and what feature_states() and the bell now carry.
const _shop = OrgSummary(id: 'o1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);

class _Admin extends AdminRepository {
  _Admin(this.team) : super(null);

  final TeamOverview? team;
  final salaries = <String, (double?, String)>{};
  final gifts = <String>[];
  final revoked = <String>[];
  final withdrawn = <String>[];

  @override
  Future<void> revokeMembership(String membershipId) async => revoked.add(membershipId);

  @override
  Future<void> revokeInvitation(String invitationId) async => withdrawn.add(invitationId);

  @override
  Future<TeamOverview?> teamOverview(String orgId) async => team;

  @override
  Future<void> setMemberSalary(String orgId, String userId,
      {double? amount, String period = 'month'}) async {
    salaries[userId] = (amount, period);
  }

  @override
  Future<void> platformGiveCauris(String orgId, int points,
      {String? note, DateTime? expiresOn}) async {
    gifts.add('$orgId:$points:${expiresOn == null ? 'gift' : 'promo'}:$note');
  }

  @override
  Future<FeatureStates?> featureStates(String orgId) async => null;
}

class _Console extends ConsoleRepository {
  _Console() : super(null);

  @override
  Future<OrgPage> searchOrgs({
    String? query,
    String? profile,
    String status = 'active',
    String? activity,
    String sort = 'activity',
    int limit = 50,
    int offset = 0,
  }) async =>
      const OrgPage(rows: [
        OrgRow(id: 'f1', name: 'Ferme du Nord', slug: 'ferme-du-nord', profile: 'farm',
            currency: 'XOF', memberCount: 2),
        OrgRow(id: 'a1', name: 'Entraide', slug: 'entraide', profile: 'association',
            currency: 'XOF', memberCount: 1),
      ], total: 2);
}

class _Cauris extends CaurisRepository {
  _Cauris() : super(null);

  @override
  Future<CaurisWallet?> wallet(String orgId) async => CaurisWallet(
        balance: 250,
        week: 0,
        promo: [PromoLot(points: 200, until: DateTime(2026, 11, 30))],
      );

  @override
  Future<List<({String feature, int cost, int minDays})>> costs() async => const [
        (feature: 'analytics', cost: 400, minDays: 0),
        (feature: 'accounting', cost: 500, minDays: 0),
        (feature: 'photo_slot', cost: 50, minDays: 0),
      ];
}

TeamOverview _team({bool open = false, bool setupDone = true}) => TeamOverview(
      seats: TeamSeats(free: 1, used: open ? 0 : 1, open: open, setupDone: setupDone, cost: 400),
      members: const [
        TeamMember(userId: 'u1', name: 'Awa Sanou', roles: ['owner'], isOwner: true,
            isMe: true, membershipIds: ['m1']),
        TeamMember(userId: 'u2', name: 'Bintou', roles: ['employee'], salary: 45000, period: 'month',
            membershipIds: ['m2', 'm3']),
        TeamMember(userId: 'u3', name: 'Issa', roles: ['employee'], hourly: 500,
            membershipIds: ['m4']),
      ],
      invitations: const [
        TeamInvite(id: 'i1', code: 'AB12-CD34', name: 'Coumba', blocked: true),
        TeamInvite(id: 'i2', code: 'EF56-GH78', phone: '+22670000000'),
      ],
    );

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: child,
    );

void main() {
  test('feature_states (100) carries the promotions, the photos and the team', () {
    final f = FeatureStates.fromJson({
      'plan': 'free',
      'balance': 250,
      'promo': [
        {'points': 200, 'until': '2026-11-30'},
      ],
      'photos': {'used': 10, 'limit': 10, 'slots': 0, 'slot_cost': 50},
      'team': {'free': 1, 'used': 1, 'open': false, 'unlimited': false, 'setup_done': true, 'cost': 400},
    });
    expect(f.promo.single.points, 200);
    expect(f.photos!.full, isTrue);
    expect(f.photos!.slotCost, 50);
    expect(f.team!.open, isFalse);
    expect(f.team!.cost, 400);
    // A database before 100 says nothing: nothing is drawn.
    final old = FeatureStates.fromJson({'plan': 'free', 'balance': 0});
    expect(old.photos, isNull);
    expect(old.team, isNull);
    expect(old.promo, isEmpty);
    // Pro: no limit to say.
    expect(PhotoQuota.fromJson({'used': 40, 'limit': null}).limited, isFalse);
  });

  testWidgets('Équipe: the people with their salary, the seat taken, the invitation out',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = _Admin(_team());
    await tester.pumpWidget(_app(TeamScreen(
        org: _shop, admin: admin, onboarding: OnboardingRepository(null))));
    await tester.pumpAndSettle();
    expect(find.text('Votre personne offerte est là'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.byKey(const Key('team-unlock')), findsOneWidget);
    expect(find.text('Awa Sanou'), findsOneWidget);
    expect(find.textContaining('45'), findsWidgets);
    expect(find.textContaining('/ mois'), findsOneWidget);
    // Paid by the hour in the payroll: said as such.
    expect(find.textContaining('/ heure'), findsOneWidget);
    // The invitations, each with where it stands.
    expect(find.text('Coumba'), findsOneWidget);
    expect(find.textContaining('ne peut pas entrer : place prise'), findsOneWidget);
    expect(find.textContaining('en attente'), findsOneWidget);

    // A salary, per day, typed as people write it.
    await tester.tap(find.byKey(const Key('team-member-u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-action-salary')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('salary-amount')), '2.500');
    await tester.tap(find.text('par jour'));
    await tester.tap(find.byKey(const Key('salary-save')));
    await tester.pumpAndSettle();
    expect(admin.salaries['u2'], (2500.0, 'day'));
  });

  testWidgets('Équipe removes a person (all their grants), never the owner or oneself; withdraws an invitation',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = _Admin(_team());
    await tester.pumpWidget(_app(TeamScreen(
        org: _shop, admin: admin, onboarding: OnboardingRepository(null))));
    await tester.pumpAndSettle();
    // The owner, who is also the viewer: a salary, nothing to remove.
    await tester.tap(find.byKey(const Key('team-member-u1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-action-remove')), findsNothing);
    expect(find.byKey(const Key('team-action-replace')), findsNothing);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('team-member-u2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-action-replace')), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-action-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-remove-confirm')));
    await tester.pumpAndSettle();
    expect(admin.revoked, ['m2', 'm3']);

    await tester.tap(find.byKey(const Key('team-invite-withdraw-i1')));
    await tester.pumpAndSettle();
    expect(admin.withdrawn, ['i1']);
  });

  test('an amount as it is written here', () {
    expect(parseAmount('45.000'), 45000);
    expect(parseAmount('45 000'), 45000);
    expect(parseAmount('45\u202f000'), 45000);
    expect(parseAmount('45,000'), 45000);
    expect(parseAmount('1.250.000'), 1250000);
    expect(parseAmount('2500'), 2500);
    expect(parseAmount('2,5'), 2.5);
    expect(parseAmount(''), isNull);
    expect(parseAmount('beaucoup'), isNull);
  });

  testWidgets('a free seat says so once, and before the setup it waits for it', (tester) async {
    await tester.pumpWidget(_app(SeatCard(
        seats: const TeamSeats(free: 1, used: 0), onUnlock: () {})));
    expect(find.text('1 personne offerte'), findsOneWidget);
    expect(find.text('Place libre'), findsOneWidget);
    expect(find.textContaining('offerte'), findsOneWidget);
    expect(find.byKey(const Key('team-unlock')), findsNothing);
    var finish = 0;
    await tester.pumpWidget(_app(SeatCard(
        seats: const TeamSeats(free: 0, used: 0, open: false, setupDone: false, cost: 400),
        onUnlock: () {},
        onFinishSetup: () => finish++)));
    expect(find.text('Elle s\'ouvre une fois la mise en route terminée.'), findsOneWidget);
    expect(find.byKey(const Key('team-seats-count')), findsNothing);
    await tester.tap(find.byKey(const Key('team-finish-setup')));
    expect(finish, 1);
    // Kept from before 100: said as it is, not « 2 / 1 ».
    await tester.pumpWidget(_app(SeatCard(
        seats: const TeamSeats(free: 1, used: 2, open: false, cost: 400), onUnlock: () {})));
    expect(find.text('2 personnes (limite : 1)'), findsOneWidget);
    // Opened by Mara: said so, not « avec vos cauris ».
    await tester.pumpWidget(_app(SeatCard(
        seats: TeamSeats(free: 1, used: 2, unlimited: true, gift: true,
            until: DateTime(2026, 11, 30, 12)),
        onUnlock: () {})));
    expect(find.text('Offert par Mara jusqu\'au 30/11'), findsOneWidget);
  });

  testWidgets('Compte: before the setup, what opens the seat; the payroll for staff who are not admins',
      (tester) async {
    late String? before, open;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      before = CompteScreen.teamLine(
          context, const TeamSeats(free: 0, used: 0, open: false, setupDone: false));
      open = CompteScreen.teamLine(context, const TeamSeats(free: 1, used: 0));
      return const SizedBox();
    })));
    expect(before, 'Terminez la mise en route pour inviter une personne');
    expect(open, '1 personne offerte');
    expect(CompteScreen.peopleRow(OrgAccess.allEdit, admin: true), 'team');
    expect(CompteScreen.peopleRow(const OrgAccess.forTier({'staff': 'view'}), admin: false), 'payroll');
    expect(
        CompteScreen.peopleRow(const OrgAccess.forTier({'staff': 'hidden'}), admin: false),
        isNull);
  });

  test('an association is offered only its own tools; a farm its own analyses (101)', () {
    expect(PlanTerms.fits('delivery', 'association'), isFalse);
    expect(PlanTerms.fits('delivery', 'church'), isFalse);
    expect(PlanTerms.fits('analytics', 'association'), isFalse);
    expect(PlanTerms.fits('analytics', 'farm'), isTrue);
    expect(PlanTerms.fits('analytics', 'retail'), isTrue);
    expect(PlanTerms.fits('accounting', 'association'), isTrue);
    expect(PlanTerms.fits('team_access', 'association'), isTrue);
    expect(PlanTerms.fits('delivery', 'farm'), isTrue);
  });

  testWidgets('the photo counter: « 7 / 10 », full with the way to one more',
      (tester) async {
    await tester.pumpWidget(_app(const Scaffold(
        body: PhotoCounter(org: _shop, quota: PhotoQuota(used: 7, limit: 10, slotCost: 50)))));
    expect(find.text('7 / 10 photos'), findsOneWidget);
    expect(find.byKey(const Key('photo-buy')), findsNothing);
    await tester.pumpWidget(_app(const Scaffold(
        body: PhotoCounter(org: _shop, quota: PhotoQuota(used: 10, limit: 10, slotCost: 50)))));
    expect(find.text('Acheter une photo (50 cauris)'), findsOneWidget);
    // An article that has its photo takes no new place: no door.
    await tester.pumpWidget(_app(const Scaffold(
        body: PhotoCounter(
            org: _shop, hasPhoto: true, quota: PhotoQuota(used: 10, limit: 10, slotCost: 50)))));
    expect(find.byKey(const Key('photo-buy')), findsNothing);
    // Pro: nothing to count.
    await tester.pumpWidget(_app(const Scaffold(
        body: PhotoCounter(org: _shop, quota: PhotoQuota(used: 40)))));
    expect(find.byKey(const Key('photo-counter')), findsNothing);
    // The sheet: bought only with the cauris to pay.
    await tester.pumpWidget(_app(const Scaffold(
        body: PhotoSlotSheet(
            org: _shop, balance: 20, quota: PhotoQuota(used: 10, limit: 10, slotCost: 50)))));
    expect(tester.widget<FilledButton>(find.byKey(const Key('photo-slot-buy'))).onPressed, isNull);
  });

  testWidgets('the console finds a business by name and gives it cauris', (tester) async {
    final admin = _Admin(null);
    await tester.pumpWidget(_app(CaurisGiftsScreen(
        console: _Console(), admin: admin, cauris: _Cauris())));
    await tester.pumpAndSettle();
    expect(find.text('Ferme du Nord'), findsOneWidget);
    await tester.tap(find.text('Entraide'));
    await tester.pumpAndSettle();
    expect(find.text('250'), findsOneWidget);
    expect(find.text('dont 200 à utiliser avant le 30/11'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gift-cauris')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gift-points')), '300');
    await tester.enterText(find.byKey(const Key('gift-note')), 'Bienvenue');
    await tester.tap(find.byKey(const Key('gift-save')));
    await tester.pumpAndSettle();
    expect(admin.gifts, ['a1:300:gift:Bienvenue']);

    // Above 500, asked once more — one zero too many is a lot of cauris.
    await tester.tap(find.byKey(const Key('gift-cauris')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gift-points')), '5 000');
    await tester.tap(find.byKey(const Key('gift-save')));
    await tester.pumpAndSettle();
    expect(find.text('Offrir 5000 cauris ?'), findsOneWidget);
    expect(admin.gifts, hasLength(1));
    await tester.tap(find.byKey(const Key('gift-confirm')));
    await tester.pumpAndSettle();
    expect(admin.gifts.last, 'a1:5000:gift:');
  });

  testWidgets('the console offers an association only the tools it has', (tester) async {
    final admin = _Admin(null);
    await tester.pumpWidget(_app(CaurisGiftsScreen(
        console: _Console(), admin: admin, cauris: _Cauris())));
    await tester.pumpAndSettle();
    // The association wears the picker's sign.
    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    await tester.tap(find.text('Entraide'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gift-unlock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gift-tool')));
    await tester.pumpAndSettle();
    // Analyses are a shop's: not in the list for an association; its books are.
    expect(find.text(PlanTerms.labelOf('analytics')), findsNothing);
    expect(find.text(PlanTerms.labelOf('accounting')), findsWidgets);
  });

  testWidgets('the bell says the gifts in English and opens the wallet', (tester) async {
    late String gift, tool;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Builder(builder: (context) {
        gift = notificationLine(context, NotificationRow.fromRow({
          'id': 'n1', 'kind': 'cauris_promo', 'org_id': 'a1', 'message': 'Mara vous offre…',
          'created_at': '2026-10-07T10:00:00Z',
          'params': {'to': 'shop', 'points': 200, 'until': '2026-11-30', 'note': 'Fête'},
        }));
        tool = notificationLine(context, NotificationRow.fromRow({
          'id': 'n2', 'kind': 'feature_gift', 'org_id': 'a1', 'message': 'Mara vous offre…',
          'created_at': '2026-10-07T10:00:00Z',
          'params': {'to': 'shop', 'feature': 'pro_all', 'until': '2026-11-30'},
        }));
        return const SizedBox();
      }),
    ));
    expect(gift, 'Mara gives you 200 cauris, to spend before 30/11/2026: Fête.');
    expect(tool, 'Mara gives you Full Mara Pro until 30/11/2026.');
    expect(
        notificationTarget(NotificationRow.fromRow({
          'id': 'n1', 'kind': 'cauris_gift', 'org_id': 'a1', 'message': '',
          'created_at': '2026-10-07T10:00:00Z', 'params': {'to': 'shop'},
        })),
        '/o/a1/chemin');
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// Google sign-in: the button only when the project has Google on; the
/// session that comes back from Google — on the web after a reload, on
/// Android as an auth event — lands on the device code exactly as a
/// password does; and nothing else is ever taken for it.
class _Server extends AuthRepository {
  _Server() : super(null);

  bool live = false;
  User? user;
  int launches = 0;
  int fetched = 0;
  bool google = true;

  @override
  bool get isConfigured => true;

  @override
  bool get hasLiveSession => live;

  @override
  User? get currentUser => user;

  @override
  Future<bool> googleAvailable() async => google;

  @override
  Future<void> signInWithGoogle() async => launches++;

  /// What my_orgs() answers: Awa's shop (the device code is for somebody
  /// with a business, 108).
  List<OrgSummary> orgs = const [
    OrgSummary(id: 'shop-1', name: 'Boutique Awa', profile: 'retail', roles: ['owner']),
  ];

  @override
  Future<List<OrgSummary>> fetchOrgs() async {
    fetched++;
    return orgs;
  }
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

const _awa = User(
  id: 'awa-1',
  appMetadata: {'provider': 'google'},
  userMetadata: {'full_name': 'Awa Ouédraogo'},
  aud: 'authenticated',
  email: 'awa@example.com',
  createdAt: '2026-10-05T00:00:00Z',
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;
  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  SessionController sessionOn(_Server server) => SessionController(
    db: db,
    auth: server,
    admin: _Admin(),
    accounting: AccountingRepository(null),
  );

  group('which providers the project has on', () {
    AuthRepository probe(http.Client client) => _Probe(client);

    test('no server, no button', () async {
      expect(await AuthRepository(null).googleAvailable(), isFalse);
    });

    test('reads external.google from the settings, with the key', () async {
      var asked = 0;
      final client = MockClient((req) async {
        asked++;
        expect(req.url.path, '/auth/v1/settings');
        expect(req.headers['apikey'], 'pk');
        return http.Response(
          jsonEncode({
            'external': {'google': true, 'email': true},
          }),
          200,
        );
      });
      final repo = probe(client);
      expect(await repo.googleAvailable(), isTrue);
      expect(await repo.googleAvailable(), isTrue);
      expect(asked, 1, reason: 'asked once per launch');
    });

    test('off, refused or unreachable all mean no button', () async {
      final off = probe(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'external': {'google': false},
            }),
            200,
          ),
        ),
      );
      expect(await off.googleAvailable(), isFalse);
      final refused = probe(MockClient((_) async => http.Response('', 401)));
      expect(await refused.googleAvailable(), isFalse);
      final down = probe(MockClient((_) async => throw Exception('x')));
      expect(await down.googleAvailable(), isFalse);
    });
  });

  group('the session that comes back', () {
    test('back from Google: identity saved, then the code to choose', () async {
      final server = _Server();
      final session = sessionOn(server);
      await session.signInWithGoogle();
      expect(server.launches, 1);

      // The browser is still open: nothing to take yet.
      expect(await session.adoptGoogleSession(), isFalse);

      server
        ..live = true
        ..user = _awa;
      expect(await session.adoptGoogleSession(), isTrue);
      expect(
        session.phase,
        SessionPhase.choosingPin,
        reason: 'the device code, as after a password',
      );
      expect(session.identity?.userId, 'awa-1');
      expect(session.identity?.displayName, 'Awa Ouédraogo');

      // Taken once.
      expect(await session.adoptGoogleSession(), isFalse);
    });

    test('back from Google with no business (a shopper): no code to choose (108)', () async {
      final server = _Server()..orgs = const [];
      final session = sessionOn(server);
      await session.signInWithGoogle();
      server
        ..live = true
        ..user = _awa;
      expect(await session.adoptGoogleSession(), isTrue);
      expect(session.phase, SessionPhase.noOrg,
          reason: 'the code protects businesses: a shopper goes to the street');
      expect(session.identity?.hasPin, isFalse);
    });

    test('the web reload: boot takes it before anything else', () async {
      final server = _Server();
      await sessionOn(server).signInWithGoogle();
      server
        ..live = true
        ..user = _awa;
      final reloaded = sessionOn(server);
      await reloaded.boot();
      expect(reloaded.phase, SessionPhase.choosingPin);
    });

    test('a password sign-in is never taken for Google', () async {
      final server = _Server()
        ..live = true
        ..user = _awa;
      final session = sessionOn(server);
      expect(
        await session.adoptGoogleSession(),
        isFalse,
        reason: 'no note on the device that anyone left for Google',
      );
      expect(session.phase, SessionPhase.booting);
    });

    test('a note older than a quarter of an hour is forgotten', () async {
      final server = _Server()
        ..live = true
        ..user = _awa;
      await db.writePref(
        'google_pending',
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      );
      expect(await sessionOn(server).adoptGoogleSession(), isFalse);
      expect(await db.readPref('google_pending'), isNull);
    });

    test('the same person signing in twice at once is one sign-in', () async {
      final server = _Server()..live = true;
      final session = sessionOn(server);
      // A device that already has a code goes straight to the businesses,
      // which is what counts the runs.
      await db.saveIdentity(
        const LocalIdentity(userId: 'awa-1', pinSalt: 's', pinHash: 'h'),
      );
      await Future.wait([
        session.handleSignedIn(_awa),
        session.handleSignedIn(_awa),
      ]);
      expect(server.fetched, 1);
    });
  });

  group('the button', () {
    Future<void> pump(
      WidgetTester tester,
      _Server server, {
      required Future<void> Function()? onGoogle,
    }) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: const [
            Strings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: Strings.supportedLocales,
          home: LoginScreen(
            auth: server,
            onSignedIn: (_) async {},
            onGoogle: onGoogle,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shown when Google is on, and leaves for it', (tester) async {
      final server = _Server();
      var left = 0;
      await pump(tester, server, onGoogle: () async => left++);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      expect(find.text('ou'), findsOneWidget);
      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pumpAndSettle();
      expect(left, 1);
    });

    testWidgets('hidden when the project has Google off', (tester) async {
      await pump(tester, _Server()..google = false, onGoogle: () async {});
      expect(find.byKey(const Key('google-sign-in')), findsNothing);
    });
  });
}

/// The real settings probe, on a repository that reports a server.
class _Probe extends AuthRepository {
  _Probe(http.Client client)
    : super(
        null,
        authUrl: 'https://x.supabase.co/auth/v1',
        apiKey: 'pk',
        httpClient: client,
      );

  @override
  bool get isConfigured => true;
}

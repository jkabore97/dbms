import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/core/security/security_repository.dart';
import 'package:kaj_app/core/security/security_settings.dart';
import 'package:kaj_app/features/account/security_screen.dart';
import 'package:kaj_app/features/auth/pin_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Compte › Sécurité (075).
///
/// Before it: the device code was asked only when the session had expired
/// offline — a phone left on the counter opened into the shop's money —
/// and the account had no list of where it was signed in.
class _Api extends SecurityRepository {
  _Api() : super(null);

  int closedOthers = 0;
  final closed = <String>[];
  final logged = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<List<SignInSession>> sessions() async => [
        const SignInSession(
            id: 's1',
            current: true,
            userAgent: 'Mozilla/5.0 (Linux; Android 14) Chrome/141'),
        SignInSession(
            id: 's2',
            current: false,
            userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/141',
            lastUsed: DateTime(2026, 10, 4, 18, 2)),
      ];

  @override
  Future<List<SecurityEvent>> events({int limit = 20}) async => [
        SecurityEvent(
            kind: 'new_device', detail: 'Windows · navigateur', at: DateTime(2026, 10, 4)),
      ];

  @override
  Future<int> closeOtherSessions() async {
    closedOthers++;
    return 1;
  }

  @override
  Future<void> closeSession(String sessionId) async => closed.add(sessionId);

  @override
  Future<void> log(String kind, {String? detail}) async => logged.add(kind);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR');
  });

  group('the lock delay', () {
    late LocalDb db;
    setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
    tearDown(() => db.close());

    test('5 min by default, kept across launches, and one device id', () async {
      final a = SecuritySettings(db);
      await a.load();
      expect(a.lockAfter, 5);
      expect(a.hideAmounts, isFalse);
      await a.setLockAfter(null);
      await a.setHideAmounts(true);
      final id = await a.deviceId();

      final b = SecuritySettings(db);
      await b.load();
      expect(b.lockAfter, isNull, reason: '« Jamais » remembered');
      expect(b.hideAmounts, isTrue);
      expect(await b.deviceId(), id, reason: 'the same phone, the same id');
    });

    test('the owner\'s rule is never loosened, and « Jamais » becomes the rule',
        () async {
      final s = SecuritySettings(db);
      await s.load();
      await s.setLockAfter(15);
      s.setPolicy(5);
      expect(s.effectiveLock, 5);
      expect(s.allows(15), isFalse);
      expect(s.allows(null), isFalse);
      expect(s.allows(1), isTrue);
      await s.setLockAfter(null);
      expect(s.effectiveLock, 5);
      await s.setLockAfter(1);
      expect(s.effectiveLock, 1, reason: 'stricter than the rule is allowed');
    });
  });

  test('the device list names what it can, and says when it cannot', () {
    expect(describeUserAgent('Mozilla/5.0 (Linux; Android 14) Chrome/141'),
        'Android · Chrome');
    expect(describeUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17) Safari/605'),
        'iPhone · Safari');
    expect(describeUserAgent('Dart/3.9 (dart:io)'), 'Appareil · application Mara');
    expect(describeUserAgent(null), 'Appareil inconnu');
  });

  group('the code', () {
    test('a lock asks the code again, only from inside and only with a code',
        () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final salt = PinCodec.newSalt();
      await db.saveIdentity(LocalIdentity(
          userId: 'u1',
          phone: '+22670000000',
          pinSalt: salt,
          pinHash: PinCodec.hash('2580', salt)));
      final session = SessionController(
        db: db,
        auth: AuthRepository(null),
        admin: AdminRepository(null),
        accounting: AccountingRepository(null),
      );
      await session.boot();
      expect(session.phase, SessionPhase.locked,
          reason: 'no live token: the code is asked at launch already');
      expect(session.lockNow(), isFalse,
          reason: 'already locked: nothing to do');

      expect(await session.changePin('1111', '7391'), 'Code actuel incorrect.');
      expect(await session.changePin('2580', '7391'), isNull);
      final saved = (await db.loadIdentity())!;
      expect(
          PinCodec.verify('7391', salt: saved.pinSalt!, hash: saved.pinHash!),
          isTrue);
    });

    testWidgets('the fingerprint sits in the keypad and is offered at once',
        (tester) async {
      var asked = 0;
      var accepted = 0;
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final salt = PinCodec.newSalt();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: PinScreen(
          purpose: PinPurpose.unlock,
          identity: LocalIdentity(
              userId: 'u1',
              pinSalt: salt,
              pinHash: PinCodec.hash('2580', salt)),
          onPinAccepted: (_) async => accepted++,
          onBiometric: () async {
            asked++;
            return true;
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(asked, 1, reason: 'offered on opening, like the phone\'s own lock');
      expect(accepted, 1);
      expect(find.byTooltip('Empreinte digitale'), findsOneWidget);
    });
  });

  testWidgets('the page: the delay, the devices, closing the others',
      (tester) async {
    tester.view.physicalSize = const Size(420, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));
    final settings = SecuritySettings(db);
    await tester.runAsync(settings.load);
    settings.setPolicy(15);
    final api = _Api();

    await tester.pumpWidget(MaterialApp(
        home: SecurityScreen(settings: settings, api: api)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Après 5 min'), findsOneWidget);
    expect(find.text('Conseillé'), findsOneWidget);
    expect(find.textContaining('Votre entreprise demande le code après 15 min'),
        findsOneWidget);
    expect(find.text('Non permis par votre entreprise'), findsNWidgets(2),
        reason: '1 h and « Jamais » exceed the rule');

    await tester.runAsync(() async {
      await tester.tap(find.text('Après 1 min'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(settings.lockAfter, 1);
    expect(api.logged, contains('lock_changed'));

    expect(find.text('Android · Chrome'), findsOneWidget);
    expect(find.text('Cet appareil'), findsOneWidget);
    expect(find.text('Windows · Chrome'), findsOneWidget);
    expect(find.text('Nouvel appareil : Windows · navigateur'), findsOneWidget);

    await tester.tap(find.byTooltip('Déconnecter cet appareil'));
    await tester.pump();
    expect(api.closed, ['s2']);

    await tester.ensureVisible(find.text('Déconnecter les autres appareils'));
    await tester.tap(find.text('Déconnecter les autres appareils'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Déconnecter'));
    await tester.pumpAndSettle();
    expect(api.closedOthers, 1);
  });
}

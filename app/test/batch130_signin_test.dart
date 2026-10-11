// Batch 130 §4: sign-in on the iPhone (App Review 4.8).
//
//   * « Continuer avec Apple » above Google, as tall and as wide, on the
//     sign-in screen; Google is never drawn alone on an iPhone; Android and
//     the web keep their buttons;
//   * after Google, the in-app Safari sheet is closed by the app once the
//     session is in (it never closes itself on a redirect to the app).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/nav/session.dart';
import 'package:kaj_app/features/auth/login_screen.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, AuthState;

/// A project with Google and Apple both switched on (or not).
class _Server extends AuthRepository {
  _Server({this.apple = true, super.closeSheet}) : super(null);

  final bool apple;
  final events = StreamController<AuthState>.broadcast();

  @override
  bool get isConfigured => true;
  @override
  Future<bool> googleAvailable() async => true;
  @override
  Future<bool> appleAvailable() async => apple;
  @override
  Stream<AuthState>? get onAuthStateChange => events.stream;
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<void> pump(WidgetTester tester, _Server server) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
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
        onGoogle: () async {},
        onApple: () async {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  final apple = find.byKey(const Key('apple-sign-in'));
  final google = find.byKey(const Key('google-sign-in'));

  testWidgets('iPhone: Apple above Google, same height and width', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(tester, _Server());
    expect(apple, findsOneWidget);
    expect(google, findsOneWidget);
    expect(tester.getTopLeft(apple).dy, lessThan(tester.getTopLeft(google).dy));
    expect(tester.getSize(apple).height, tester.getSize(google).height);
    expect(tester.getSize(apple).width, tester.getSize(google).width);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iPhone with Apple off: no Google alone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(tester, _Server(apple: false));
    expect(apple, findsNothing);
    expect(google, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android keeps today\'s buttons: Google, no Apple', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pump(tester, _Server());
    expect(apple, findsNothing);
    expect(google, findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  test('the Safari sheet is closed on an iPhone, and only there', () async {
    var closed = 0;
    final server = _Server(closeSheet: () async => closed++);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await server.closeSignInSheet();
    expect(closed, 1);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await server.closeSignInSheet();
    expect(closed, 1);
    // A sheet already gone, or none: nothing thrown.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _Server(closeSheet: () async => throw StateError('no sheet')).closeSignInSheet();
  });

  test('the session closes the sheet when Google\'s session arrives', () async {
    var closed = 0;
    final server = _Server(closeSheet: () async => closed++);
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final session = SessionController(
        db: db, auth: server, admin: _Admin(), accounting: AccountingRepository(null));
    addTearDown(session.dispose);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    server.events.add(const AuthState(AuthChangeEvent.tokenRefreshed, null));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, 0, reason: 'only a sign-in closes it');
    server.events.add(const AuthState(AuthChangeEvent.signedIn, null));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, 1);
  });
}

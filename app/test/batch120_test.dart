import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/notify/push_client.dart';
import 'package:kaj_app/core/notify/push_client_stub.dart';
import 'package:kaj_app/core/notify/push_setup.dart';
import 'package:kaj_app/core/onboarding/application_form.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';
import 'package:kaj_app/features/admin/request_form_screen.dart';
import 'package:kaj_app/features/notify/push_diagnostics.dart';
import 'package:kaj_app/features/notify/push_prompt.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';

/// Batch 120, the owner's three: « I want the notification to be enabled
/// as soon as a shopper opens the app and showed every time a user opens
/// the app and notification is not already activated » — the pop-up at the
/// opening, and the diagnostics that say which step a phone is missing;
/// « When finish creating farm, the app told me that my shop is ready » —
/// the end of the setup in each kind's own word; « In the admin panel …
/// when the keyboard raises, the app content becomes all white ».

class _Device implements PushPromptDevice {
  _Device(this.answer, {this.settings = true});

  PushStanding answer;
  final bool settings;
  int looks = 0;
  int enabled = 0;
  int opened = 0;

  @override
  Future<PushStanding> standing() async {
    looks++;
    return answer;
  }

  @override
  Future<bool> enable() async {
    enabled++;
    answer = PushStanding.on;
    return true;
  }

  @override
  Future<bool> openSettings() async {
    opened++;
    return true;
  }

  @override
  bool get canOpenSettings => settings;
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<PlatformTodo> todo() async => const PlatformTodo({});
}

class _Onboarding extends OnboardingRepository {
  _Onboarding() : super(null);
  @override
  Future<ApplicationForm?> applicationForm({bool strict = false}) async => null;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('« Activer les notifications ? » at the opening', () {
    late GlobalKey<NavigatorState> nav;
    late _Device device;
    late PushPrompt prompt;

    Future<void> app(WidgetTester tester, {Widget? body}) async {
      nav = GlobalKey<NavigatorState>();
      prompt = PushPrompt(device: device, context: () => nav.currentContext);
      addTearDown(prompt.dispose);
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Scaffold(body: body ?? const Text('la rue')),
      ));
    }

    testWidgets('a signed-in person whose device is not on is asked; « Activer » turns it on',
        (tester) async {
      device = _Device(PushStanding.askable);
      await app(tester);
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget);
      expect(find.text('Activer les notifications ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('push-prompt-enable')));
      await _settle(tester);
      expect(device.enabled, 1, reason: 'the device is asked from the tap itself');
      expect(find.byKey(const Key('push-prompt')), findsNothing);
      expect(find.text('Activé : les notifications sonneront même l\'application fermée.'), findsOneWidget);
    });

    testWidgets('« Plus tard »: never twice in one opening, asked again at the next one',
        (tester) async {
      device = _Device(PushStanding.askable);
      await app(tester);
      prompt.phase(signedIn: true);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('push-prompt-later')));
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsNothing);
      // The session moves (a business opened, a refresh): same opening.
      prompt.phase(signedIn: true);
      prompt.resumed(const Duration(minutes: 20));
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsNothing);
      // Back after more than an hour: an opening again.
      prompt.resumed(const Duration(hours: 2));
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget);
    });

    testWidgets('nothing over a gate or a signed-out street; asked once signed in',
        (tester) async {
      device = _Device(PushStanding.askable);
      await app(tester);
      // The code screen, the second step, a signed-out shopper.
      prompt.phase(signedIn: false);
      prompt.resumed(const Duration(hours: 3));
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsNothing);
      expect(device.looks, 0);
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget);
    });

    testWidgets('a sign-out, then a sign-in on the same phone: asked again', (tester) async {
      device = _Device(PushStanding.askable);
      await app(tester);
      prompt.phase(signedIn: true);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('push-prompt-later')));
      await _settle(tester);
      prompt.signedOut();
      prompt.phase(signedIn: false);
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget);
    });

    testWidgets('already on, allowed but not written now, or nothing to ring with: nothing shown',
        (tester) async {
      for (final standing in [PushStanding.on, PushStanding.later, PushStanding.unavailable]) {
        device = _Device(standing);
        await app(tester);
        prompt.phase(signedIn: true);
        await _settle(tester);
        expect(find.byType(AlertDialog), findsNothing, reason: '$standing');
        expect(device.looks, 1);
      }
    });

    testWidgets('blocked on a phone: it says so and opens the settings', (tester) async {
      device = _Device(PushStanding.blocked);
      await app(tester);
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt-blocked')), findsOneWidget);
      expect(find.text('Notifications bloquées'), findsOneWidget);
      await tester.tap(find.byKey(const Key('push-prompt-settings')));
      await _settle(tester);
      expect(device.opened, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('blocked in a browser: the way through its settings, no button it cannot keep',
        (tester) async {
      device = _Device(PushStanding.blocked, settings: false);
      await app(tester);
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(find.textContaining('Touchez le cadenas'), findsOneWidget);
      expect(find.byKey(const Key('push-prompt-settings')), findsNothing);
      expect(find.byKey(const Key('push-prompt-later')), findsOneWidget);
    });

    testWidgets('a first setup is never interrupted: asked once it is done', (tester) async {
      device = _Device(PushStanding.askable);
      await app(tester, body: const PushPromptQuiet(child: Text('mise en route')));
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsNothing);
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('accueil')),
      ));
      await _settle(tester);
      expect(PushPrompt.quiet.value, 0);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget);
    });

    testWidgets('allowed but offline: quiet now, looked at again at the next opening',
        (tester) async {
      device = _Device(PushStanding.later);
      await app(tester);
      prompt.phase(signedIn: true);
      prompt.resumed(const Duration(minutes: 5));
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(device.looks, 1, reason: 'not again in the same opening');
      device.answer = PushStanding.askable;
      prompt.resumed(const Duration(hours: 2));
      await _settle(tester);
      expect(device.looks, 2);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget);
    });

    testWidgets('the root navigator not built yet: asked a frame later', (tester) async {
      device = _Device(PushStanding.askable);
      nav = GlobalKey<NavigatorState>();
      var calls = 0;
      prompt = PushPrompt(device: device, context: () => ++calls < 3 ? null : nav.currentContext);
      addTearDown(prompt.dispose);
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('la rue'))));
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(calls, 3);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget);
    });

    testWidgets('no navigator at all: a bounded wait, then asked at the next chance',
        (tester) async {
      device = _Device(PushStanding.askable);
      nav = GlobalKey<NavigatorState>();
      var built = false;
      var calls = 0;
      prompt = PushPrompt(device: device, context: () {
        calls++;
        return built ? nav.currentContext : null;
      });
      addTearDown(prompt.dispose);
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('la rue'))));
      prompt.phase(signedIn: true);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(calls, PushPrompt.frameTries, reason: 'never a wait without end');
      expect(find.byType(AlertDialog), findsNothing);
      built = true;
      prompt.phase(signedIn: true);
      await _settle(tester);
      expect(find.byKey(const Key('push-prompt')), findsOneWidget, reason: 'still pending');
    });

    test('where the device stands: allowed but not written is never « askable »', () {
      PushStanding of(bool on, bool available, PushPermission p) =>
          PushSetup.standingOf(on: on, available: available, permission: p);
      expect(of(true, true, PushPermission.granted), PushStanding.on);
      expect(of(false, true, PushPermission.granted), PushStanding.later,
          reason: 'already granted, ensure() failed (offline): quiet');
      expect(of(false, true, PushPermission.prompt), PushStanding.askable);
      expect(of(false, true, PushPermission.blocked), PushStanding.blocked);
      expect(of(false, true, PushPermission.unsupported), PushStanding.unavailable);
      expect(of(false, false, PushPermission.prompt), PushStanding.unavailable);
    });

    group('Android\'s question, then the word to MainActivity', () {
      const channel = MethodChannel('bf.kaj.app/notify');
      late List<String> log;
      setUp(() {
        log = [];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          log.add(call.method);
          return null;
        });
      });
      tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      test('noted only once the system has answered — a dismissed dialog is never « blocked »',
          () async {
        final answer = Completer<AuthorizationStatus>();
        final asking = PushPlatform.ask(() {
          log.add('request');
          return answer.future;
        });
        await Future<void>.delayed(Duration.zero);
        expect(log, ['request'], reason: 'nothing noted while the question is up');
        answer.complete(AuthorizationStatus.denied);
        expect(await asking, isFalse);
        expect(log, ['request', 'answered']);
      });

      test('allowed: answered, and true', () async {
        expect(await PushPlatform.ask(() async => AuthorizationStatus.authorized), isTrue);
        expect(await PushPlatform.ask(() async => AuthorizationStatus.provisional), isTrue);
        expect(log, ['answered', 'answered']);
      });

      test('a question that never returned an answer notes nothing', () async {
        await expectLater(PushPlatform.ask(() async => throw StateError('activity gone')),
            throwsStateError);
        expect(log, isEmpty);
      });
    });

    test('the device itself: signed out, or a platform with no push, offers nothing', () async {
      final notify = NotificationsRepository(null);
      expect(await PushSetup.standing(notify), PushStanding.unavailable);
      expect(await AppPushDevice(notify).standing(), PushStanding.unavailable);
      expect(await PushClient.permission(), PushPermission.unsupported,
          reason: 'a test host is neither Android nor a browser');
      expect(await PushClient.openSettings(), isFalse);
    });
  });

  group('« Diagnostic de cet appareil »', () {
    testWidgets('a phone built without Firebase says so, step by step', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PushDiagnosticsPanel(
              notify: NotificationsRepository(null),
              look: () async => const PushDiagnosis(
                facts: PushDeviceFacts(platform: 'Android', firebaseReady: false),
                available: false,
                buildHasWorker: true,
                permission: PushPermission.prompt,
                address: null,
                saved: null,
                signedIn: true,
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('push-diagnostics')));
      await _settle(tester);
      expect(find.text('Plateforme : Android'), findsOneWidget);
      expect(find.text('Firebase démarré : non'), findsOneWidget);
      expect(find.text('Cette version a été construite sans google-services.json.'), findsOneWidget);
      expect(find.text('Jeton de l\'appareil obtenu : non'), findsOneWidget);
      expect(find.text('Enregistré sur le serveur : non'), findsOneWidget);
      expect(find.textContaining('Service worker'), findsNothing, reason: 'a browser\'s line only');
      await tester.tap(find.byKey(const Key('push-diagnostics-retry')));
      await _settle(tester);
      expect(find.byKey(const Key('push-diagnostics-said')), findsOneWidget);
      expect(find.textContaining('n\'a pas abouti'), findsOneWidget);
    });

    testWidgets('a browser that is on shows every yes', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PushDiagnosticsPanel(
              notify: NotificationsRepository(null),
              look: () async => const PushDiagnosis(
                facts: PushDeviceFacts(platform: 'Web', workerActive: true),
                available: true,
                buildHasWorker: true,
                permission: PushPermission.granted,
                address: 'https://push.example/abc',
                saved: true,
                signedIn: true,
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('push-diagnostics')));
      await _settle(tester);
      expect(find.text('Service worker actif : oui'), findsOneWidget);
      expect(find.text('Abonnement du navigateur : oui'), findsOneWidget);
      expect(find.text('Enregistré sur le serveur : oui'), findsOneWidget);
      expect(find.text('Autorisation de l\'appareil : autorisées'), findsOneWidget);
      expect(find.byKey(const Key('diag-firebase')), findsNothing);
    });
  });

  group('the end of the setup, in each kind\'s word', () {
    for (final (profile, ready, open) in [
      ('retail', 'Votre boutique est prête', 'Ouvrir ma boutique'),
      ('farm', 'Votre ferme est prête', 'Ouvrir ma ferme'),
      ('association', 'Votre association est prête', 'Ouvrir mon association'),
      ('church', 'Votre association est prête', 'Ouvrir mon association'),
    ]) {
      testWidgets(profile, (tester) async {
        var done = 0;
        await tester.pumpWidget(MaterialApp(
          home: SetupReady(
            org: OrgSummary(id: 'o', name: 'Chez Issa', profile: profile, roles: const ['owner']),
            onDone: () => done++,
          ),
        ));
        expect(find.text('C\'est prêt !'), findsOneWidget);
        expect(find.text(ready), findsOneWidget);
        expect(find.text(open), findsOneWidget);
        if (profile != 'retail') expect(find.textContaining('boutique'), findsNothing);
        await tester.tap(find.byKey(const Key('setup-enter')));
        expect(done, 1);
      });
    }
  });

  group('the command center with the keyboard up', () {
    GoRouter router(Widget page) => GoRouter(initialLocation: Routes.consoleRequestForm, routes: [
          ShellRoute(
            builder: (_, _, child) =>
                CommandCenterShell(center: _Center(), platformAdmin: true, child: child),
            routes: [GoRoute(path: Routes.consoleRequestForm, builder: (_, _) => page)],
          ),
        ]);

    for (final size in const [Size(390, 800), Size(360, 640)]) {
      testWidgets('a page keeps the whole height above the keyboard (${size.width.toInt()})',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp.router(
          routerConfig: router(Scaffold(
            body: ListView(
              key: const Key('kb-page'),
              children: [
                for (var i = 0; i < 8; i++)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(key: Key('kb-field-$i')),
                  ),
              ],
            ),
          )),
        ));
        await _settle(tester);
        await tester.showKeyboard(find.byKey(const Key('kb-field-0')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await _settle(tester);
        // The page's body ends at the keyboard — not 300 px above it (the
        // keyboard taken off twice: a body of nothing, the page white).
        expect(tester.getRect(find.byKey(const Key('kb-page'))).bottom, size.height - 300);
        expect(tester.getRect(find.byKey(const Key('kb-field-0'))).bottom,
            lessThan(size.height - 300));
        expect(find.byKey(const Key('kb-field-0')).hitTestable(), findsOneWidget);
      });

      testWidgets('« Parcours de création » stays drawn while typing (${size.width.toInt()})',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp.router(
          routerConfig: router(RequestFormScreen(onboarding: _Onboarding(), undo: (_) async {})),
        ));
        await _settle(tester);
        await tester.showKeyboard(find.byKey(const Key('form-welcome')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await _settle(tester);
        // The line being typed is above the keyboard, under the bands.
        final typing = tester.getRect(find.descendant(
            of: find.byKey(const Key('form-welcome')), matching: find.byType(EditableText)));
        expect(typing.top, greaterThanOrEqualTo(64));
        expect(typing.top + 30, lessThanOrEqualTo(size.height - 300));
        // And the page goes on below it, down to the keyboard: before 120
        // nothing was drawn under the field.
        final page = tester.getRect(find
            .descendant(of: find.byType(RequestFormScreen), matching: find.byType(Scrollable))
            .first);
        expect(page.bottom, size.height - 300);
        expect(page.height, greaterThan(150));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/nav/router.dart' show Routes;
import 'package:kaj_app/features/account/legal_screens.dart';
import 'package:kaj_app/features/account/support.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 127, « Aide Mara » (126): the support card, its fallback before
/// 126, the footer's « Aide », and Réglages saving a text setting — the
/// owner's help number among them.

/// A Supabase that answers each function as [answer] says: a value, an
/// error status with PostgREST's body, or a dropped connection.
SupabaseClient _client(List<String> asked, Object? Function(String fn, Map<String, dynamic> body) answer,
        {Future<void>? Function(String fn)? wait}) =>
    SupabaseClient(
      'http://db.test',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        final fn = r.url.pathSegments.last;
        final body = r.body.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(r.body) as Map? ?? {});
        asked.add('$fn ${r.body}');
        await wait?.call(fn);
        final a = answer(fn, body);
        if (a is http.ClientException) throw a;
        if (a is _Refusal) {
          return http.Response(jsonEncode({'code': a.code, 'message': a.message, 'details': null, 'hint': null}),
              a.status, request: r, headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response(jsonEncode(a), 200,
            request: r, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

class _Refusal {
  const _Refusal(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
}

const _noFunction = _Refusal(404, 'PGRST202',
    'Could not find the function public.support_contacts without parameters in the schema cache');

/// The platform's settings as 113–126's server keeps them: a string setting
/// takes a string, and each help setting its trigger's check.
class _Server {
  _Server({this.before126 = false});

  /// 113's check of the number (spaces, « + », brackets, dots and dashes
  /// out — nothing else), as the live database had it before 126.
  final bool before126;
  final values = <String, Object?>{
    'support_whatsapp': '',
    'support_email': 'hello@kaj-consulting.com',
    'support_hours': '24 h/24, 7 j/7',
    'platform_wave': '',
  };
  final asked = <String>[];
  final written = <String, Object?>{};

  Object? answer(String fn, Map<String, dynamic> body) {
    if (fn == 'platform_settings_board') {
      return {for (final e in values.entries) e.key: {'value': e.value, 'updated_at': null, 'changed_by': null}};
    }
    if (fn == 'platform_set_setting') {
      final key = body['p_key'] as String;
      final v = body['p_value'];
      if (v is! String) return const _Refusal(400, 'P0001', 'Ce réglage attend un texte.');
      if (key == 'support_whatsapp') {
        final digits = v.replaceAll(RegExp(before126 ? r'[\s+().-]' : r'[^\p{L}\p{N}]', unicode: true), '');
        if (digits.isNotEmpty && !RegExp(r'^[0-9]{8,15}$').hasMatch(digits)) {
          return const _Refusal(400, 'P0001',
              'Le numéro WhatsApp de l\'aide : l\'indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).');
        }
      }
      if (key == 'support_email' &&
          !RegExp(r'''^[^@\s<>"'?&,;]+@[^@\s<>"'?&,;]+\.[^@\s<>"'?&,;.]+$''').hasMatch(v)) {
        return const _Refusal(400, 'P0001', 'L\'e-mail de l\'aide : une adresse comme hello@kaj-consulting.com.');
      }
      values[key] = v;
      written[key] = v;
      return 'act-$key';
    }
    return null;
  }
}

Future<void> _reglages(WidgetTester tester, CommandCenterRepository center, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: SettingsSection(center: center)));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String key) async {
  final row = find.byKey(Key('setting-$key'));
  await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('setting-field')), text);
  await tester.tap(find.byKey(const Key('setting-save')));
  await tester.pumpAndSettle();
}

/// Every link url_launcher was asked to open.
List<String> _launches(WidgetTester tester) {
  final opened = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    final args = call.arguments;
    if (args is Map && args['url'] != null) opened.add('${args['url']}');
    return true;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
  return opened;
}

Widget _host(Widget child, {Locale locale = const Locale('fr')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _withNumber = SupportContacts(
    email: 'hello@kaj-consulting.com', whatsapp: '18623354492', hours: '24 h/24, 7 j/7');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(Support.reset);

  group('Réglages saves a text setting (126) — the owner\'s help number', () {
    // Root cause, reproduced: a number pasted from WhatsApp or the phone's
    // contacts comes wrapped in invisible direction marks (U+202A…U+202C)
    // and may carry non-breaking hyphens (U+2011). The app sent it as it
    // was; 113's check refused it; and the dialog had already closed, so
    // nothing was written, nothing journaled, and only a passing snackbar
    // said why.
    const pasted = '\u202A+1 (862) 335\u20114492\u202C';

    testWidgets('a pasted number reaches even 113\'s server as digits, and saves', (tester) async {
      final server = _Server(before126: true);
      final center = CommandCenterRepository(_client(server.asked, server.answer));
      await _reglages(tester, center);
      await _open(tester, 'support_whatsapp');
      await _type(tester, pasted);
      expect(server.written, {'support_whatsapp': '18623354492'});
      expect(server.asked.where((a) => a.startsWith('platform_set_setting')).single,
          'platform_set_setting {"p_key":"support_whatsapp","p_value":"18623354492"}');
      expect(find.byKey(const Key('setting-field')), findsNothing, reason: 'the dialog closes once saved');
      expect(find.text('18623354492'), findsOneWidget);
      expect(find.text('Numéro WhatsApp de l\'aide Mara (vide : caché) : enregistré.'), findsOneWidget);
    });

    for (final typed in ['+1 862 335 4492', '18623354492', '+1 (862) 335-4492']) {
      testWidgets('« $typed » saves as 18623354492', (tester) async {
        final server = _Server();
        await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)));
        await _open(tester, 'support_whatsapp');
        await _type(tester, typed);
        expect(server.written, {'support_whatsapp': '18623354492'});
        expect(find.text('18623354492'), findsOneWidget);
      });
    }

    testWidgets('emptied: saved empty, the button hidden', (tester) async {
      final server = _Server()..values['support_whatsapp'] = '18623354492';
      await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)));
      await _open(tester, 'support_whatsapp');
      await _type(tester, '   ');
      expect(server.written, {'support_whatsapp': ''});
      expect(find.text('(vide)'), findsOneWidget);
    });

    testWidgets('a wrong number, e-mail or hours: said under the field, nothing sent', (tester) async {
      final server = _Server();
      await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)));
      await _open(tester, 'support_whatsapp');
      for (final bad in ['le support', '7000', '+1 862 335 4492 poste 3']) {
        await _type(tester, bad);
        expect(find.text('Le numéro WhatsApp de l\'aide : l\'indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).'),
            findsOneWidget, reason: bad);
      }
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await _open(tester, 'support_email');
      for (final bad in ['hello', 'hello@kaj', 'a b@c.com']) {
        await _type(tester, bad);
        expect(find.text('L\'e-mail de l\'aide : une adresse comme hello@kaj-consulting.com.'), findsOneWidget, reason: bad);
      }
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await _open(tester, 'support_hours');
      for (final bad in ['', 'x' * 61]) {
        await _type(tester, bad);
        expect(find.text('Les heures de l\'aide : quelques mots, 60 caractères au plus (par exemple 24 h/24, 7 j/7).'),
            findsOneWidget, reason: bad);
      }
      expect(server.asked.where((a) => a.startsWith('platform_set_setting')), isEmpty);
    });

    testWidgets('a refusal from the server: the dialog stays, the typed text kept, the reason under it', (tester) async {
      final asked = <String>[];
      final center = CommandCenterRepository(_client(asked, (fn, body) {
        if (fn == 'platform_settings_board') {
          return {'support_hours': {'value': '24 h/24, 7 j/7', 'updated_at': null, 'changed_by': null}};
        }
        return const _Refusal(400, 'P0001', 'Réservé à la plateforme');
      }));
      await _reglages(tester, center);
      await _open(tester, 'support_hours');
      await _type(tester, 'du lundi au samedi');
      expect(find.byKey(const Key('setting-field')), findsOneWidget, reason: 'still open');
      expect(find.text('Réservé à la plateforme'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('setting-field'))).controller!.text, 'du lundi au samedi');
      expect(tester.widget<FilledButton>(find.byKey(const Key('setting-save'))).onPressed, isNotNull);
    });

    testWidgets('the e-mail, the hours and another text setting save as typed', (tester) async {
      final server = _Server();
      await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)), size: const Size(1280, 2400));
      expect(find.text('Aide aux clients'), findsOneWidget);
      for (final label in ['Numéro WhatsApp de l\'aide Mara (vide : caché)', 'E-mail de l\'aide Mara',
          'Heures de l\'aide Mara (par exemple 24 h/24, 7 j/7)']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await _open(tester, 'support_email');
      await _type(tester, '  aide@marakaj.com ');
      await _open(tester, 'support_hours');
      await _type(tester, 'du lundi au samedi, 8 h – 20 h');
      await _open(tester, 'platform_wave');
      await _type(tester, '+226 70 00 00 00');
      expect(server.written, {
        'support_email': 'aide@marakaj.com',
        'support_hours': 'du lundi au samedi, 8 h – 20 h',
        'platform_wave': '+226 70 00 00 00',
      });
    });

    testWidgets('while the server is asked the dialog cannot be closed — no « Annuler », no barrier, no back',
        (tester) async {
      final answer = Completer<void>();
      final server = _Server();
      final center = CommandCenterRepository(_client(server.asked, server.answer,
          wait: (fn) => fn == 'platform_set_setting' ? answer.future : null));
      await _reglages(tester, center);
      await _open(tester, 'support_hours');
      await tester.enterText(find.byKey(const Key('setting-field')), 'du lundi au samedi');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pump();
      expect(tester.widget<TextButton>(find.byKey(const Key('setting-cancel'))).onPressed, isNull,
          reason: '« Annuler » off while saving');
      expect(tester.widget<FilledButton>(find.byKey(const Key('setting-save'))).onPressed, isNull);
      await tester.tapAt(const Offset(4, 4)); // the barrier
      await tester.pump();
      expect(find.byKey(const Key('setting-field')), findsOneWidget, reason: 'the barrier does not close it');
      await tester.binding.handlePopRoute(); // Android's back
      await tester.pump();
      expect(find.byKey(const Key('setting-field')), findsOneWidget, reason: 'back does not close it');
      final dialogNavigator = Navigator.of(tester.element(find.byKey(const Key('setting-field'))));
      expect(await dialogNavigator.maybePop(), isTrue, reason: 'the pop is handled — by the PopScope');
      await tester.pump();
      expect(find.byKey(const Key('setting-field')), findsOneWidget, reason: 'a back gesture does not close it');
      answer.complete();
      await tester.pumpAndSettle();
      expect(server.written, {'support_hours': 'du lundi au samedi'});
      expect(find.byKey(const Key('setting-field')), findsNothing, reason: 'closed once the server said yes');
    });

    testWidgets('not saving: the barrier leaves it open, « Annuler » closes it', (tester) async {
      final server = _Server();
      await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)));
      await _open(tester, 'support_hours');
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setting-field')), findsOneWidget);
      await tester.tap(find.byKey(const Key('setting-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setting-field')), findsNothing);
      expect(server.written, isEmpty);
    });

    testWidgets('the dialog gone before a refusal comes: the refusal still said, in a snackbar', (tester) async {
      final answer = Completer<void>();
      final asked = <String>[];
      final center = CommandCenterRepository(
          _client(asked, (fn, body) => fn == 'platform_settings_board'
              ? {'support_hours': {'value': '24 h/24, 7 j/7', 'updated_at': null, 'changed_by': null}}
              : const _Refusal(400, 'P0001', 'Réservé à la plateforme'),
              wait: (fn) => fn == 'platform_set_setting' ? answer.future : null));
      await _reglages(tester, center);
      await _open(tester, 'support_hours');
      await tester.enterText(find.byKey(const Key('setting-field')), 'du lundi au samedi');
      await tester.tap(find.byKey(const Key('setting-save')));
      await tester.pump();
      // Somehow gone (a pop no PopScope stops: a route replaced, a sign-out).
      Navigator.of(tester.element(find.byKey(const Key('setting-field')))).pop();
      await tester.pump(const Duration(milliseconds: 500)); // the row still busy: no settling
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('setting-field')), findsNothing);
      answer.complete();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SnackBar, 'Réservé à la plateforme'), findsOneWidget);
    });

    testWidgets('an e-mail with < > " \' ? & , ; or a space: refused in Réglages, nothing sent', (tester) async {
      final server = _Server();
      await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)));
      await _open(tester, 'support_email');
      for (final bad in ['a<b@x.io', 'a>b@x.io', 'a"b@x.io', 'a\'b@x.io', 'a@x.io?cc=y@z.io', 'a&b@x.io',
          'a,b@x.io', 'a;b@x.io', 'a@x;y.io', 'a@x.i<o', 'a\tb@x.io', '${'a' * 116}@x.io']) {
        await _type(tester, bad);
        expect(find.text('L\'e-mail de l\'aide : une adresse comme hello@kaj-consulting.com.'), findsOneWidget,
            reason: bad);
      }
      expect(server.asked.where((a) => a.startsWith('platform_set_setting')), isEmpty);
      // 116 characters « 😀 » (232 UTF-16 units) and « @x.io »: too long.
      await _type(tester, '${'😀' * 116}@x.io');
      expect(find.text('L\'e-mail de l\'aide : une adresse comme hello@kaj-consulting.com.'), findsOneWidget);
      expect(server.asked.where((a) => a.startsWith('platform_set_setting')), isEmpty);
      await _type(tester, '${'😀' * 115}@x.io');
      expect(server.written, {'support_email': '${'😀' * 115}@x.io'}, reason: '120 characters, counted as Postgres');
    });

    testWidgets('two numbers (« / », « ; », « , ») refused, never run together', (tester) async {
      final server = _Server();
      await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)));
      await _open(tester, 'support_whatsapp');
      for (final bad in ['22670000 / 22676000', '22670000;22676000', '22670000, 22676000', '226/70000000',
          '+226 70 00 00 00 ; +226 76 00 00 00']) {
        await _type(tester, bad);
        expect(find.text('Le numéro WhatsApp de l\'aide : l\'indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).'),
            findsOneWidget, reason: bad);
      }
      expect(server.asked.where((a) => a.startsWith('platform_set_setting')), isEmpty);
      expect(supportNumberHasTwo('+1 (862) 335-4492'), isFalse);
    });

    testWidgets('the hours counted by character, as Postgres: 60 emoji taken, 61 refused', (tester) async {
      final server = _Server();
      await _reglages(tester, CommandCenterRepository(_client(server.asked, server.answer)));
      await _open(tester, 'support_hours');
      await _type(tester, '🕘' * 61);
      expect(find.text('Les heures de l\'aide : quelques mots, 60 caractères au plus (par exemple 24 h/24, 7 j/7).'),
          findsOneWidget);
      await _type(tester, '🕘' * 60);
      expect(server.written, {'support_hours': '🕘' * 60});
    });

    test('the help group lists the three; in English', () {
      expect([for (final d in platformSettingDefs) if (d.group == 'help') d.key],
          ['support_whatsapp', 'support_email', 'support_hours']);
      expect(platformSettingDefs.where((d) => d.group == 'help').every((d) => d.type == SettingType.text), isTrue);
      expect(translate('en', 'E-mail de l\'aide Mara'), 'Mara\'s help e-mail');
      expect(translate('en', 'Heures de l\'aide Mara (par exemple 24 h/24, 7 j/7)'),
          'Mara\'s help hours (for example 24 h/24, 7 j/7)');
      expect(supportNumberDigits('\u202A+1 (862) 335\u20114492\u202C'), '18623354492');
      expect(supportNumberDigits('le support'), 'lesupport');
    });
  });

  group('the support card', () {
    testWidgets('with a number: WhatsApp with the greeting, the e-mail, the hours', (tester) async {
      Support.reset(_withNumber);
      final opened = _launches(tester);
      await tester.pumpWidget(_host(const SupportCard()));
      await tester.pumpAndSettle();
      expect(find.text('Aide Mara'), findsOneWidget);
      // The installed hours drawn with non-breaking spaces (stored plain).
      expect(find.text('Une question, un souci ? Nous répondons 24\u00A0h/24, 7\u00A0j/7.'), findsOneWidget);
      expect(find.text('hello@kaj-consulting.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('support-whatsapp')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support-email')));
      await tester.pumpAndSettle();
      expect(opened, [
        'https://wa.me/18623354492?text=${Uri.encodeComponent('Bonjour, j\'ai besoin d\'aide avec Mara.')}',
        'mailto:hello@kaj-consulting.com?subject=Aide%20Mara',
      ]);
    });

    testWidgets('without a number: no WhatsApp anywhere, the e-mail still', (tester) async {
      final opened = _launches(tester);
      await tester.pumpWidget(_host(const SupportCard()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('support-whatsapp')), findsNothing);
      expect(find.text('WhatsApp'), findsNothing);
      expect(find.byKey(const Key('support-email')), findsOneWidget);
      // The old placeholder is gone: nothing opens a chat with no number.
      await Support.openWhatsApp(tester.element(find.byType(SupportCard)));
      expect(opened, isEmpty);
    });

    testWidgets('in English: the installed hours said in English, typed ones as typed', (tester) async {
      Support.reset(_withNumber);
      await tester.pumpWidget(_host(const SupportCard(), locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Mara Help'), findsOneWidget);
      expect(find.text('A question, a problem? We answer 24/7.'), findsOneWidget);
      Support.reset(const SupportContacts(email: 'aide@marakaj.com', hours: 'lun.–sam., 8 h – 20 h'));
      await tester.pumpAndSettle();
      expect(find.text('A question, a problem? We answer lun.–sam., 8 h – 20 h.'), findsOneWidget);
      expect(find.text('aide@marakaj.com'), findsOneWidget);
    });

    testWidgets('the help page (/aide) opens on the card, above the questions', (tester) async {
      Support.reset(_withNumber);
      await tester.pumpWidget(const MaterialApp(home: FaqScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('support-card')), findsOneWidget);
      expect(find.byKey(const Key('support-whatsapp')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('support-card'))).dy,
          lessThan(tester.getTopLeft(find.text('L\'application fonctionne-t-elle sans internet ?')).dy));
      final answer = find.text('Depuis Compte › Aide (ou Mon profil › Aide) : par e-mail, ou sur WhatsApp quand le bouton est affiché.');
      await tester.scrollUntilVisible(answer, 300, scrollable: find.byType(Scrollable).first);
      expect(answer, findsOneWidget);
    });
  });

  group('support_contacts(), asked once — and before 126', () {
    test('126 answers: the three, asked once for the whole app', () async {
      final asked = <String>[];
      final client = _client(asked, (fn, _) => fn == 'support_contacts'
          ? {'email': 'aide@marakaj.com', 'whatsapp': '18623354492', 'hours': '7 j/7'}
          : null);
      await Support.warm(client);
      await Support.warm(client);
      expect(asked.map((a) => a.split(' ').first), ['support_contacts']);
      expect(Support.contacts.value.email, 'aide@marakaj.com');
      expect(Support.contacts.value.whatsapp, '18623354492');
      expect(Support.contacts.value.hours, '7 j/7');
    });

    test('a database before 126: 113\'s number, the e-mail and hours as installed', () async {
      final asked = <String>[];
      await Support.warm(_client(asked, (fn, _) => fn == 'support_contacts' ? _noFunction : '18623354492'));
      expect(asked.map((a) => a.split(' ').first), ['support_contacts', 'support_whatsapp']);
      expect(Support.contacts.value.email, 'hello@kaj-consulting.com');
      expect(Support.contacts.value.hours, '24 h/24, 7 j/7');
      expect(Support.contacts.value.whatsapp, '18623354492');
    });

    test('before 126 with no number (or signed out): no WhatsApp, no placeholder', () async {
      await Support.warm(_client([], (fn, _) => fn == 'support_contacts' ? _noFunction : null));
      expect(Support.contacts.value.whatsapp, isNull);
      Support.reset();
      await Support.warm(_client([], (fn, _) => fn == 'support_contacts'
          ? _noFunction
          : const _Refusal(401, '42501', 'permission denied for function support_whatsapp')));
      expect(Support.contacts.value.whatsapp, isNull);
      expect(Support.contacts.value.email, 'hello@kaj-consulting.com');
    });

    test('no network: the defaults now, asked again the next time', () async {
      var offline = true;
      final asked = <String>[];
      final client = _client(asked, (fn, _) => offline
          ? http.ClientException('Connection refused')
          : {'email': 'hello@kaj-consulting.com', 'whatsapp': '18623354492', 'hours': '24 h/24, 7 j/7'});
      await Support.warm(client);
      expect(Support.contacts.value.whatsapp, isNull);
      offline = false;
      await Support.warm(client);
      expect(Support.contacts.value.whatsapp, '18623354492');
      expect(asked.length, 2);
    });

    test('an address is checked as 126 checks it; the hours counted by character', () {
      for (final bad in ['a<b@x.io', 'a"b@x.io', 'a\'b@x.io', 'a b@x.io', 'a@x.io?cc=y@z.io', 'a&b@x.io',
          'a,b@x.io', 'a;b@x.io', 'a@x>y.io', '${'a' * 116}@x.io', 'hello@kaj', 'a@b@c.io']) {
        expect(Support.isEmail(bad), isFalse, reason: bad);
        expect(SupportContacts.fromJson({'email': bad}).email, 'hello@kaj-consulting.com', reason: bad);
      }
      for (final good in ['hello@kaj-consulting.com', 'aide+mara@marakaj.com', '${'é' * 115}@x.io', '${'😀' * 115}@x.io']) {
        expect(Support.isEmail(good), isTrue, reason: good);
      }
      expect(SupportContacts.fromJson({'hours': '🕘' * 60}).hours, '🕘' * 60);
      expect(SupportContacts.fromJson({'hours': '🕘' * 61}).hours, '24 h/24, 7 j/7');
    });

    test('a wrong answer is never drawn', () {
      final c = SupportContacts.fromJson({'email': 'pas une adresse', 'whatsapp': '+226 70', 'hours': 'x' * 61});
      expect(c.email, 'hello@kaj-consulting.com');
      expect(c.whatsapp, isNull);
      expect(c.hours, '24 h/24, 7 j/7');
      expect(SupportContacts.fromJson(null).email, 'hello@kaj-consulting.com');
    });
  });

  group('the footer\'s « Aide »', () {
    testWidgets('inside the app: the help page', (tester) async {
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: SingleChildScrollView(child: ShopFooter()))),
        GoRoute(path: Routes.faq, builder: (_, _) => const FaqScreen()),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Aide'), findsOneWidget);
      expect(find.byKey(const Key('powered-by')), findsOneWidget, reason: 'the footer keeps what it had');
      await tester.tap(find.byKey(const Key('footer-help')));
      await tester.pumpAndSettle();
      expect(find.byType(FaqScreen), findsOneWidget);
      expect(find.byKey(const Key('support-card')), findsOneWidget);
    });

    testWidgets('a target a finger can hit: 48 wide, 24 high at least; the band still small', (tester) async {
      for (final width in [320.0, 390.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(_host(const ShopFooter()));
        await tester.pumpAndSettle();
        final target = tester.getSize(find.byKey(const Key('footer-help')));
        expect(target.width, greaterThanOrEqualTo(48), reason: '$width');
        expect(target.height, greaterThanOrEqualTo(24), reason: '$width');
      }
      tester.view.reset();
    });

    testWidgets('with no router: the site\'s /aide', (tester) async {
      final opened = _launches(tester);
      await tester.pumpWidget(_host(const ShopFooter()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('footer-help')));
      await tester.pumpAndSettle();
      expect(opened, ['https://marakaj.com/aide']);
    });

    test('Routes.faq is the site\'s /aide', () => expect(Routes.faq, '/aide'));
  });
}

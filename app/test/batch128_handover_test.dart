import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kaj_app/core/courier/courier_repository.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/courier/courier_screen.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The delivery code's lockout (127): five wrong codes lock the order for
/// 15 minutes and the shop is told. The server answers a wrong code
/// instead of raising (a raise would undo the count); « Mes courses » says
/// how many tries are left, or that the order is locked.

SupabaseClient _client(List<String> asked, Object? Function(String fn) answer) => SupabaseClient(
      'http://db.test',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        final fn = r.url.pathSegments.last;
        asked.add('$fn ${r.body}');
        final a = answer(fn);
        const json = {'content-type': 'application/json; charset=utf-8'};
        if (a is int) {
          return http.Response(
              jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function', 'details': null, 'hint': null}),
              a,
              request: r,
              headers: json);
        }
        return http.Response(jsonEncode(a), 200, request: r, headers: json);
      }),
    );

class _Courier extends CourierRepository {
  _Courier(this.refusals) : super(null);

  final List<HandoverRefused?> refusals;
  final tried = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<String?> status() async => 'approved';

  @override
  Future<List<DeliveryJob>> available() async => const [];

  @override
  Future<List<DeliveryJob>> mine() async => [
        DeliveryJob(
          orderId: 'o1',
          shopName: 'Boutique Awa',
          total: 5000,
          currency: 'XOF',
          createdAt: DateTime(2026, 10, 5, 9),
          customerName: 'Fati',
          status: 'in_transit',
        ),
      ];

  @override
  Future<List<CourierEarnings>> earnings() async => const [];

  @override
  Future<List<CashHeld>> cash() async => const [];

  @override
  Future<void> deliver(String orderId, String code) async {
    tried.add('$orderId:$code');
    final refused = refusals.isEmpty ? null : refusals.removeAt(0);
    if (refused != null) throw refused;
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
  });

  group('the repository reads the door\'s answer', () {
    test('a wrong code is a HandoverRefused with the tries left; the right one passes', () async {
      final asked = <String>[];
      var answers = <Object?>[
        {'ok': false, 'reason': 'wrong_code', 'left': 3, 'message': 'Code incorrect'},
        {'ok': false, 'reason': 'locked', 'minutes': 15, 'fresh': true, 'message': 'Trop de codes faux'},
        {'ok': true},
      ];
      final repo = CourierRepository(_client(asked, (_) => answers.removeAt(0)));
      await expectLater(
          repo.deliver('o1', ' 1234 '),
          throwsA(isA<HandoverRefused>()
              .having((e) => e.locked, 'locked', false)
              .having((e) => e.left, 'left', 3)));
      await expectLater(
          repo.deliver('o1', '1234'),
          throwsA(isA<HandoverRefused>()
              .having((e) => e.locked, 'locked', true)
              .having((e) => e.minutes, 'minutes', 15)));
      await repo.deliver('o1', '4821');
      expect(asked, [
        'courier_handover {"p_order_id":"o1","p_code":"1234"}',
        'courier_handover {"p_order_id":"o1","p_code":"1234"}',
        'courier_handover {"p_order_id":"o1","p_code":"4821"}',
      ]);
      answers = [];
    });

    test('a database before 127: the old door', () async {
      final asked = <String>[];
      final repo = CourierRepository(_client(asked, (fn) => fn == 'courier_handover' ? 404 : null));
      await repo.deliver('o1', '4821');
      expect(asked, [
        'courier_handover {"p_order_id":"o1","p_code":"4821"}',
        'courier_deliver {"p_order_id":"o1","p_code":"4821"}',
      ]);
    });
  });

  Future<void> open(WidgetTester tester, _Courier courier, {Locale? locale}) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: locale == null ? null : Strings.localizationsDelegates,
      supportedLocales: locale == null ? const [Locale('en', 'US')] : Strings.supportedLocales,
      home: CourierScreen(courier: courier),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.textContaining(locale == null ? 'Mes courses' : 'My trips').first);
    await tester.pumpAndSettle();
  }

  Future<void> tryCode(WidgetTester tester, String code, {bool en = false}) async {
    await tester.tap(find.text(en ? 'Delivered' : 'Livré').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), code);
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
  }

  testWidgets('« Mes courses »: the tries left, then the lock, then the delivery', (tester) async {
    final courier = _Courier([
      const HandoverRefused(locked: false, left: 4),
      const HandoverRefused(locked: false, left: 1),
      const HandoverRefused(locked: true, minutes: 15),
      null,
    ]);
    await open(tester, courier);

    await tryCode(tester, '1111');
    expect(find.text('Code incorrect : demandez au client les 4 chiffres de sa commande (4 essais avant blocage).'),
        findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CourierScreen))).clearSnackBars();
    await tester.pumpAndSettle();

    await tryCode(tester, '2222');
    expect(find.text('Code incorrect : demandez au client les 4 chiffres de sa commande (1 essai avant blocage).'),
        findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CourierScreen))).clearSnackBars();
    await tester.pumpAndSettle();

    await tryCode(tester, '3333');
    expect(find.text('Trop de codes faux : cette livraison est bloquée 15 min. La boutique est prévenue.'),
        findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CourierScreen))).clearSnackBars();
    await tester.pumpAndSettle();

    await tryCode(tester, '4821');
    expect(courier.tried, ['o1:1111', 'o1:2222', 'o1:3333', 'o1:4821']);
    expect(find.textContaining('Code incorrect'), findsNothing);
    expect(find.textContaining('Trop de codes'), findsNothing);
  });

  testWidgets('in English, the tries left and the lock; the shop\'s bell', (tester) async {
    final courier = _Courier([
      const HandoverRefused(locked: false, left: 2),
      const HandoverRefused(locked: true, minutes: 9),
    ]);
    await open(tester, courier, locale: const Locale('en'));
    await tryCode(tester, '1111', en: true);
    expect(find.text('Wrong code: ask the customer for the 4 digits of their order (2 tries before it locks).'),
        findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CourierScreen))).clearSnackBars();
    await tester.pumpAndSettle();
    await tryCode(tester, '2222', en: true);
    expect(find.text('Too many wrong codes: this delivery is locked for 9 min. The shop has been told.'),
        findsOneWidget);

    String? line;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Builder(builder: (context) {
        line = notificationLine(
            context,
            NotificationRow.fromRow({
              'id': 'n1',
              'kind': 'delivery_code_locked',
              'message': 'Livraison de Fati : 5 codes faux, bloquée 15 min. Appelez le livreur ou le client.',
              'params': {'to': 'shop', 'order_id': 'o1', 'name': 'Fati', 'minutes': 15},
              'created_at': '2026-10-11T10:00:00Z',
            }));
        return const SizedBox();
      }),
    ));
    expect(line, 'Delivery for Fati: 5 wrong codes, locked for 15 min. Call the courier or the customer.');
  });
}

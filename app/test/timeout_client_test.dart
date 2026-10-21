import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/net/timeout_client.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/credit/credit_flows.dart';
import 'package:kaj_app/features/invoicing/invoice_flow.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One time limit for every call to Supabase (batch 149): a request that
/// goes out on a stalled line and never gets an answer ends, and the person
/// reads « Pas de connexion » instead of watching a spinner forever.

/// A line that takes the request and never answers.
http.Client _stalled({bool Function(http.BaseRequest r)? answers, List<http.BaseRequest>? seen}) =>
    MockClient.streaming((request, body) async {
      seen?.add(request);
      if (answers != null && answers(request)) {
        return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
            request: request, headers: {'content-type': 'application/json'});
      }
      return Completer<http.StreamedResponse>().future;
    });

const _offline = 'Pas de connexion. Réessayez quand le réseau revient.';

OrgSummary _org(String profile) => OrgSummary(
      id: 'o-$profile',
      name: 'Chez $profile',
      slug: 'chez-$profile',
      profile: profile,
      currency: 'XOF',
      roles: const ['owner'],
      visibility: 'full',
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('the wrapper', () {
    test('a request nobody answers fails after the bound', () async {
      final client = TimeoutClient(_stalled(), timeout: const Duration(milliseconds: 50));
      final watch = Stopwatch()..start();
      // A read says it as a LineDown (not asked again), its cause the bound.
      await expectLater(client.get(Uri.parse('https://x.test/rest/v1/sales')),
          throwsA(isA<LineDown>().having((e) => e.cause, 'cause', isA<RequestTimedOut>())));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('the stalled request itself is let go (its abort trigger fires)', () async {
      final seen = <http.BaseRequest>[];
      final client =
          TimeoutClient(_stalled(seen: seen), timeout: const Duration(milliseconds: 30));
      await expectLater(
          client.post(Uri.parse('https://x.test/rest/v1/rpc/repay_customer'),
              headers: {'Content-Type': 'application/json'}, body: '{"a":1}'),
          throwsA(isA<RequestTimedOut>()));
      final sent = seen.single;
      expect(sent, isA<http.Abortable>());
      expect((sent as http.Request).body, '{"a":1}', reason: 'the body is sent as it was');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      var aborted = false;
      await (sent as http.Abortable).abortTrigger!.then((_) => aborted = true);
      expect(aborted, isTrue);
    });

    test('an answer that starts and then goes silent fails too', () async {
      final inner = MockClient.streaming((request, _) async {
        final body = StreamController<List<int>>();
        body.add(utf8.encode('[{"id":'));
        return http.StreamedResponse(body.stream, 200, request: request);
      });
      final client = TimeoutClient(inner, timeout: const Duration(milliseconds: 50));
      await expectLater(client.get(Uri.parse('https://x.test/rest/v1/sales')),
          throwsA(isA<LineDown>().having((e) => e.cause, 'cause', isA<RequestTimedOut>())));
    });

    test('a slow answer still arriving is never cut', () async {
      final inner = MockClient.streaming((request, _) async {
        Stream<List<int>> slow() async* {
          for (var i = 0; i < 6; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            yield utf8.encode('$i');
          }
        }

        return http.StreamedResponse(slow(), 200, request: request);
      });
      // Each piece comes within the bound, the whole takes three times it.
      final client = TimeoutClient(inner, timeout: const Duration(milliseconds: 60));
      final response = await client.get(Uri.parse('https://x.test/rest/v1/sales'));
      expect(response.body, '012345');
    });

    test('an answer in time is passed through untouched', () async {
      final client = TimeoutClient(MockClient((r) async => http.Response('{"ok":true}', 201,
          headers: {'x-a': 'b'}, request: r)));
      final response = await client.post(Uri.parse('https://x.test/rest/v1/rpc/f'), body: '{}');
      expect(response.statusCode, 201);
      expect(response.body, '{"ok":true}');
      expect(response.headers['x-a'], 'b');
    });

    test('a large body (an upload) and a retried read get their own bounds', () {
      final client = TimeoutClient(http.Client());
      final small = http.Request('POST', Uri.parse('https://x.test/rpc/f'))..body = '{}';
      final big = http.Request('POST', Uri.parse('https://x.test/storage/v1/object/a'))
        ..bodyBytes = List<int>.filled(TimeoutClient.largeBody + 1, 0);
      final multipart = http.MultipartRequest('POST', Uri.parse('https://x.test/up'));
      final retried = http.Request('GET', Uri.parse('https://x.test/rest/v1/sales'))
        ..headers['X-Retry-Count'] = '1';
      expect(client.boundFor(small), TimeoutClient.defaultTimeout);
      expect(client.boundFor(big), TimeoutClient.defaultUploadTimeout);
      expect(client.boundFor(multipart), TimeoutClient.defaultUploadTimeout);
      expect(client.boundFor(retried), TimeoutClient.defaultRetryTimeout);
      expect(TimeoutClient.defaultTimeout, const Duration(seconds: 30));
    });

    test('it reads as « Pas de connexion », directly and through auth', () {
      final error = RequestTimedOut(Uri.parse('https://x.test'), const Duration(seconds: 30));
      expect(describeError(error), _offline);
      expect(isOffline(error), isTrue, reason: 'the till keeps the sale in its outbox');
      // gotrue wraps a transport failure in AuthRetryableFetchException(message: '$error').
      expect(describeError(AuthRetryableFetchException(message: error.toString())), _offline);
    });

    test('through a real Supabase client: an RPC fails, it does not hang', () async {
      final supabase = SupabaseClient('https://example.supabase.co', 'anon-key',
          httpClient: TimeoutClient(_stalled(), timeout: const Duration(milliseconds: 50)));
      addTearDown(supabase.dispose);
      Object? caught;
      try {
        await supabase.rpc('file_document', params: {'p_document_id': 'd1'});
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<RequestTimedOut>());
      expect(describeError(caught!), _offline);
    });
  });

  group('real flows on a stalled line', () {
    Future<void> pump(WidgetTester tester, Widget flow) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: flow,
      ));
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('flow-next')));
      await tester.pumpAndSettle();
    }

    /// Made outside the fake clock (its auth refresh timer is real); the
    /// wrapper's own timer is armed by the tap, on the test's clock.
    Future<SupabaseClient> client(WidgetTester tester, http.Client inner) async {
      final c = (await tester.runAsync(() async => SupabaseClient(
          'https://example.supabase.co', 'anon-key',
          httpClient: TimeoutClient(inner, timeout: const Duration(seconds: 30)))))!;
      addTearDown(() => tester.runAsync(c.dispose));
      return c;
    }

    for (final profile in ['retail', 'farm', 'association']) {
      testWidgets('a $profile\'s credit repayment ends with « Pas de connexion »',
          (tester) async {
        final supabase = await client(tester, _stalled());
        await pump(
            tester,
            RepayFlow(
              org: _org(profile),
              credit: CreditRepository(supabase),
              debtors: const [DebtorRow(customerId: 'c-awa', name: 'Awa', totalOwed: 2500)],
              customerId: 'c-awa',
              store: MemoryFlowStore(),
            ));
        await next(tester);
        await tester.tap(find.byKey(const Key('repay-all')));
        await tester.pump();
        await next(tester);
        await tester.tap(find.byKey(const Key('flow-save')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 29));
        expect(find.text(_offline), findsNothing, reason: 'still waiting, within the bound');
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text(_offline), findsOneWidget);
        expect(find.byKey(const Key('flow-done')), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing,
            reason: 'nothing left spinning');
      });
    }

    testWidgets('an invoice whose create_invoice is never answered says « Pas de connexion »',
        (tester) async {
      final supabase = await client(tester,
          _stalled(answers: (r) => !r.url.path.endsWith('/create_invoice')));
      await pump(
          tester,
          InvoiceFlow(
            org: _org('retail'),
            invoicing: InvoicingRepository(supabase),
            store: MemoryFlowStore(),
          ));
      await tester.enterText(find.byKey(const Key('customer-name')), 'Hôtel Indépendance');
      await tester.pump();
      await next(tester);
      await next(tester); // contact
      await tester.enterText(find.byKey(const Key('invoice-typed-name')), 'Plateaux d\'œufs');
      await tester.enterText(find.byKey(const Key('invoice-typed-price')), '2500');
      await tester.pump();
      await tester.tap(find.byKey(const Key('invoice-typed-add')));
      await tester.pumpAndSettle();
      await next(tester);
      await tester.enterText(find.byKey(const Key('invoice-qty-0')), '4');
      await tester.pump();
      await next(tester);
      await tester.tap(find.byKey(const Key('flow-option-days:15')));
      await tester.pump();
      await next(tester);
      await next(tester); // note
      expect(find.byKey(const Key('flow-summary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('flow-save')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text(_offline), findsOneWidget);
      expect(find.byKey(const Key('flow-done')), findsNothing);
    });
  });
}

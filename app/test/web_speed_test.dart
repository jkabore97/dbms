// ignore_for_file: implementation_imports
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_localizations/src/l10n/generated_date_localizations.dart'
    as flutter_dates;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:kaj_app/core/format/money.dart' as money;
import 'package:kaj_app/core/l10n/fr_en_date_data.dart';
import 'package:kaj_app/core/l10n/fr_en_localizations.dart';
import 'package:kaj_app/core/net/same_origin_rest.dart';
import 'package:kaj_app/core/net/timeout_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Web first load: PostgREST through the site's own address, and only the
/// French and English locale data in the build.

const _project = 'https://abcdefghijklmnop.supabase.co';
final _page = Uri.parse('https://marakaj.com/s/tony-pizza?x=1');

void main() {
  group('which address the web build sends PostgREST to', () {
    test('a path on the site, resolved against the page it was opened on', () {
      expect(
          restProxyBase(supabaseUrl: _project, proxy: '/sb', isWeb: true, pageUrl: _page),
          'https://marakaj.com/sb');
      expect(
          restProxyBase(
              supabaseUrl: _project,
              proxy: '/sb/',
              isWeb: true,
              pageUrl: Uri.parse('https://www.marakaj.com/')),
          'https://www.marakaj.com/sb');
    });

    test('a full address is taken as it is', () {
      expect(
          restProxyBase(
              supabaseUrl: _project, proxy: 'https://marakaj.com/sb/', isWeb: true, pageUrl: _page),
          'https://marakaj.com/sb');
    });

    test('unset, or not the web, or nonsense: direct, as before', () {
      for (final proxy in ['', '   ']) {
        expect(restProxyBase(supabaseUrl: _project, proxy: proxy, isWeb: true, pageUrl: _page),
            isNull);
      }
      // Android and iOS never use it, whatever the build says.
      expect(restProxyBase(supabaseUrl: _project, proxy: '/sb', isWeb: false, pageUrl: _page),
          isNull);
      expect(restProxyBase(supabaseUrl: '', proxy: '/sb', isWeb: true, pageUrl: _page), isNull);
      expect(
          restProxyBase(supabaseUrl: _project, proxy: 'ftp://x/sb', isWeb: true, pageUrl: _page),
          isNull);
      expect(
          restProxyBase(
              supabaseUrl: _project, proxy: '/sb', isWeb: true, pageUrl: Uri.parse('file:///x')),
          isNull);
    });
  });

  group('SameOriginRestClient', () {
    late List<http.BaseRequest> seen;
    late SameOriginRestClient client;
    setUp(() {
      seen = [];
      client = SameOriginRestClient(
        _Recorder(seen),
        supabaseUrl: _project,
        proxyBase: 'https://marakaj.com/sb',
      );
    });

    test('PostgREST goes to the site, path, query, headers and body unchanged', () async {
      await client.post(
        Uri.parse('$_project/rest/v1/rpc/storefront?select=*'),
        headers: {
          'apikey': 'k',
          'Authorization': 'Bearer t',
          'Prefer': 'count=exact',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'p_slug': 'tony-pizza'}),
      );
      final r = seen.single as http.Request;
      expect(r, isNot(isA<http.Abortable>()));
      expect(r.url.toString(), 'https://marakaj.com/sb/rest/v1/rpc/storefront?select=*');
      expect(r.method, 'POST');
      expect(r.headers['apikey'], 'k');
      expect(r.headers['Authorization'], 'Bearer t');
      expect(r.headers['Prefer'], 'count=exact');
      expect(r.body, '{"p_slug":"tony-pizza"}');
    });

    test('auth, storage, functions, realtime and other hosts stay direct', () async {
      for (final url in [
        '$_project/auth/v1/token?grant_type=refresh_token',
        '$_project/auth/v1/settings',
        '$_project/storage/v1/object/x',
        '$_project/functions/v1/f',
        '$_project/realtime/v1/api/broadcast',
        '$_project/rest/v10/x',
        'https://abcdefghijklmnop.supabase.co.evil.example/rest/v1/x',
        'https://kaj-uploads.example/v1/objects/x',
      ]) {
        seen.clear();
        await client.get(Uri.parse(url));
        expect(seen.single.url.toString(), url, reason: url);
      }
    });

    test('the abort trigger the timeout armed still applies to the copy', () async {
      final request = http.AbortableRequest('GET', Uri.parse('$_project/rest/v1/items'),
          abortTrigger: Future<void>.delayed(const Duration(days: 1)));
      await client.send(request);
      expect(seen.single, isA<http.Abortable>());
      expect(seen.single.url.host, 'marakaj.com');
    });

    test('through Supabase itself: reads go to /sb, sign-in stays on the project', () async {
      final calls = <Uri>[];
      final inner = MockClient((request) async {
        calls.add(request.url);
        if (request.url.path.endsWith('/token')) {
          return http.Response('{"error":"invalid_grant"}', 400,
              headers: {'content-type': 'application/json'}, request: request);
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'}, request: request);
      });
      final supabase = SupabaseClient(
        _project,
        'sb_publishable_test',
        httpClient: SameOriginRestClient(TimeoutClient(inner),
            supabaseUrl: _project, proxyBase: 'https://marakaj.com/sb'),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await supabase.rpc('storefront_directory');
      await supabase.from('orgs').select('id').limit(1);
      try {
        await supabase.auth.signInWithPassword(email: 'a@b.c', password: 'x');
      } catch (_) {}
      expect(calls.map((u) => u.toString()), [
        'https://marakaj.com/sb/rest/v1/rpc/storefront_directory',
        'https://marakaj.com/sb/rest/v1/orgs?select=id&limit=1',
        '$_project/auth/v1/token?grant_type=password',
      ]);
      // The realtime websocket keeps the project's own address.
      expect(supabase.realtime.endPoint, startsWith('wss://abcdefghijklmnop.supabase.co/realtime/v1'));
      await supabase.dispose();
    });
  });

  group('French and English only, the same as Flutter gave them', () {
    test('the date data is Flutter\'s own for fr and en', () {
      for (final locale in ['fr', 'en']) {
        expect(frEnDateSymbols[locale]!.toString(),
            flutter_dates.dateSymbols[locale]!.toString(),
            reason: locale);
        expect(frEnDatePatterns[locale], flutter_dates.datePatterns[locale], reason: locale);
      }
      expect(frEnDateSymbols.keys, unorderedEquals(['fr', 'en']));
    });

    testWidgets('Material, Cupertino and widgets strings match the global delegates',
        (tester) async {
      for (final locale in const [Locale('fr'), Locale('en')]) {
        final mine = await const FrEnMaterialLocalizations().load(locale);
        final theirs = await GlobalMaterialLocalizations.delegate.load(locale);
        final day = DateTime(2026, 3, 7);
        expect(mine.okButtonLabel, theirs.okButtonLabel);
        expect(mine.cancelButtonLabel, theirs.cancelButtonLabel);
        expect(mine.formatFullDate(day), theirs.formatFullDate(day));
        expect(mine.formatMediumDate(day), theirs.formatMediumDate(day));
        expect(mine.formatCompactDate(day), theirs.formatCompactDate(day));
        expect(mine.formatMonthYear(day), theirs.formatMonthYear(day));
        expect(mine.formatDecimal(1234567), theirs.formatDecimal(1234567));
        expect(mine.firstDayOfWeekIndex, theirs.firstDayOfWeekIndex);
        expect(mine.narrowWeekdays, theirs.narrowWeekdays);
        expect(mine.timeOfDayFormat(), theirs.timeOfDayFormat());
        expect(mine.dateHelpText, theirs.dateHelpText);
        final c1 = await const FrEnCupertinoLocalizations().load(locale);
        final c2 = await GlobalCupertinoLocalizations.delegate.load(locale);
        expect(c1.datePickerMediumDate(day), c2.datePickerMediumDate(day));
        expect(c1.cutButtonLabel, c2.cutButtonLabel);
        final w1 = await const FrEnWidgetsLocalizations().load(locale);
        final w2 = await GlobalWidgetsLocalizations.delegate.load(locale);
        expect(w1.textDirection, w2.textDirection);
        expect(w1.copyButtonLabel, w2.copyButtonLabel);
      }
      expect(const FrEnMaterialLocalizations().isSupported(const Locale('de')), isFalse);
    });

    test('dates, numbers and money read as they did', () {
      initializeFrEnDateFormatting();
      final day = DateTime(2026, 3, 7, 14, 5);
      expect(DateFormat('EEE d MMM, HH:mm', 'fr_FR').format(day), 'sam. 7 mars, 14:05');
      expect(DateFormat('d MMMM y', 'fr').format(day), '7 mars 2026');
      expect(DateFormat.yMMMMd('en').format(day), 'March 7, 2026');
      expect(DateFormat('d MMM', 'en_US').format(day), '7 Mar');
      expect(DateFormat('dd/MM/yyyy').format(day), '07/03/2026');
      expect(NumberFormat.decimalPattern('fr_FR').format(1234567), '1 234 567');
      expect(NumberFormat.decimalPattern('en').format(1234567), '1,234,567');
      expect(NumberFormat.simpleCurrency(locale: 'fr_FR', name: 'EUR').format(12.5),
          '12,50 €');
      expect(NumberFormat.simpleCurrency(locale: 'en', name: 'USD').format(12.5), r'$12.50');
      expect(Intl.plural(2, one: 'un', other: 'plusieurs', locale: 'fr'), 'plusieurs');
      expect(Intl.plural(1, one: 'one', other: 'many', locale: 'en'), 'one');
      expect(money.moneyFormat('XOF').format(1200000), '1\u202f200\u202f000\u00a0FCFA');
      expect(money.moneyFormat('XAF').format(450), '450\u00a0FCFA');
      expect(money.moneyFormat('EUR').format(12.5), '12,50\u00a0EUR');
      expect(money.moneyFormat('USD').format(12.5), '12,50\u00a0USD');
    });
  });
}

/// Keeps the very request it is given (MockClient copies it).
class _Recorder extends http.BaseClient {
  _Recorder(this.seen);
  final List<http.BaseRequest> seen;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    seen.add(request);
    await request.finalize().toBytes();
    return http.StreamedResponse(Stream.value(utf8.encode('[]')), 200,
        request: request, headers: {'content-type': 'application/json'});
  }
}

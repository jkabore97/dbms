import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/accounting/accounting_repository.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/auth/pin_codec.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/errors.dart';
import 'package:kaj_app/core/export/report_export.dart';
import 'package:kaj_app/core/farm/farm_repository.dart';
import 'package:kaj_app/core/invoicing/invoicing_repository.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/net/timeout_client.dart';
import 'package:kaj_app/core/onboarding/onboarding_repository.dart';
import 'package:kaj_app/core/reports/reports_repository.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/retail/staff.dart';
import 'package:kaj_app/core/site/app_download.dart';
import 'package:kaj_app/core/sync/sync_service.dart';
import 'package:kaj_app/features/auth/join_or_apply_screen.dart';
import 'package:kaj_app/features/auth/pin_screen.dart';
import 'package:kaj_app/features/retail/product_photo.dart';
import 'package:kaj_app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The owner's report: « the app freezes — sometimes a few buttons,
/// sometimes the whole app; also offline on the Android app; and the
/// website is very slow. » Each group is one cause found and its fix.

/// A line with no signal at all: every request fails at once, as Android's
/// airplane mode and a browser offline do.
http.Client _offline(List<http.BaseRequest> seen) => MockClient((r) async {
      seen.add(r);
      throw const SocketException('Failed host lookup');
    });

/// Supabase as main.dart builds it: everything through the one time limit.
SupabaseClient _app(http.Client inner, {Duration timeout = TimeoutClient.defaultTimeout}) =>
    SupabaseClient('https://example.supabase.co', 'anon-key',
        httpClient: TimeoutClient(inner, timeout: timeout));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  group('offline, a read says so at once (it took 7 s in 4 tries)', () {
    test('main.dart gives Supabase the bounded client', () {
      final main = File('lib/main.dart').readAsStringSync();
      // On the web, around it, the same-origin PostgREST client
      // (core/net/same_origin_rest.dart) — the bound still applies.
      expect(main, contains('httpClient: _supabaseHttp(TimeoutClient(http.Client()))'));
    });

    test('a stalled read ends after one bound, not four (it was more than a minute)', () async {
      final seen = <http.BaseRequest>[];
      final s = _app(
          MockClient.streaming((r, _) {
            seen.add(r);
            return Completer<http.StreamedResponse>().future;
          }),
          timeout: const Duration(milliseconds: 100));
      addTearDown(s.dispose);
      final w = Stopwatch()..start();
      Object? caught;
      try {
        await s.from('products').select('id');
      } catch (e) {
        caught = e;
      }
      expect(w.elapsed, lessThan(const Duration(milliseconds: 900)),
          reason: 'PostgREST waited 1 + 2 + 4 s and asked three times more');
      expect(seen, hasLength(1));
      expect(caught, isA<LineDown>().having((e) => e.cause, 'cause', isA<RequestTimedOut>()));
      expect(describeError(caught!), 'Pas de connexion. Réessayez quand le réseau revient.');
    });

    test('a « busy » answer is still an answer: PostgREST may ask again', () async {
      final r = await TimeoutClient(MockClient((r) async => http.Response('busy', 503)))
          .get(Uri.parse('https://x.test/rest/v1/products'));
      expect(r.statusCode, 503);
    });

    Future<Duration> timed(Future<void> Function() read) async {
      final w = Stopwatch()..start();
      Object? caught;
      try {
        await read();
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull, reason: 'offline must fail, not answer');
      expect(isOffline(caught!), isTrue, reason: 'read as the network: the cached copy follows');
      return w.elapsed;
    }

    test('a shop\'s catalogue, a farm\'s day, an association\'s members', () async {
      final seen = <http.BaseRequest>[];
      final s = _app(_offline(seen));
      addTearDown(s.dispose);
      final reads = <String, Future<void> Function()>{
        'shop': () => RetailRepository(s).products('o-shop'),
        'farm': () => FarmRepository(s).flocksWrittenToday(['f1']),
        'association': () => ReportsRepository(s).members('o-asso'),
      };
      for (final MapEntry(key: kind, value: read) in reads.entries) {
        seen.clear();
        final took = await timed(read);
        expect(took, lessThan(const Duration(milliseconds: 500)), reason: kind);
        expect(seen.every((r) => !r.headers.containsKey('X-Retry-Count')), isTrue,
            reason: '$kind: a dead line is not asked again');
      }
    });

    test('the till still sells from the phone\'s catalogue, without the wait', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      await db.cacheProducts('o-shop', [
        {'id': 'p1', 'name': 'Savon', 'sale_price': 450, 'quantity_on_hand': 3},
      ], askedAt: DateTime.now());
      final s = _app(_offline([]));
      addTearDown(s.dispose);
      final w = Stopwatch()..start();
      final shelf = await RetailRepository(s, outbox: db).tillProducts('o-shop');
      expect(w.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(shelf.fromDevice, isTrue);
      expect(shelf.products.single.name, 'Savon');
    });
  });

  group('what the line says, by kind of request', () {
    test('a read: LineDown, reading as its cause', () async {
      final e = await TimeoutClient(_offline([])).get(Uri.parse('https://x.test/a')).then<Object?>(
          (_) => null,
          onError: (Object e) => e);
      expect(e, isA<LineDown>().having((e) => e.cause, 'cause', isA<SocketException>()));
      expect(isOffline(e!), isTrue);
    });

    test('a write (an RPC, an upload): the error as it was', () async {
      await expectLater(
          TimeoutClient(_offline([])).post(Uri.parse('https://x.test/rest/v1/rpc/record_sale'), body: '{}'),
          throwsA(isA<SocketException>()));
    });
  });

  group('every request the app makes is bounded', () {
    test('no repository keeps a bare http.Client() (the Workers: photos, Wave, account, courier)', () {
      final bare = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trimLeft().startsWith('//')) continue;
          // The wrapper's own inner client, in main.dart and timeout_client.dart.
          if (l.contains('TimeoutClient(http.Client())')) continue;
          if (l.contains('http.Client()')) bare.add('${f.path}:${i + 1}');
        }
      }
      expect(bare, isEmpty);
      expect(TimeoutClient.bounded(), isA<TimeoutClient>());
    });

    test('a photo the Worker never sends ends, and the tile keeps its letter', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      final capture = CaptureRepository(null,
          db: db,
          uploadsUrl: 'https://up.test',
          httpClient: TimeoutClient(
              MockClient.streaming((r, _) => Completer<http.StreamedResponse>().future),
              timeout: const Duration(milliseconds: 50)));
      await expectLater(capture.publicObjectBytes('a/b.jpg'),
          throwsA(isA<LineDown>().having((e) => e.cause, 'cause', isA<RequestTimedOut>())));
    });
  });

  group('the outbox on a dead line', () {
    test('stops at the first failure of the network instead of waiting on every row', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      for (final org in ['shop', 'farm', 'asso']) {
        await db.recordEntry(orgId: org, amount: 1000, direction: 'out', label: 'Loyer');
      }
      var tries = 0;
      var online = false;
      final sync = SyncService(db, SupabaseClient('https://example.supabase.co', 'k'),
          currentUserId: () => 'u1', post: (action, params) async {
        tries++;
        if (!online) throw const SocketException('Failed host lookup');
        return 'id-$tries';
      });
      await sync.syncNow();
      expect(tries, 1, reason: 'the other two would have failed the same way, one timeout each');
      expect(await db.pendingCount(), 3, reason: 'nothing dropped');
      online = true;
      await sync.syncNow();
      expect(await db.pendingCount(), 0);
    });

    test('a refusal (not the network) still lets the rows behind it go', () async {
      final db = await LocalDb.open(path: inMemoryDatabasePath);
      addTearDown(db.close);
      await db.recordEntry(orgId: 'shop', amount: 1, direction: 'out', label: 'A');
      await db.recordEntry(orgId: 'shop', amount: 2, direction: 'out', label: 'B');
      var tries = 0;
      final sync = SyncService(db, SupabaseClient('https://example.supabase.co', 'k'),
          currentUserId: () => 'u1', post: (action, params) async {
        if (++tries == 1) throw const PostgrestException(message: 'refusé', code: '42501');
        return 'id-$tries';
      });
      await sync.syncNow();
      expect(tries, 2);
      expect(await db.pendingCount(), 1);
    });
  });

  group('the whole app, still', () {
    test('a thumbnail is decoded at its size, not the photo\'s 2000 px', () {
      expect(ProductPhoto.decodeWidth(const BoxConstraints.tightFor(width: 56, height: 56), 3), 336);
      expect(ProductPhoto.decodeWidth(const BoxConstraints(maxWidth: 120, maxHeight: 80), 2), 480);
      expect(ProductPhoto.decodeWidth(const BoxConstraints(), 2), isNull,
          reason: 'no size known: the whole picture');
    });

    testWidgets('the Articles tile asks the decoder for its own size', (tester) async {
      final db = await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath));
      addTearDown(() => tester.runAsync(db!.close));
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
      final capture = CaptureRepository(null,
          db: db!,
          uploadsUrl: 'https://up.test',
          httpClient: MockClient((r) async => http.Response.bytes(png, 200)));
      // A configured repository needs a client for its token; the bytes come
      // from the vitrine's public read here instead.
      final bytes = await tester.runAsync(() => capture.publicObjectBytes('k.png'));
      expect(bytes, isNotNull);
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(width: 60, height: 60, child: _Shown(bytes: bytes!)),
        ),
      ));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, ProductPhoto.decodeWidth(
          const BoxConstraints.tightFor(width: 60, height: 60), tester.view.devicePixelRatio));
    });

    test('a report\'s PDF is laid out off the UI isolate', () async {
      expect(ReportExport.inBackground, isTrue, reason: 'on a phone, compute()');
      final rows = [
        for (var i = 0; i < 3000; i++) ['Vente n° $i — œufs', 2500 + i, DateTime(2026, 10, 1 + i % 28)],
      ];
      final e = ReportExport(
        title: 'Journal',
        fileStem: 'journal',
        orgName: 'Ferme Sanou',
        currency: 'XOF',
        sections: [
          ExportSection(columns: const [
            ExportColumn('Libellé'),
            ExportColumn('Montant', money: true),
            ExportColumn('Date', date: true),
          ], rows: rows),
        ],
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
      );
      // Fonts left out: rootBundle is the app's; the isolate path is the same.
      final pdf = await e.toPdf(embedFonts: false);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(pdf.length, greaterThan(10000));
    });

    testWidgets('the app download card does not rebuild the page under it', (tester) async {
      var built = 0;
      DateTime? shownAt;
      await tester.pumpWidget(MaterialApp(
        home: AppDownloadPrompt(
          env: AppDownloadEnv(
            phone: AppPhone.ios,
            standalone: false,
            readShownAt: () => shownAt,
            writeShownAt: (at) => shownAt = at,
          ),
          links: () async => const AppLinks(android: apkDownloadUrl, ios: 'https://apps.apple.com/app/mara/id1'),
          child: _Counted(onInit: () => built++),
        ),
      ));
      expect(built, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byKey(const Key('app-download')), findsOneWidget);
      expect(built, 1, reason: 'the street was built again from nothing — every question asked twice');
      await tester.tap(find.byKey(const Key('app-download-later')));
      await tester.pump();
      expect(find.byKey(const Key('app-download')), findsNothing);
      expect(built, 1, reason: 'and a third time when the card closed');
    });
  });

  group('« Rejoindre »: the joined business opens', () {
    Future<void> flush(WidgetTester tester, {int rounds = 10}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      await tester.pump();
    }

    Future<(_Server, LocalDb)> open(WidgetTester tester,
        {required List<OrgSummary> before, required OrgSummary joins, required bool withCode}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.localesTestValue = [const Locale('fr')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/rejoindre';
      addTearDown(() => tester.binding.platformDispatcher.defaultRouteNameTestValue = '/');
      final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
      addTearDown(() => tester.runAsync(db.close));
      await tester.runAsync(() async {
        final salt = PinCodec.newSalt();
        await db.saveIdentity(LocalIdentity(
          userId: 'u-awa',
          displayName: 'Awa',
          phone: '+22670000001',
          pinSalt: withCode ? salt : null,
          pinHash: withCode ? PinCodec.hash('1379', salt) : null,
        ));
        await db.cacheOrgs(before);
      });
      final server = _Server(before);
      await tester.pumpWidget(KajApp(
        db: db,
        auth: server,
        admin: _Claims(server, joins),
        reports: ReportsRepository(null),
        accounting: AccountingRepository(null),
        console: ConsoleRepository(null),
        farm: FarmRepository(null),
        invoicing: InvoicingRepository(null),
        retail: RetailRepository(null),
        staff: StaffRepository(null),
        capture: CaptureRepository(null, db: db),
        onboarding: OnboardingRepository(null),
      ));
      await flush(tester);
      return (server, db);
    }

    Future<void> claim(WidgetTester tester) async {
      expect(find.byType(JoinOrApplyScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'AWA-2026');
      await tester.pump();
      await tester.tap(find.text('Rejoindre l’entreprise'));
      await flush(tester);
    }

    String? opened(WidgetTester tester) =>
        AppScope.of(tester.element(find.byType(Scaffold).first)).session.lastOrgId;

    const shop = OrgSummary(id: 'o-shop', name: 'Boutique Awa', profile: 'retail', roles: ['owner']);
    const farm = OrgSummary(id: 'o-farm', name: 'Ferme Sanou', profile: 'farm', roles: ['employee']);
    const asso = OrgSummary(
        id: 'o-asso', name: 'Association Wend', profile: 'association', roles: ['member']);

    testWidgets('someone who already has a business: the new one opens', (tester) async {
      await open(tester, before: const [shop], joins: farm, withCode: true);
      await claim(tester);
      expect(find.byType(JoinOrApplyScreen), findsNothing,
          reason: '« Ouverture de votre entreprise… » and nobody moved');
      expect(opened(tester), farm.id);
    });

    testWidgets('a first business: through the code to choose, then into it', (tester) async {
      await open(tester, before: const [], joins: asso, withCode: false);
      await claim(tester);
      // A first business asks for the device code (108) before its books.
      expect(find.byType(PinScreen), findsOneWidget);
      for (var round = 0; round < 2; round++) {
        for (final d in '1379'.split('')) {
          await tester.tap(find.text(d).last);
          await tester.pump();
        }
        await flush(tester, rounds: 4);
      }
      await flush(tester);
      expect(find.byType(PinScreen), findsNothing);
      expect(find.byType(JoinOrApplyScreen), findsNothing,
          reason: 'the code screen gave back /rejoindre, the form already used');
      expect(opened(tester), asso.id);
    });

    testWidgets('a first business with a code already on the phone: straight in', (tester) async {
      await open(tester, before: const [], joins: shop, withCode: true);
      await claim(tester);
      expect(find.byType(JoinOrApplyScreen), findsNothing);
      expect(opened(tester), shop.id);
    });
  });
}

class _Shown extends StatelessWidget {
  const _Shown({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Image.memory(bytes,
            fit: BoxFit.cover,
            cacheWidth: ProductPhoto.decodeWidth(box, MediaQuery.devicePixelRatioOf(context))),
      );
}

class _Counted extends StatefulWidget {
  const _Counted({required this.onInit});
  final VoidCallback onInit;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('La rue'));
}

class _Server extends AuthRepository {
  _Server(this.orgs) : super(null);

  List<OrgSummary> orgs;

  @override
  bool get hasLiveSession => true;

  @override
  Future<List<OrgSummary>> fetchOrgs() async => orgs;
}

class _Claims extends AdminRepository {
  _Claims(this.server, this.joins) : super(null);

  final _Server server;
  final OrgSummary joins;

  @override
  Future<bool> isPlatformAdmin() async => false;

  @override
  Future<int> claimMyInvitations() async => 0;

  @override
  Future<String> claimInvitation(String code) async {
    server.orgs = [...server.orgs, joins];
    return joins.id;
  }
}

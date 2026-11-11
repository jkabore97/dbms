import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/events/events_repository.dart' show eventKinds;
import 'package:kaj_app/core/events/street_event.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/events/street_picture_sheet.dart';
import 'package:kaj_app/features/storefront/street_events.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 162 in the app: the street's « Événements » strip — nothing when there
/// is no event — and one event's page: how far off, the tickets and their
/// places, « Réserver », the invitation, WhatsApp, share.
class _Street extends StorefrontRepository {
  _Street(this.list, {this.one}) : super(null);

  final List<StreetEvent> list;
  final StreetEvent? one;

  @override
  Future<List<StreetEvent>> streetEvents() async => list;

  @override
  Future<StreetEvent?> streetEvent(String slug) async => one;
}

final _now = DateTime(2026, 11, 2, 10);

StreetEvent _concert({bool full = false}) => StreetEvent.fromJson({
      'slug': 'concert-fatim-ab12',
      'title': 'Concert Fatim',
      'kind': 'concert',
      'starts_at': DateTime(2026, 11, 5, 20).toUtc().toIso8601String(),
      'date_fr': 'jeudi 5 novembre à 20 h',
      'place': 'CENASA',
      'org_name': 'Awa Concerts',
      'tickets': true,
      'from_price': 2000,
      'currency': 'XOF',
      'pay_whatsapp': '+226 70 00 00 01',
      if (full)
        'offer': {
          'open': true,
          'types': [
            {'name': 'Standard', 'price': 2000, 'left': 12},
            {'name': 'VIP', 'price': 10000, 'left': 0},
          ],
        },
    });

final _party = StreetEvent.fromJson({
  'slug': 'fete-ab12',
  'title': 'Fête du quartier',
  'kind': 'anniversaire',
  'starts_at': DateTime(2026, 11, 2, 19).toUtc().toIso8601String(),
  'date_fr': 'lundi 2 novembre à 19 h',
  'tickets': false,
});

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: Scaffold(body: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  setUp(() async => db = await LocalDb.open(path: inMemoryDatabasePath));
  tearDown(() => db.close());

  test('how far off: in progress, today, tomorrow, in n days', () {
    expect(eventCountdown(DateTime(2026, 11, 2, 9), _now).phrase, 'En cours');
    expect(eventCountdown(DateTime(2026, 11, 2, 22), _now).phrase, 'Aujourd’hui');
    expect(eventCountdown(DateTime(2026, 11, 3, 1), _now).phrase, 'Demain');
    final c = eventCountdown(DateTime(2026, 11, 5, 20), _now);
    expect((c.phrase, c.n), ('Dans {n} j', 3));
  });

  testWidgets('no event: no strip at all', (tester) async {
    await _pump(tester, StreetEventsStrip(storefront: _Street(const []), capture: CaptureRepository(null, db: db)));
    expect(find.byKey(const Key('street-events')), findsNothing);
    expect(find.text('Événements'), findsNothing);
  });

  testWidgets('the strip: each event with how far off, the date and from what price; a tap opens its page',
      (tester) async {
    final street = _Street([_party, _concert()], one: _concert(full: true));
    await _pump(tester, StreetEventsStrip(storefront: street, capture: CaptureRepository(null, db: db), now: () => _now));
    expect(find.text('ÉVÉNEMENTS'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text('Dans 3 j'), findsOneWidget);
    expect(find.text('Entrée libre'), findsOneWidget);
    expect(find.textContaining('Billets dès 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('street-event-concert-fatim-ab12')));
    await tester.pumpAndSettle();
    expect(find.text('Concert Fatim'), findsOneWidget);
    expect(find.text('Organisé par Awa Concerts'), findsOneWidget);
    expect(find.text('12 places'), findsOneWidget);
    expect(find.text('Complet'), findsOneWidget);
  });

  testWidgets('the event page: « Réserver » opens the tickets, the invitation, WhatsApp, share', (tester) async {
    final opened = <Uri>[];
    final shared = <String>[];
    await _pump(
      tester,
      EventVitrineScreen(
        storefront: _Street(const [], one: _concert(full: true)),
        capture: CaptureRepository(null, db: db),
        first: _concert(),
        now: () => _now,
        open: (u) async => opened.add(u),
        share: (t) async => shared.add(t),
      ),
    );
    expect(find.text('DANS 3 J'), findsOneWidget);
    expect(find.text('Le paiement se fait directement à l’organisateur. Marakaj n’encaisse rien.'), findsOneWidget);
    for (final k in ['event-vitrine-book', 'event-vitrine-card', 'event-vitrine-wa', 'event-vitrine-share']) {
      await tester.ensureVisible(find.byKey(Key(k)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(k)));
      await tester.pumpAndSettle();
    }
    expect(opened[0].path, '/e/concert-fatim-ab12/billets');
    expect(opened[1].path, '/e/concert-fatim-ab12');
    expect(opened[2].host, 'wa.me');
    expect(opened[2].path, '/22670000001');
    expect(shared.single, contains('https://marakaj.com/e/concert-fatim-ab12'));
  });

  testWidgets('an event no longer on the street says so; no « Réserver »', (tester) async {
    await _pump(
      tester,
      EventVitrineScreen(storefront: _Street(const []), capture: CaptureRepository(null, db: db), first: _concert(), now: () => _now),
    );
    expect(find.text('Cet événement n’est plus sur la rue.'), findsOneWidget);
    expect(find.byKey(const Key('event-vitrine-book')), findsNothing);
  });

  testWidgets('165: a sponsored event says so on the street', (tester) async {
    final sponsored = StreetEvent.fromJson({
      'slug': 'gala-ab12', 'title': 'Gala', 'kind': 'gala', 'starts_at': DateTime(2026, 11, 9, 20).toUtc().toIso8601String(),
      'tickets': false, 'sponsored': true,
    });
    await _pump(tester, StreetEventsStrip(storefront: _Street([sponsored, _party]), capture: CaptureRepository(null, db: db), now: () => _now));
    expect(find.text('Sponsorisé'), findsOneWidget);
  });

  // 174: the owner — « you really need to find and put a nice preview for
  // events », then « very nice and high quality preview images ». No photo:
  // the picture of its kind of event under its kind and day; a bank photo:
  // that photo; the card's own photo: that, as before.
  testWidgets('174: a card without a photo shows its kind\'s picture under its kind and day; a bank photo is used', (tester) async {
    StreetEvent ev(String kind, Map<String, dynamic> extra) => StreetEvent.fromJson({
          'slug': 'e-$kind-${extra.length}',
          'title': 'Esprance Anniversaire',
          'kind': kind,
          'starts_at': DateTime(2027, 1, 16, 18).toUtc().toIso8601String(),
          'date_fr': 'Samedi 16 janvier 2027 · 18 h',
          'tickets': false,
          ...extra,
        });
    String? asked(WidgetTester tester) => tester.widgetList<Image>(find.byType(Image)).map((i) => i.image)
        .map((p) => p is ResizeImage ? p.imageProvider : p).whereType<NetworkImage>().map((n) => n.url).firstOrNull;

    await _pump(tester, StreetEventsStrip(storefront: _Street([ev('anniversaire', {'card': 'anime_carnet'})]), capture: CaptureRepository(null, db: db), now: () => _now));
    expect(find.byKey(const Key('street-event-design')), findsOneWidget);
    expect(find.text('16'), findsOneWidget, reason: 'the day on its badge');
    expect(find.text('JANV.'), findsOneWidget);
    expect(asked(tester), 'https://marakaj.com/cartes/fetes/anniversaire.jpg');

    // a kind without its own picture (« retraite »): the festive gathering
    await _pump(tester, StreetEventsStrip(key: const Key('b'), storefront: _Street([ev('retraite', {})]), capture: CaptureRepository(null, db: db), now: () => _now));
    expect(asked(tester), 'https://marakaj.com/cartes/fetes/autre.jpg');

    // a bank photo
    await _pump(tester, StreetEventsStrip(key: const Key('c'), storefront: _Street([ev('mariage', {'card': 'jardin', 'poster_stock': 'garden-2'})]), capture: CaptureRepository(null, db: db), now: () => _now));
    expect(find.byKey(const Key('street-event-stock')), findsOneWidget);
    expect(asked(tester), 'https://marakaj.com/cartes/img/garden-2.jpg');
  });

  test('174: every kind of event has its picture in the site, small enough for a phone', () {
    for (final (kind, _) in eventKinds) {
      final pic = kind == 'retraite' ? 'autre' : kind;
      final f = File('web/cartes/fetes/$pic.jpg');
      expect(f.existsSync(), isTrue, reason: kind);
      expect(f.lengthSync(), lessThan(400 * 1024), reason: '$kind: under 400 kB');
    }
    expect(File('web/cartes/fetes/autre.jpg').existsSync(), isTrue);
  });

  // 175: the owner — « allow them to put their own image or choose between
  // those you generated ». The organiser's gallery choice comes first, even
  // before the card's own photo.
  testWidgets('175: the gallery picture the organiser chose is the one shown, before the card\'s photo', (tester) async {
    final chosen = StreetEvent.fromJson({
      'slug': 'mariage-ab12', 'title': 'Mariage Awa & Paul', 'kind': 'mariage',
      'starts_at': DateTime(2027, 1, 16, 18).toUtc().toIso8601String(), 'tickets': false,
      'poster': null, 'poster_fete': 'gala',
    });
    await _pump(tester, StreetEventsStrip(storefront: _Street([chosen]), capture: CaptureRepository(null, db: db), now: () => _now));
    final urls = tester.widgetList<Image>(find.byType(Image)).map((i) => i.image)
        .map((p) => p is ResizeImage ? p.imageProvider : p).whereType<NetworkImage>().map((n) => n.url);
    expect(urls.first, 'https://marakaj.com/cartes/fetes/gala.jpg');
    expect(find.text('JANV.'), findsOneWidget, reason: 'its day on the badge still');

    // a name the app will not ask for: the kind's own picture
    final odd = StreetEvent.fromJson({
      'slug': 'odd-ab12', 'title': 'X', 'kind': 'mariage',
      'starts_at': DateTime(2027, 1, 16, 18).toUtc().toIso8601String(), 'tickets': false, 'poster_fete': '../x',
    });
    await _pump(tester, StreetEventsStrip(key: const Key('b'), storefront: _Street([odd]), capture: CaptureRepository(null, db: db), now: () => _now));
    final urls2 = tester.widgetList<Image>(find.byType(Image)).map((i) => i.image)
        .map((p) => p is ResizeImage ? p.imageProvider : p).whereType<NetworkImage>().map((n) => n.url);
    expect(urls2.first, 'https://marakaj.com/cartes/fetes/mariage.jpg');
  });

  testWidgets('175: « Photo sur la rue » — automatic, the card\'s own pictures, the gallery with the kind\'s first', (tester) async {
    ({String? choice})? answer;
    late BuildContext ctx;
    await _pump(tester, Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }));
    Future<void> open(String? current, List<String> own) async {
      answer = null;
      showStreetPictureSheet(ctx, current: current, kind: 'concert', ownKeys: own, ownUrl: (k) => 'https://up.test/$k')
          .then((a) => answer = a);
      await tester.pumpAndSettle();
    }

    await open(null, const []);
    expect(find.text('Photo sur la rue'), findsOneWidget);
    expect(find.byKey(const Key('street-picture-own-none')), findsOneWidget, reason: 'no photo yet: how to add one');
    final first = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('street-picture-fete-'));
    expect((tester.widget(first.first).key as ValueKey<String>).value, 'street-picture-fete-concert', reason: 'the kind\'s own first');
    await tester.tap(find.byKey(const Key('street-picture-fete-concert')));
    await tester.pumpAndSettle();
    expect(answer?.choice, 'fete:concert');

    const key = 'events/17517517-2222-0000-0000-000000000001/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg';
    await open('fete:concert', const [key]);
    await tester.tap(find.byKey(const Key('street-picture-own-$key')));
    await tester.pumpAndSettle();
    expect(answer?.choice, key);

    await open(key, const [key]);
    await tester.tap(find.byKey(const Key('street-picture-auto')));
    await tester.pumpAndSettle();
    expect(answer, isNotNull);
    expect(answer!.choice, isNull, reason: 'automatic again');
  });

  test('175: the gallery names the app asks for, and each kind\'s own', () {
    expect(streetGalleryName('mariage-2'), isTrue);
    expect(streetGalleryName('../x'), isFalse);
    expect(streetGalleryName(null), isFalse);
    expect(streetPictureOfKind('anniv'), 'anniversaire');
    expect(streetPictureOfKind('retraite'), 'autre');
    for (final g in streetGallery) {
      expect(File('web/cartes/fetes/$g.jpg').existsSync(), isTrue, reason: g);
    }
  });
}

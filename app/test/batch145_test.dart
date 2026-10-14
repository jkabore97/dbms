import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/rates/currency_rates.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/features/admin/org_settings_screen.dart';
import 'package:kaj_app/features/admin/pin_picker.dart';
import 'package:kaj_app/features/setup/setup_screen.dart';
import 'package:kaj_app/features/storefront/directory_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 145: the business's position, moved with a finger on the map.
///
/// The owner: « move the pin with a finger on the map » to the exact door.
/// Paramètres › « La position de ma boutique / ma ferme / mon association »
/// and the first setup's position step draw PinPicker: drag the pin or tap
/// a spot, the latitude and longitude follow live, typing moves the pin,
/// « + » / « − » / « Centrer sur ma position », two fingers pinch the map,
/// one finger elsewhere still scrolls the page; « Enregistrer » saves.
///
/// No tile is fetched here (tiles: false / mapTiles: false).
/// `B145_SHOTS=<dir>` also writes the screenshots.

const _ouaga = (12.3714, -1.5197);

// ---------------------------------------------------------------------------
// The settings' server, faked
// ---------------------------------------------------------------------------

class _Admin extends AdminRepository {
  _Admin({
    required this.profile,
    this.lat,
    this.lng,
    this.phone,
    this.currency = 'XOF',
  }) : super(null);

  final String profile;
  final double? lat;
  final double? lng;
  final String? phone;
  final String currency;

  /// Every set_storefront_location sent, in order.
  final saved = <(double?, double?)>[];

  String get _name => switch (profile) {
    'farm' => 'Ferme Sahel Vert',
    'association' => 'Association Lumière du Kadiogo',
    _ => 'Boutique Kanvas',
  };

  @override
  Future<Map<String, dynamic>> fetchOrg(String orgId) async => {
    'id': orgId,
    'name': _name,
    'slug': 'kanvas',
    'profile': profile,
    'default_currency': currency,
  };

  @override
  Future<String?> waveMerchant(String orgId) async => null;

  @override
  Future<List<CurrencyRate>> currencyRates(String orgId) async => const [];

  @override
  Future<
    ({
      bool enabled,
      String? blurb,
      double? lat,
      double? lng,
      double? deliveryBase,
      double? deliveryPerKm,
    })
  >
  storefront(String orgId) async => (
    enabled: true,
    blurb: 'Tout le quartier' as String?,
    lat: lat,
    lng: lng,
    deliveryBase: null as double?,
    deliveryPerKm: null as double?,
  );

  @override
  Future<double?> deliveryReach(String orgId) async => null;

  @override
  Future<double?> deliveryIncludedKm(String orgId) async => null;

  @override
  Future<({String? phone, String? address})> orgContact(String orgId) async =>
      (phone: phone, address: null);

  @override
  Future<VitrineChecklist?> vitrineChecklist(String orgId) async => null;

  // The save.
  @override
  Future<void> updateOrg({
    required String orgId,
    String? name,
    String? slug,
    String? profile,
    String? currency,
  }) async {}

  @override
  Future<void> setWaveMerchant(String orgId, String? merchant) async {}

  @override
  Future<void> setStorefront(
    String orgId, {
    required bool enabled,
    String? blurb,
  }) async {}

  @override
  Future<void> setOrgContact(
    String orgId, {
    required String phone,
    required String address,
  }) async {}

  @override
  Future<void> setStorefrontLocation(
    String orgId, {
    double? lat,
    double? lng,
  }) async => saved.add((lat, lng));

  @override
  Future<void> setDeliveryRates(
    String orgId, {
    double? base,
    double? perKm,
  }) async {}

  @override
  Future<void> setDeliveryIncludedKm(String orgId, double? km) async {}

  @override
  Future<void> setDeliveryReach(String orgId, double? km) async {}
}

class _Setup implements SetupActions {
  final log = <String>[];

  @override
  Future<void> rename(String orgId, String name, String currency) async =>
      log.add('rename');

  @override
  Future<void> addArticle(
    String orgId, {
    required String name,
    required double price,
    required double quantity,
  }) async => log.add('article');

  @override
  Future<void> saveVitrine(
    String orgId, {
    required bool open,
    required String blurb,
    required String phone,
    required String address,
  }) async => log.add('vitrine');

  @override
  Future<void> savePosition(String orgId, double lat, double lng) async =>
      log.add('position ${lat.toStringAsFixed(4)} ${lng.toStringAsFixed(4)}');

  @override
  Future<void> finish(String orgId) async => log.add('finish');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _size(
  WidgetTester tester,
  double w,
  double h, {
  double text = 1,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Widget _app(Widget home, {String lang = 'fr'}) => MaterialApp(
  locale: Locale(lang),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  debugShowCheckedModeBanner: false,
  home: RepaintBoundary(key: const Key('shot'), child: home),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openPosition(
  WidgetTester tester,
  _Admin admin, {
  String lang = 'fr',
  double w = 390,
  double h = 1100,
  double text = 1,
}) async {
  await _size(tester, w, h, text: text);
  await tester.pumpWidget(
    _app(
      OrgSettingsScreen(
        admin: admin,
        orgId: 'org-1',
        initialPart: 'position',
        mapTiles: false,
      ),
      lang: lang,
    ),
  );
  await _settle(tester);
}

/// Scrolls the page (not a field) until [f] is built and on screen.
Future<void> _reach(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    150,
    scrollable: find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.pump();
}

/// The map's own camera, read from inside it (the zoom buttons are not).
MapCamera _cameraOf(WidgetTester tester) => MapCamera.of(
  tester.element(
    find.descendant(
      of: find.byType(FlutterMap),
      matching: find.byType(MarkerLayer),
    ),
  ),
);

double _field(WidgetTester tester, String key) => double.parse(
  tester.widget<TextField>(find.byKey(Key(key))).controller!.text,
);

Offset _mapCentre(WidgetTester tester) =>
    tester.getCenter(find.byKey(const Key('pin-picker-map')));

/// The pin's tip on screen (the marker box is above its point).
Offset _pinTip(WidgetTester tester) =>
    tester.getBottomLeft(find.byKey(const Key('pin-picker-pin'))) +
    Offset(
      tester.getSize(find.byKey(const Key('pin-picker-pin'))).width / 2,
      0,
    );

/// PinPicker alone, in a page that scrolls, with room above and below.
Future<({ScrollController scroll, List<(double, double)> moves})> _pumpPicker(
  WidgetTester tester, {
  double? lat = 12.3714,
  double? lng = -1.5197,
  String currency = 'XOF',
  String? phone,
  String lang = 'fr',
  double w = 390,
  double h = 844,
  double text = 1,
}) async {
  await _size(tester, w, h, text: text);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  final moves = <(double, double)>[];
  (double, double)? pin = lat == null ? null : (lat, lng!);
  await tester.pumpWidget(
    _app(
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 200),
              PinPicker(
                lat: pin?.$1,
                lng: pin?.$2,
                currency: currency,
                phone: phone,
                tiles: false,
                onLocate: () {},
                onMove: (a, b) => setState(() {
                  moves.add((a, b));
                  pin = (a, b);
                }),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
      lang: lang,
    ),
  );
  await _settle(tester);
  return (scroll: scroll, moves: moves);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    await initializeDateFormatting('en', null);
  });

  // -------------------------------------------------------------------------
  group('the map: drag, tap, zoom, and the page', () {
    testWidgets('a tap moves the pin there', (tester) async {
      final r = await _pumpPicker(tester);
      final before = _pinTip(tester);
      await tester.tapAt(_mapCentre(tester) + const Offset(-80, 50));
      await _settle(tester);
      expect(r.moves, hasLength(1));
      final (lat, lng) = r.moves.single;
      expect(lat, lessThan(_ouaga.$1), reason: 'below the centre: south');
      expect(lng, lessThan(_ouaga.$2), reason: 'left of the centre: west');
      // The pin is now drawn where the finger was.
      final after = _pinTip(tester);
      expect((after - before).dx, closeTo(-80, 3));
      expect((after - before).dy, closeTo(50, 3));
    });

    testWidgets('dragging the pin moves it live, and the page stays still', (
      tester,
    ) async {
      final r = await _pumpPicker(tester);
      final start = _pinTip(tester) - const Offset(0, 20);
      final g = await tester.startGesture(start);
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(10, 15));
        await tester.pump();
      }
      expect(
        r.moves.length,
        greaterThanOrEqualTo(5),
        reason: 'each move is sent at once',
      );
      await g.up();
      await _settle(tester);
      expect(r.scroll.offset, 0, reason: 'the finger on the pin is the pin\'s');
      final (lat, lng) = r.moves.last;
      expect(lat, lessThan(_ouaga.$1));
      expect(lng, greaterThan(_ouaga.$2));
    });

    testWidgets('one finger on the map scrolls the page: it is not trapped', (
      tester,
    ) async {
      final r = await _pumpPicker(tester);
      await tester.dragFrom(
        _mapCentre(tester) + const Offset(-120, 60),
        const Offset(0, -150),
      );
      await _settle(tester);
      expect(r.scroll.offset, greaterThan(100));
      expect(r.moves, isEmpty, reason: 'a scroll is not a tap');
    });

    testWidgets('a finger held still, then moved, still scrolls the page', (
      tester,
    ) async {
      final r = await _pumpPicker(tester);
      final g = await tester.startGesture(
        _mapCentre(tester) + const Offset(-120, 60),
      );
      await tester.pump(const Duration(milliseconds: 800));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, -15));
        await tester.pump();
      }
      await g.up();
      await _settle(tester);
      expect(r.scroll.offset, greaterThan(100));
      expect(r.moves, isEmpty);
    });

    testWidgets('a mouse wheel over the map scrolls the page', (tester) async {
      final r = await _pumpPicker(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(_mapCentre(tester)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await _settle(tester);
      expect(r.scroll.offset, greaterThan(0));
    });

    testWidgets('+ and − zoom; « Centrer sur ma position » is there', (
      tester,
    ) async {
      await _pumpPicker(tester);
      expect(_cameraOf(tester).zoom, 16);
      await tester.tap(find.byKey(const Key('pin-picker-zoom-in')));
      await _settle(tester);
      expect(_cameraOf(tester).zoom, 17);
      await tester.tap(find.byKey(const Key('pin-picker-zoom-out')));
      await tester.tap(find.byKey(const Key('pin-picker-zoom-out')));
      await _settle(tester);
      expect(_cameraOf(tester).zoom, 15);
      expect(find.byTooltip('Centrer sur ma position'), findsOneWidget);
    });

    testWidgets('two fingers pinch the map, and the page holds still', (
      tester,
    ) async {
      final r = await _pumpPicker(tester);
      final c = _mapCentre(tester) + const Offset(-60, 0);
      final a = await tester.startGesture(c - const Offset(30, 0), pointer: 7);
      final b = await tester.startGesture(c + const Offset(30, 0), pointer: 8);
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-10, -8));
        await b.moveBy(const Offset(10, 8));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await _settle(tester);
      expect(r.scroll.offset, 0);
      expect(_cameraOf(tester).zoom, greaterThan(16.9));
      expect(r.moves, isEmpty, reason: 'a pinch does not move the pin');
    });

    testWidgets('the tiles\' credit is on the map', (tester) async {
      await _pumpPicker(tester);
      expect(find.text('© OpenStreetMap'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('no position yet', () {
    testWidgets('no pin, the place asked; a tap places it', (tester) async {
      final r = await _pumpPicker(
        tester,
        lat: null,
        lng: null,
        phone: '+22670123456',
      );
      expect(find.byKey(const Key('pin-picker-pin')), findsNothing);
      expect(find.byKey(const Key('pin-picker-place')), findsOneWidget);
      expect(
        find.textContaining('touchez la carte à l\'endroit de la porte'),
        findsOneWidget,
      );
      await tester.tapAt(_mapCentre(tester));
      await _settle(tester);
      expect(r.moves, hasLength(1));
      // Burkina Faso's middle, from the phone's +226.
      expect(r.moves.single.$1, closeTo(12.24, 0.3));
      expect(r.moves.single.$2, closeTo(-1.56, 0.3));
      expect(find.byKey(const Key('pin-picker-pin')), findsOneWidget);
      expect(find.byKey(const Key('pin-picker-place')), findsNothing);
      // The first pin brings the map in to the street.
      expect(_cameraOf(tester).zoom, 16);
    });

    test('where the map opens: the phone, the currency, or the world', () {
      expect(startView(phone: '+22670123456', currency: 'XOF'), (
        lat: 12.24,
        lng: -1.56,
        zoom: 6.0,
      ));
      expect(
        startView(phone: '+225 07 12 34 56', currency: 'XOF').lat,
        closeTo(7.5, 0.1),
      );
      expect(startView(currency: 'XOF'), (lat: 12.0, lng: -4.0, zoom: 4.0));
      expect(startView(currency: 'XAF').lng, 15.0);
      // A Paris number for a franc CFA shop: the zone, not France.
      expect(startView(phone: '+33612345678', currency: 'XOF').lng, -4.0);
      // A number with no country says nothing.
      expect(startView(phone: '70 12 34 56', currency: 'USD'), (
        lat: 15.0,
        lng: 0.0,
        zoom: 2.0,
      ));
      expect(
        startView(phone: '0033612345678', currency: 'EUR').lat,
        closeTo(46.6, 0.1),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the warning, kept', () {
    testWidgets('a pin far from the franc CFA zone is said', (tester) async {
      await _pumpPicker(tester, lat: 40.757953, lng: -74.191392);
      expect(find.byKey(const Key('pin-picker-misplaced')), findsOneWidget);
      expect(
        find.textContaining('loin de la zone de votre monnaie'),
        findsOneWidget,
      );
    });

    testWidgets('Ouagadougou is not', (tester) async {
      await _pumpPicker(tester);
      expect(find.byKey(const Key('pin-picker-misplaced')), findsNothing);
    });

    testWidgets('a business in dollars is not judged', (tester) async {
      await _openPosition(
        tester,
        _Admin(
          profile: 'retail',
          lat: 40.757953,
          lng: -74.191392,
          currency: 'USD',
        ),
      );
      expect(find.byKey(const Key('pin-picker-pin')), findsOneWidget);
      expect(find.byKey(const Key('pin-picker-misplaced')), findsNothing);
    });

    testWidgets('dragging it home lifts the warning', (tester) async {
      await _openPosition(
        tester,
        _Admin(profile: 'retail', lat: 40.757953, lng: -74.191392),
      );
      expect(find.byKey(const Key('pin-picker-misplaced')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('position-lat')), '12.3714');
      await tester.enterText(find.byKey(const Key('position-lng')), '-1.5197');
      await _settle(tester);
      expect(find.byKey(const Key('pin-picker-misplaced')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('Paramètres › position, every kind', () {
    for (final (profile, title) in const [
      ('retail', 'La position de ma boutique'),
      ('farm', 'La position de ma ferme'),
      ('association', 'La position de mon association'),
    ]) {
      testWidgets(
        '$profile: drag, the fields follow; nothing saved until « Enregistrer »',
        (tester) async {
          final admin = _Admin(
            profile: profile,
            lat: _ouaga.$1,
            lng: _ouaga.$2,
          );
          await _openPosition(tester, admin);
          expect(find.text(title), findsWidgets);
          expect(_field(tester, 'position-lat'), _ouaga.$1);

          await tester.drag(
            find.byKey(const Key('pin-picker-pin')),
            const Offset(60, 40),
          );
          await _settle(tester);
          final lat = _field(tester, 'position-lat');
          final lng = _field(tester, 'position-lng');
          expect(lat, lessThan(_ouaga.$1));
          expect(lng, greaterThan(_ouaga.$2));
          expect(
            admin.saved,
            isEmpty,
            reason: 'nothing is saved while dragging',
          );

          await _reach(tester, find.text('Enregistrer'));
          await tester.tap(find.text('Enregistrer'));
          await _settle(tester);
          expect(admin.saved, [(lat, lng)]);
        },
      );

      testWidgets('$profile: typing in the fields moves the pin', (
        tester,
      ) async {
        await _openPosition(
          tester,
          _Admin(profile: profile, lat: _ouaga.$1, lng: _ouaga.$2),
        );
        final before = _pinTip(tester);
        // About 300 m north-east: still in the view at street zoom… and
        // the map follows the pin to the centre.
        await tester.enterText(
          find.byKey(const Key('position-lat')),
          '12.3741',
        );
        await tester.enterText(
          find.byKey(const Key('position-lng')),
          '-1.5170',
        );
        await _settle(tester);
        final camera = _cameraOf(tester);
        expect(camera.center.latitude, closeTo(12.3741, 1e-6));
        expect(camera.center.longitude, closeTo(-1.5170, 1e-6));
        // The pin is at the map's centre, where it was before (centred).
        expect((_pinTip(tester) - before).distance, lessThan(2));
      });

      testWidgets(
        '$profile: no position yet — the map asks, a tap fills the fields',
        (tester) async {
          final admin = _Admin(profile: profile, phone: '+22670123456');
          await _openPosition(tester, admin);
          expect(find.byKey(const Key('pin-picker-place')), findsOneWidget);
          expect(find.byKey(const Key('position-lat')), findsOneWidget);
          await tester.tapAt(_mapCentre(tester));
          await _settle(tester);
          expect(_field(tester, 'position-lat'), closeTo(12.24, 0.3));
          expect(_field(tester, 'position-lng'), closeTo(-1.56, 0.3));
          await _reach(tester, find.text('Enregistrer'));
          await tester.tap(find.text('Enregistrer'));
          await _settle(tester);
          expect(admin.saved.single.$1, closeTo(12.24, 0.3));
        },
      );
    }

    testWidgets('a position cleared is saved as none, as before', (
      tester,
    ) async {
      final admin = _Admin(profile: 'retail', lat: _ouaga.$1, lng: _ouaga.$2);
      await _openPosition(tester, admin);
      await tester.enterText(find.byKey(const Key('position-lat')), '');
      await tester.enterText(find.byKey(const Key('position-lng')), '');
      await _settle(tester);
      expect(find.byKey(const Key('pin-picker-pin')), findsNothing);
      await _reach(tester, find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await _settle(tester);
      expect(admin.saved, [(null, null)]);
    });
  });

  // -------------------------------------------------------------------------
  group('the first setup\'s position step', () {
    testWidgets(
      'a tap places the pin, a drag moves it, « Terminer » saves it',
      (tester) async {
        await _size(tester, 480, 1400);
        final a = _Setup();
        await tester.pumpWidget(
          _app(
            SetupScreen(
              org: const OrgSummary(
                id: 'o1',
                name: 'Ferme Sahel Vert',
                profile: 'farm',
                roles: ['owner'],
                slug: 'sahel',
              ),
              actions: a,
              onDone: () {},
              stepsOff: () async => {'vitrine'},
              mapTiles: false,
            ),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const Key('setup-next-0')));
        await _settle(tester);
        await tester.enterText(
          find.byKey(const Key('setup-article')),
          'Poulet bicyclette',
        );
        await tester.enterText(find.byKey(const Key('setup-price')), '3500');
        await tester.enterText(find.byKey(const Key('setup-quantity')), '20');
        await tester.tap(find.byKey(const Key('setup-add')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('setup-next-1')));
        await _settle(tester);

        expect(find.text('La position de ma ferme'), findsOneWidget);
        expect(find.byKey(const Key('pin-picker-place')), findsOneWidget);
        expect(find.byKey(const Key('setup-locate')), findsOneWidget);
        await _reach(tester, find.byKey(const Key('pin-picker-map')));
        await tester.tapAt(_mapCentre(tester));
        await _settle(tester);
        expect(find.byKey(const Key('setup-next-3')), findsOneWidget);
        await tester.drag(
          find.byKey(const Key('pin-picker-pin')),
          const Offset(0, 30),
        );
        await _settle(tester);
        await tester.tap(find.byKey(const Key('setup-next-3')));
        await _settle(tester);
        expect(a.log.where((l) => l.startsWith('position')), hasLength(1));
        final parts = a.log
            .firstWhere((l) => l.startsWith('position'))
            .split(' ');
        // Burkina Faso from the setup's +226, then dragged south.
        expect(double.parse(parts[1]), lessThan(12.24));
        expect(double.parse(parts[2]), closeTo(-1.56, 0.01));
      },
    );
  });

  // -------------------------------------------------------------------------
  group('French and English', () {
    testWidgets('English', (tester) async {
      await _openPosition(
        tester,
        _Admin(profile: 'farm', lat: _ouaga.$1, lng: _ouaga.$2),
        lang: 'en',
      );
      expect(
        find.text('Drag the pin to the door, or tap the map at that spot.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Two fingers (or the mouse) move the map'),
        findsOneWidget,
      );
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Centre on my position'), findsOneWidget);
      expect(find.text('© OpenStreetMap'), findsOneWidget);
    });

    testWidgets('English, no position yet, and the warning', (tester) async {
      await _pumpPicker(tester, lat: null, lng: null, lang: 'en');
      expect(
        find.text(
          'No position yet: tap the map where the door is to place the pin there.',
        ),
        findsOneWidget,
      );
      await _pumpPicker(tester, lat: 40.75, lng: -74.19, lang: 'en');
      expect(
        find.textContaining('far from your currency\'s area'),
        findsOneWidget,
      );
    });

    testWidgets('French', (tester) async {
      await _openPosition(
        tester,
        _Admin(profile: 'association', lat: _ouaga.$1, lng: _ouaga.$2),
      );
      expect(
        find.text(
          'Faites glisser le repère jusqu\'à la porte, ou touchez la carte à cet endroit.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Zoomer'), findsOneWidget);
      expect(find.byTooltip('Dézoomer'), findsOneWidget);
      expect(find.byTooltip('Centrer sur ma position'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('320 px at 1.3', () {
    for (final lang in ['fr', 'en']) {
      for (final profile in ['retail', 'farm', 'association']) {
        for (final placed in [true, false]) {
          testWidgets(
            '$lang $profile ${placed ? 'placed' : 'no position'}: no overflow',
            (tester) async {
              await _openPosition(
                tester,
                _Admin(
                  profile: profile,
                  lat: placed ? 40.757953 : null,
                  lng: placed ? -74.191392 : null,
                ),
                lang: lang,
                w: 320,
                h: 640,
                text: 1.3,
              );
              expect(tester.takeException(), isNull);
              expect(find.byKey(const Key('pin-picker-map')), findsOneWidget);
              final map = tester.getRect(
                find.byKey(const Key('pin-picker-map')),
              );
              expect(map.width, lessThanOrEqualTo(320));
              expect(map.left, greaterThanOrEqualTo(0));
              // The buttons and the credit sit inside the map.
              final zoom = tester.getRect(
                find.byKey(const Key('pin-picker-zoom-in')),
              );
              expect(map.contains(zoom.center), isTrue);
              final credit = tester.getRect(
                find.byKey(const Key('osm-credit')),
              );
              expect(credit.right, lessThanOrEqualTo(map.right + 0.5));
              // Down to « Enregistrer »: nothing overflows on the way.
              await _reach(
                tester,
                find.text(lang == 'fr' ? 'Enregistrer' : 'Save'),
              );
              await _settle(tester);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    testWidgets('six decimals are read whole: the fields stack at 320 × 1.3', (
      tester,
    ) async {
      await _openPosition(
        tester,
        _Admin(profile: 'retail', lat: 12.370352, lng: -1.518198),
        w: 320,
        h: 640,
        text: 1.3,
      );
      await _reach(tester, find.byKey(const Key('position-lng')));
      final lat = tester.getRect(find.byKey(const Key('position-lat')));
      final lng = tester.getRect(find.byKey(const Key('position-lng')));
      expect(lng.top, greaterThan(lat.bottom), reason: 'one under the other');
      await _openPosition(
        tester,
        _Admin(profile: 'retail', lat: 12.37, lng: -1.51),
      );
      final a = tester.getRect(find.byKey(const Key('position-lat')));
      final b = tester.getRect(find.byKey(const Key('position-lng')));
      expect(a.top, b.top, reason: 'side by side at 390');
    });

    testWidgets('the first setup\'s map at 320 × 1.3', (tester) async {
      final r = await _pumpPicker(
        tester,
        lat: null,
        lng: null,
        w: 320,
        h: 640,
        text: 1.3,
      );
      expect(tester.takeException(), isNull);
      expect(r.moves, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('the supervisor\'s cases', () {
    testWidgets('« NaN » typed is no position, and is not saved', (
      tester,
    ) async {
      final admin = _Admin(profile: 'retail', lat: _ouaga.$1, lng: _ouaga.$2);
      await _openPosition(tester, admin);
      await tester.enterText(find.byKey(const Key('position-lat')), 'NaN');
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('pin-picker-pin')), findsNothing);
      await _reach(tester, find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await _settle(tester);
      expect(admin.saved, isEmpty);
      expect(
        find.text('Indiquez la latitude et la longitude, ou aucune des deux.'),
        findsOneWidget,
      );
    });

    testWidgets('a comma typed as the decimal point moves the pin', (
      tester,
    ) async {
      final admin = _Admin(profile: 'farm', lat: _ouaga.$1, lng: _ouaga.$2);
      await _openPosition(tester, admin);
      await tester.enterText(find.byKey(const Key('position-lat')), '12,3741');
      await tester.enterText(find.byKey(const Key('position-lng')), '-1,5170');
      await _settle(tester);
      expect(_cameraOf(tester).center.latitude, closeTo(12.3741, 1e-6));
      await _reach(tester, find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await _settle(tester);
      expect(admin.saved, [(12.3741, -1.517)]);
    });

    testWidgets('the map turned off mid-drag ends the drag', (tester) async {
      await _size(tester, 390, 844);
      final moves = <(double, double)>[];
      var enabled = true;
      late StateSetter set;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return PinPicker(
                  lat: _ouaga.$1,
                  lng: _ouaga.$2,
                  currency: 'XOF',
                  tiles: false,
                  enabled: enabled,
                  onMove: (a, b) => moves.add((a, b)),
                );
              },
            ),
          ),
        ),
      );
      await _settle(tester);
      final g = await tester.startGesture(
        _pinTip(tester) - const Offset(0, 20),
      );
      await g.moveBy(const Offset(10, 10));
      await g.moveBy(const Offset(10, 10));
      await tester.pump();
      final before = moves.length;
      expect(before, greaterThan(0));
      // « Utiliser ma position » tapped with another finger.
      set(() => enabled = false);
      await tester.pump();
      await g.moveBy(const Offset(20, 20));
      await tester.pump();
      await g.up();
      await _settle(tester);
      expect(moves.length, before, reason: 'no move once the map is off');
    });

    testWidgets('a pin typed back to the last tapped spot is gone to', (
      tester,
    ) async {
      await _openPosition(
        tester,
        _Admin(profile: 'retail', lat: _ouaga.$1, lng: _ouaga.$2),
      );
      await tester.tapAt(_mapCentre(tester) + const Offset(40, 30));
      await _settle(tester);
      final lat = tester
          .widget<TextField>(find.byKey(const Key('position-lat')))
          .controller!
          .text;
      final lng = tester
          .widget<TextField>(find.byKey(const Key('position-lng')))
          .controller!
          .text;
      await tester.enterText(find.byKey(const Key('position-lat')), '14.0');
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('position-lat')), lat);
      await tester.enterText(find.byKey(const Key('position-lng')), lng);
      await _settle(tester);
      expect(
        _cameraOf(tester).center.latitude,
        closeTo(double.parse(lat), 1e-6),
      );
    });

    for (final (w, h, text) in const [
      (390.0, 844.0, 1.0),
      (320.0, 640.0, 1.3),
    ]) {
      testWidgets('the street\'s map carries the credit, above the cards '
          '(${w.toInt()} × $text)', (tester) async {
        await _size(tester, w, h, text: text);
        await tester.pumpWidget(
          MaterialApp(
            home: DirectoryMapPage(
              entries: const [
                DirectoryEntry(
                  orgId: 'o1',
                  name: 'Boutique Awa',
                  slug: 'awa',
                  profile: 'retail',
                  lat: 12.3714,
                  lng: -1.5197,
                ),
              ],
              previews: const {},
              fallback: const LatLng(12.3714, -1.5197),
              onOpen: (_) {},
              onDirections: (_) {},
              tiles: false,
            ),
          ),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        final credit = tester.getRect(find.byKey(const Key('osm-credit')));
        final strip = tester.getRect(find.byType(PageView));
        expect(credit.right, lessThanOrEqualTo(w));
        expect(credit.left, greaterThanOrEqualTo(0));
        expect(credit.bottom, lessThan(h - 148), reason: 'above the strip');
        expect(credit.bottom, lessThan(strip.top), reason: 'no card covers it');
        expect(credit.height, greaterThanOrEqualTo(12), reason: 'legible');
        // It is hit, not the card or the map under it.
        final hit = tester.hitTestOnBinding(credit.center);
        expect(hit.path.any((e) => e.target is RenderParagraph), isTrue);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Screenshots (B145_SHOTS=<dir>)
  // -------------------------------------------------------------------------
  final shots = Platform.environment['B145_SHOTS'];
  group('screenshots', () {
    Future<void> realFonts() async {
      var dir = File(Platform.resolvedExecutable).parent;
      for (
        var i = 0;
        i < 6 && !Directory('${dir.path}/material_fonts').existsSync();
        i++
      ) {
        dir = dir.parent;
      }
      final fonts = Directory('${dir.path}/material_fonts');
      if (!fonts.existsSync()) return;
      final loader = FontLoader('Roboto');
      for (final f in const [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]) {
        final file = File('${fonts.path}/$f');
        if (file.existsSync()) {
          loader.addFont(
            Future.value(ByteData.view(file.readAsBytesSync().buffer)),
          );
        }
      }
      await loader.load();
      final icons = File('${fonts.path}/MaterialIcons-Regular.otf');
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.view(icons.readAsBytesSync().buffer)),
            ))
            .load();
      }
    }

    Future<void> shoot(WidgetTester tester, String name) async {
      await _settle(tester);
      await tester.runAsync(() async {
        final ro = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('shot')).first,
        );
        final img = await ro.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    final sizes = [('390', 390.0, 844.0, 1.0), ('320x1.3', 320.0, 640.0, 1.3)];
    for (final lang in ['fr', 'en']) {
      for (final (tag, w, h, text) in sizes) {
        testWidgets('$lang $tag', (tester) async {
          Directory(shots!).createSync(recursive: true);
          await tester.runAsync(realFonts);
          final p = '${lang}_${tag}_';

          await _openPosition(
            tester,
            _Admin(profile: 'retail', lat: _ouaga.$1, lng: _ouaga.$2),
            lang: lang,
            w: w,
            h: h,
            text: text,
          );
          await shoot(tester, '${p}01_shop_before');
          await tester.drag(
            find.byKey(const Key('pin-picker-pin')),
            const Offset(70, 50),
          );
          await shoot(tester, '${p}02_shop_after_drag');
          await _reach(tester, find.byKey(const Key('position-lat')));
          await shoot(tester, '${p}03_shop_fields');

          await tester.pumpWidget(const SizedBox());
          await _openPosition(
            tester,
            _Admin(profile: 'farm', phone: '+22670123456'),
            lang: lang,
            w: w,
            h: h,
            text: text,
          );
          await shoot(tester, '${p}04_farm_no_position');
          await tester.tapAt(_mapCentre(tester));
          await shoot(tester, '${p}05_farm_placed');

          await tester.pumpWidget(const SizedBox());
          await _openPosition(
            tester,
            _Admin(profile: 'association', lat: 40.757953, lng: -74.191392),
            lang: lang,
            w: w,
            h: h,
            text: text,
          );
          await _reach(tester, find.byKey(const Key('pin-picker-misplaced')));
          await shoot(tester, '${p}06_association_misplaced');
        });
      }
    }
  }, skip: shots == null ? 'B145_SHOTS=<dir> writes the screenshots' : null);
}

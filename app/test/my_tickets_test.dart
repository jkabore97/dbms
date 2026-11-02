import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/events/my_tickets.dart';
import 'package:kaj_app/core/events/tickets_repository.dart';
import 'package:kaj_app/features/storefront/my_tickets_screens.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ticket sales, part 4: the buyer's tickets on the phone — kept with no
/// account, their last look read with no signal, the slim bar over the
/// street (« Dans 3 j », then « Aujourd'hui » in green), and « Mes billets »
/// drawing each QR on the phone itself.
final _now = DateTime(2026, 11, 2, 10);

MyTickets _concert({String status = 'paid', DateTime? at}) => MyTickets.fromJson({
      'id': '0c0ffee0-0000-4000-8000-0000000000a1',
      'slug': 'concert-fatim-ab12',
      'title': 'Concert Fatim',
      'status': status,
      'ref': 'MK-3F9A2',
      'starts_at': (at ?? DateTime(2026, 11, 5, 20)).toUtc().toIso8601String(),
      'date_fr': 'jeudi 5 novembre à 20 h',
      'place': 'CENASA',
      'tickets': status == 'paid'
          ? [
              {'id': '0c0ffee0-0000-4000-8000-0000000000b1', 'type': 'VIP', 'holder': 'Tanti Rose', 'status': 'valid'},
              {'id': '0c0ffee0-0000-4000-8000-0000000000b2', 'type': 'VIP', 'holder': 'Tanti Rose', 'status': 'used'},
            ]
          : [],
    });

class _Store extends MyTicketsStore {
  _Store(this.list) : super(null, null);

  List<MyTickets> list;
  final kept0 = <String>[];

  @override
  Future<void> keep(String requestId) async => kept0.add(requestId);

  @override
  Future<List<MyTickets>> kept({DateTime? now}) async => list;

  @override
  Future<List<MyTickets>> refresh({DateTime? now}) async => list;
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    home: home,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  test('kept with no account; the last look read with no signal; a past event leaves', () async {
    final db = await LocalDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    final store = MyTicketsStore(null, db);
    await store.keep('0C0FFEE0-0000-4000-8000-0000000000A1');
    expect(jsonDecode((await db.readPref('tickets.ids'))!), ['0c0ffee0-0000-4000-8000-0000000000a1']);
    await db.writePref('tickets.kept', jsonEncode([_concert().toJson(), _concert(at: DateTime(2026, 10, 1)).toJson()]));
    final kept = await store.kept(now: _now);
    expect(kept.length, 1, reason: 'last month’s concert is gone');
    expect(kept.single.tickets.length, 2);
    expect((await store.refresh(now: _now)).single.title, 'Concert Fatim', reason: 'no server: the last look');
  });

  testWidgets('no ticket: no bar', (tester) async {
    await _pump(tester, Scaffold(body: StreetTicketsBar(store: _Store(const []), now: () => _now)));
    expect(find.byKey(const Key('street-tickets-bar')), findsNothing);
  });

  testWidgets('the bar: the next event and how far off; a tap opens the QR codes, drawn on the phone', (tester) async {
    await _pump(tester, Scaffold(body: StreetTicketsBar(store: _Store([_concert()]), now: () => _now)));
    expect(find.text('Concert Fatim · Dans 3 j'), findsOneWidget);
    await tester.tap(find.byKey(const Key('street-tickets-bar')));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget, reason: 'the valid ticket; the used one says so');
    expect(find.text('Déjà utilisé'), findsOneWidget);
    expect(find.text('Billet 1 · VIP'), findsOneWidget);
  });

  testWidgets('the day itself: « Aujourd’hui », in green', (tester) async {
    await _pump(tester, Scaffold(body: StreetTicketsBar(store: _Store([_concert(at: DateTime(2026, 11, 2, 20))]), now: () => _now)));
    expect(find.text('Concert Fatim · Aujourd’hui'), findsOneWidget);
    final bar = tester.widget<Material>(find.byKey(const Key('street-tickets-bar')));
    expect(bar.color, const Color(0xFF1E7B3A));
  });

  testWidgets('/billets/<id>: the request kept first; waiting, it says so and opens its page', (tester) async {
    final store = _Store([_concert(status: 'pending')]);
    final opened = <Uri>[];
    await _pump(tester, MyTicketsScreen(store: store, keepId: '0c0ffee0-0000-4000-8000-0000000000a1', now: () => _now,
        open: (u) async => opened.add(u)));
    expect(store.kept0, ['0c0ffee0-0000-4000-8000-0000000000a1']);
    expect(find.text('En attente de paiement · MK-3F9A2'), findsOneWidget);
    await tester.tap(find.text('En attente de paiement · MK-3F9A2'));
    await tester.pumpAndSettle();
    expect(opened.single.path, '/e/concert-fatim-ab12/billets/0c0ffee0-0000-4000-8000-0000000000a1');
  });
}

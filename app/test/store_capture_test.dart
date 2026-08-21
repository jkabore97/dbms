import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/l10n/strings.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/features/retail/store_home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The camera button is either there and works, or is not drawn at all.
///
/// There is no third state, and this file is why. A build made before the
/// upload Worker had a URL compiles perfectly and would happily draw a camera
/// button that can never send anything — and a button that does nothing
/// teaches people the app is broken, which is a more expensive lesson than a
/// missing feature.
///
/// `flutter analyze` cannot catch that: both states type-check.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  late LocalDb db;
  late SupabaseClient client;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
    // Never asked to do anything: constructing one makes no request, and it
    // is what `isConfigured` needs to be true without a server. Disposed
    // after each case because it arms a token-refresh timer on construction
    // and a widget test refuses to end with one pending.
    client = SupabaseClient('https://example.supabase.co', 'sb_publishable_test');
  });

  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  const org = OrgSummary(
    id: '00000000-0000-0000-0000-000000000001',
    name: 'Boutique Esperance',
    slug: 'boutique-esperance',
    profile: 'retail',
    roles: ['owner'],
    currency: 'XOF',
  );

  Future<void> pump(WidgetTester tester, CaptureRepository capture) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: StoreHomeScreen(org: org, capture: capture),
    ));
    await tester.pump();
  }

  testWidgets('with no upload Worker configured there is no camera at all',
      (tester) async {
    await pump(tester, CaptureRepository(client, db: db));

    expect(find.widgetWithText(FloatingActionButton, 'Photo'), findsNothing);
    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
  });

  testWidgets('configured, the camera is the primary action', (tester) async {
    await pump(
      tester,
      CaptureRepository(
        client,
        db: db,
        uploadsUrl: 'https://kaj-uploads.example.workers.dev',
      ),
    );

    // This shop has no till button wired in (no retail repository), so the
    // camera is the only action and stays the big labelled one. When a shop
    // has both, the sale is the headline and the camera becomes the small
    // round companion above it — see the FAB in store_home_screen.dart.
    expect(find.widgetWithText(FloatingActionButton, 'Photo'), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);

    // And the way back to what has already been photographed.
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
  });

  testWidgets('with a till and a camera, the sale is the headline button',
      (tester) async {
    // A real shop has both. The sale is the big labelled button she reaches
    // for all day; the camera becomes the small round companion above it.
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: StoreHomeScreen(
        org: org,
        retail: RetailRepository(client),
        capture: CaptureRepository(
          client,
          db: db,
          uploadsUrl: 'https://kaj-uploads.example.workers.dev',
        ),
      ),
    ));
    await tester.pump();

    // The sale is extended and labelled — the obvious action.
    expect(find.widgetWithText(FloatingActionButton, 'Vente'), findsOneWidget);
    expect(find.byIcon(Icons.point_of_sale), findsOneWidget);

    // The camera is still there, but now the small icon-only one: no label.
    expect(find.widgetWithText(FloatingActionButton, 'Photo'), findsNothing);
    expect(find.byIcon(Icons.photo_camera), findsOneWidget);
  });

  testWidgets('a build with no server draws neither button', (tester) async {
    // Null client: the whole app is offline-only, and every screen behind
    // both buttons is a server query.
    await pump(tester, CaptureRepository(null, db: db));

    expect(find.widgetWithText(FloatingActionButton, 'Photo'), findsNothing);
    expect(find.byIcon(Icons.point_of_sale), findsNothing);
  });
}

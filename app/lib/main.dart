import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/db/local_db.dart';
import 'core/sync/sync_service.dart';
import 'features/church/church_home_screen.dart';

/// Supplied at build time so no credentials live in the source:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
///
/// Supabase renamed the anon key to the publishable key. Both the legacy
/// `eyJ...` anon key and a new `sb_publishable_...` key work here.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  // The local database opens first and the UI runs from it. If Supabase is
  // unreachable, the app still works completely — that is the whole point.
  final db = await LocalDb.open();

  SyncService? sync;
  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
    sync = SyncService(db, Supabase.instance.client)..start();
  }

  runApp(KajApp(db: db, sync: sync));
}

class KajApp extends StatelessWidget {
  const KajApp({super.key, required this.db, this.sync});

  final LocalDb db;
  final SyncService? sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaj',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E5E4E)),
        useMaterial3: true,
        // Larger default text: many users are reading on cheap phones in
        // poor light, sometimes without reading glasses.
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16),
          bodyLarge: TextStyle(fontSize: 18),
        ),
      ),
      home: ChurchHomeScreen(
        db: db,
        // TODO: replace with the org resolved from the signed-in user's
        // membership once the login flow lands.
        orgId: '22222222-2222-2222-2222-222222222222',
        orgName: 'Grace Chapel',
      ),
    );
  }
}

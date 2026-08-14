import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_root.dart';
import 'core/accounting/accounting_repository.dart';
import 'core/admin/admin_repository.dart';
import 'core/auth/auth_repository.dart';
import 'core/capture/capture_repository.dart';
import 'core/console/console_repository.dart';
import 'core/db/local_db.dart';
import 'core/farm/farm_repository.dart';
import 'core/invoicing/invoicing_repository.dart';
import 'core/onboarding/onboarding_repository.dart';
import 'core/retail/retail_repository.dart';
import 'core/retail/staff.dart';
import 'core/reports/reports_repository.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/kaj_theme.dart';

/// Supplied at build time so no credentials live in the source:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
///
/// Supabase renamed the anon key to the publishable key. Both the legacy
/// `eyJ...` anon key and a new `sb_publishable_...` key work here.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Where photographs go: the origin of the upload Worker (workers/uploads),
/// e.g. `https://kaj-uploads.kabore-boss.workers.dev`.
///
/// Empty in a build made before that Worker was deployed, and the camera
/// button is then hidden rather than shown and failing. A button that does
/// nothing teaches people the app is broken.
const uploadsUrl = String.fromEnvironment('UPLOADS_URL');

Future<void> main() async {
  // Anything thrown before `runApp` leaves the browser showing a blank white
  // page with the reason buried in the console. Catch it and put it on screen.
  try {
    await _startup();
  } catch (error, stack) {
    runApp(StartupErrorApp(error: error, stack: stack));
  }
}

Future<void> _startup() async {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite talks to a native plugin that does not exist in a browser. On web
  // the factory is swapped for the wasm/IndexedDB one before anything opens a
  // database; every call in LocalDb goes through the global factory, so this
  // single line is all the platform difference there is.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  await initializeDateFormatting('fr_FR', null);

  // The local database opens first and the UI runs from it. If Supabase is
  // unreachable, the app still works completely — that is the whole point.
  final db = await LocalDb.open();

  SupabaseClient? client;
  SyncService? sync;
  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      // The session is written to device storage and reloaded on launch, so a
      // phone that has been out of range for a fortnight still knows who its
      // owner is. Refreshing that session needs signal; the device PIN covers
      // the stretch where there is none.
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
    );
    client = Supabase.instance.client;
    // Started by AppRoot once someone is actually signed in — draining the
    // outbox before then would post entries with no author.
    sync = SyncService(db, client);
  }

  runApp(KajApp(
    db: db,
    auth: AuthRepository(client),
    admin: AdminRepository(client),
    reports: ReportsRepository(client),
    accounting: AccountingRepository(client),
    console: ConsoleRepository(client),
    farm: FarmRepository(client),
    invoicing: InvoicingRepository(client),
    retail: RetailRepository(client),
    staff: StaffRepository(client),
    capture: CaptureRepository(client, db: db, uploadsUrl: uploadsUrl),
    onboarding: OnboardingRepository(client),
    sync: sync,
  ));
}

/// Shown instead of a white page when the app cannot start. It is deliberately
/// plain — it must not depend on anything that could itself have failed.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFDECEA),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "L'application n'a pas pu démarrer",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8C1D18),
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  '$error',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: Color(0xFF410E0B),
                  ),
                ),
                if (stack != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    '$stack',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF5F3A38),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KajApp extends StatelessWidget {
  const KajApp({
    super.key,
    required this.db,
    required this.auth,
    required this.admin,
    required this.reports,
    required this.accounting,
    required this.console,
    required this.farm,
    required this.invoicing,
    required this.retail,
    required this.staff,
    required this.capture,
    required this.onboarding,
    this.sync,
  });

  final LocalDb db;
  final AuthRepository auth;
  final AdminRepository admin;
  final ReportsRepository reports;
  final AccountingRepository accounting;
  final ConsoleRepository console;
  final FarmRepository farm;
  final InvoicingRepository invoicing;
  final RetailRepository retail;
  final StaffRepository staff;
  final CaptureRepository capture;
  final OnboardingRepository onboarding;
  final SyncService? sync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaj',
      debugShowCheckedModeBanner: false,
      // The app's own colours, for everything that belongs to no business:
      // signing in, the business picker, the platform console. Each business
      // then repaints itself in its profile's palette — see ProfileTheme.
      theme: kajTheme(kajPalette),
      // No org is named anywhere in this file, and none ever should be. Which
      // business opens is decided by the signed-in user's memberships.
      home: AppRoot(
        db: db,
        auth: auth,
        admin: admin,
        reports: reports,
        accounting: accounting,
        console: console,
        farm: farm,
        invoicing: invoicing,
        retail: retail,
        staff: staff,
        capture: capture,
        onboarding: onboarding,
        sync: sync,
      ),
    );
  }
}

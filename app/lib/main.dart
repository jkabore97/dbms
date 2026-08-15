import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/nav/app_scope.dart';
import 'core/nav/router.dart';
import 'core/nav/session.dart';
import 'core/nav/url_strategy.dart';
import 'core/accounting/accounting_repository.dart';
import 'core/admin/admin_repository.dart';
import 'core/auth/auth_repository.dart';
import 'core/capture/capture_repository.dart';
import 'core/console/console_repository.dart';
import 'core/db/local_db.dart';
import 'core/farm/farm_repository.dart';
import 'core/invoicing/invoicing_repository.dart';
import 'core/l10n/locale_controller.dart';
import 'l10n/strings.dart';
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

  // Addresses without a `#`. A no-op on Android, which has no address bar.
  // Must run before the first frame, or the first URL is written in the old
  // form and the one after it in the new one.
  useCleanUrls();

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
    // Started by the session once someone is actually signed in — draining
    // the outbox before then would post entries with no author.
    sync = SyncService(db, client);
  }

  // Loaded before runApp so the first frame is already in the right
  // language. A screen that flashes French before switching teaches somebody
  // the setting did not work.
  final locale = LocaleController(db);
  await locale.load();

  runApp(KajApp(
    locale: locale,
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

class KajApp extends StatefulWidget {
  const KajApp({
    super.key,
    this.locale,
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

  /// Null in tests that do not care about language; the app then behaves
  /// exactly as before this existed — French, not switchable.
  final LocaleController? locale;

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
  State<KajApp> createState() => _KajAppState();
}

class _KajAppState extends State<KajApp> {
  late final SessionController _session;
  late final GoRouter _router;
  late final LocaleController _locale;

  @override
  void initState() {
    super.initState();
    _locale = widget.locale ?? LocaleController(widget.db);
    _session = SessionController(
      db: widget.db,
      auth: widget.auth,
      admin: widget.admin,
      accounting: widget.accounting,
      sync: widget.sync,
    );
    _router = buildRouter(_session);
    // Kicks the state machine off. The router is already listening, so the
    // first phase it settles on is the first address the person sees.
    _session.boot();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The repositories sit above the router rather than being threaded through
    // constructors: a route builder is called by the router with nothing but
    // the URL, so it has no parent to be handed them by.
    return AppScope(
      session: _session,
      localeController: _locale,
      db: widget.db,
      auth: widget.auth,
      admin: widget.admin,
      reports: widget.reports,
      accounting: widget.accounting,
      console: widget.console,
      farm: widget.farm,
      invoicing: widget.invoicing,
      retail: widget.retail,
      staff: widget.staff,
      capture: widget.capture,
      onboarding: widget.onboarding,
      sync: widget.sync,
      // Rebuilds when the language changes — that is the whole trick: every
      // screen below re-reads Strings.of(context) and repaints in the new
      // language with nothing reloaded and nothing lost.
      child: ListenableBuilder(
        listenable: _locale,
        builder: (context, _) => MaterialApp.router(
          onGenerateTitle: (context) => Strings.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          // The app's own colours, for everything that belongs to no business:
          // signing in, the business picker, the platform console. Each
          // business then repaints itself in its profile's palette — see
          // ProfileTheme.
          theme: kajTheme(kajPalette),
          locale: _locale.effective,
          supportedLocales: enabledLocales,
          localizationsDelegates: const [
            Strings.delegate,
            // Fallbacks first: a delegate list is searched in order, and these
            // answer only for the draft locales Material has never heard of.
            MaterialFallbackDelegate(),
            WidgetsFallbackDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // No org is named anywhere in this file, and none ever should be.
          // Which business opens is decided by the signed-in user's
          // memberships; the URL only says which of those to show.
          routerConfig: _router,
        ),
      ),
    );
  }
}

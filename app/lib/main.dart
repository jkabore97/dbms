import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/storefront/hidden_vitrines.dart';
import 'core/auth/two_step.dart';
import 'core/nav/app_scope.dart';
import 'core/nav/back_first.dart';
import 'core/nav/router.dart';
import 'core/nav/session.dart';
import 'core/nav/url_strategy.dart';
import 'core/accounting/accounting_repository.dart';
import 'core/analytics/analytics_repository.dart';
import 'core/admin/admin_repository.dart';
import 'core/auth/auth_callback.dart';
import 'core/auth/auth_repository.dart';
import 'core/capture/capture_repository.dart';
import 'core/console/console_repository.dart';
import 'core/credit/credit_repository.dart';
import 'core/db/local_db.dart';
import 'core/farm/farm_repository.dart';
import 'core/invoicing/invoicing_repository.dart';
import 'core/l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'core/onboarding/onboarding_repository.dart';
import 'core/notify/notifications_repository.dart';
import 'core/notify/push_client.dart';
import 'core/notify/push_setup.dart';
import 'features/notify/push_prompt.dart';
import 'core/observability/crash_reporting.dart';
import 'core/production/production_repository.dart';
import 'core/retail/retail_repository.dart';
import 'core/retail/staff.dart';
import 'core/reports/reports_repository.dart';
import 'core/pay/wave_pay.dart';
import 'core/access/store_rules.dart' show storeBillingPlatform;
import 'features/pro/store_billing_plugin.dart' deferred as store_plugin;
import 'features/pro/store_watcher.dart';
import 'core/security/security_repository.dart';
import 'core/security/security_settings.dart';
import 'core/sync/sync_service.dart';
import 'core/tontine/tontine_repository.dart';
import 'core/theme/kaj_theme.dart';
import 'core/site/server_url.dart';
import 'core/update/update_banner.dart';
import 'core/update/update_check.dart';
import 'core/terms/terms.dart';
import 'features/account/terms_gate.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Supplied at build time so no credentials live in the source:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
///
/// Supabase renamed the anon key to the publishable key. Both the legacy
/// `eyJ...` anon key and a new `sb_publishable_...` key work here.
final supabaseUrl = supabaseOrigin(const String.fromEnvironment('SUPABASE_URL'));
const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Where photographs go: the origin of the upload Worker (workers/uploads),
/// e.g. `https://kaj-uploads.kabore-boss.workers.dev`.
///
/// Empty in a build made before that Worker was deployed, and the camera
/// button is then hidden rather than shown and failing. A button that does
/// nothing teaches people the app is broken.
const uploadsUrl = String.fromEnvironment('UPLOADS_URL');

/// The origin of the account Worker (workers/account-admin), e.g.
/// `https://kaj-account.kabore-boss.workers.dev`. Empty in a build made before
/// that Worker was deployed, and the admin password-reset and delete-account
/// actions are then hidden rather than shown and failing — the same posture as
/// the camera above. Role change and remove-from-business need no Worker and
/// are always available.
const accountAdminUrl = String.fromEnvironment('ACCOUNT_ADMIN_URL');

/// The app's own version, for the crash reporter's release tag. Kept in one
/// place next to pubspec's `version:` — bump both together
/// (test/batch125_test.dart fails when they differ).
const appVersion = '1.0.0';

Future<void> main() => CrashReporting.run(_boot, version: appVersion);

Future<void> _boot() async {
  // Anything thrown before `runApp` leaves the browser showing a blank white
  // page with the reason buried in the console. Catch it and put it on
  // screen — and tell the reporter, because a startup failure is the one
  // error no user can describe.
  try {
    await _startup();
  } catch (error, stack) {
    await CrashReporting.report(error, stack);
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
  // Opened while Supabase starts: the two do not depend on each other, and
  // on the web the database's engine is itself a download.
  final opening = LocalDb.open();

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
      //
      // PKCE only (SEC_AUDIT_2 M3): a link signs this device in only with
      // the `code` of a sign-in this device started — never with a raw
      // access_token / refresh_token somebody put in a link
      // (core/auth/auth_callback.dart). Google's return and an e-mail
      // confirmation asked from here both come back with that code.
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
        authFlowType: AuthFlowType.pkce,
        detectSessionInUriPredicate: isPkceAuthCallback,
      ),
    );
    client = Supabase.instance.client;
  }
  final db = await opening;
  // The vitrines this phone hid (150), read once now: the street and the
  // vitrines know them at once, never waiting on the device to draw.
  unawaited(HiddenVitrines(db).list());
  if (client != null) {
    // Started by the session once someone is actually signed in — draining
    // the outbox before then would post entries with no author.
    sync = SyncService(db, client);
  }

  // Loaded before runApp so the first frame is already in the right
  // language. A screen that flashes French before switching teaches somebody
  // the setting did not work.
  final locale = LocaleController(db);
  await locale.load();
  // Whether the person switched « Notifications sur ce téléphone » off (122).
  await PushSetup.load(db);

  runApp(KajApp(
    locale: locale,
    db: db,
    auth: AuthRepository(
      client,
      authUrl: client == null ? null : '$supabaseUrl/auth/v1',
      apiKey: client == null ? null : supabasePublishableKey,
    ),
    admin: AdminRepository(client, accountAdminUrl: accountAdminUrl),
    reports: ReportsRepository(client),
    accounting: AccountingRepository(client),
    console: ConsoleRepository(client),
    farm: FarmRepository(client),
    invoicing: InvoicingRepository(client),
    retail: RetailRepository(client,
        outbox: db, onQueued: () => unawaited(sync?.syncNow())),
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
                Text(
                  context.tr('L\'application n\'a pas pu démarrer'),
                  style: const TextStyle(
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
    this.twoStep,
    this.terms,
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

  /// The platform admin's second step (077). Built from [auth] when not
  /// given; tests give a fake.
  final TwoStep? twoStep;

  /// What the person still has to accept (142); built from [auth] when
  /// not given; tests give a fake.
  final TermsApi? terms;

  @override
  State<KajApp> createState() => _KajAppState();
}

class _KajAppState extends State<KajApp> with WidgetsBindingObserver {
  late final SessionController _session;
  late final GoRouter _router;
  late final LocaleController _locale;

  /// Whether a newer build is out (core/update). One look at start, then
  /// every six hours while the app stays open — a shop's tab or a courier's
  /// phone does stay open — so the banner reaches people who never reload.
  late final UpdateCheck _update;
  Timer? _updateTimer;

  /// Keeps an open app current (SessionController.refresh): what the server
  /// says about this person is re-read every few minutes and whenever the
  /// app comes back to the foreground, so a change made on another phone or
  /// in the console arrives without a restart.
  Timer? _refreshTimer;

  /// The lock (Compte › Sécurité): when the app went to the background, and
  /// the choices that say how long it may stay there before the code is
  /// asked again.
  late final SecuritySettings _security = SecuritySettings(widget.db);
  late final SecurityRepository _securityApi =
      SecurityRepository(widget.auth.client);
  late final WavePay _wavePay = WavePay(widget.auth.client);

  /// The Conditions d'utilisation to accept before anything else (142,
  /// batch 147): followed from the session, drawn by TermsGate over the
  /// whole app.
  late final TermsController _terms = TermsController(
    api: widget.terms ?? SupabaseTermsApi(widget.auth.client),
    platform: TermsController.platformName(),
    appVersion: buildSha.isEmpty
        ? appVersion
        : '$appVersion+${buildSha.length > 7 ? buildSha.substring(0, 7) : buildSha}',
    // A few seconds of « loading » at most before the business screens,
    // while the server says whether the gate is due (fails open).
    holdFor: widget.terms != null || widget.auth.isConfigured
        ? const Duration(seconds: 3)
        : Duration.zero,
  );

  /// The gate's own navigator: Android's back closes what it opened, and
  /// never the router's pages hidden under it (147).
  final _termsNavigator = GlobalKey<NavigatorState>(debugLabel: 'terms-gate');
  Future<bool?> _termsBack() => TermsGate.handleBack(_terms, _termsNavigator);

  /// The store builds' purchase listener (130, review S3): every purchase
  /// the App Store or Google Play reports from the app's start — not only
  /// while the Pro page is open — verified for the business it was bought
  /// for. Null on the web and the GitHub APK.
  StoreWatcher? _storeWatcher;
  DateTime? _awayAt;
  bool _deviceRegistered = false;

  /// The bell, once for the app (115): its live counts (notify.bell) are
  /// shared by every bell and every bar, so it is never rebuilt.
  late final NotificationsRepository _notify =
      NotificationsRepository(widget.auth.client);
  StreamSubscription<String>? _pushTaps;

  /// « Activer les notifications ? » at each opening (120), over the
  /// router's own navigator.
  late final PushPrompt _pushPrompt = PushPrompt(
    device: AppPushDevice(_notify),
    context: () => _router.routerDelegate.navigatorKey.currentContext,
  );

  /// Somebody is in, and no gate (the code, the second step) stands in
  /// front: a shopper or a courier (noOrg) as much as a member.
  bool get _signedIn =>
      _session.phase == SessionPhase.noOrg ||
      _session.phase == SessionPhase.picking ||
      _session.phase == SessionPhase.ready;

  void _onSession() {
    // The terms: asked of whoever is in, forgotten at sign-out (142).
    if (_session.phase == SessionPhase.signedOut) {
      _terms.clear();
    } else {
      unawaited(_terms.track(_signedIn ? _session.identity?.userId : null));
    }
    if (_session.phase == SessionPhase.signedOut) _pushPrompt.signedOut();
    _pushPrompt.phase(signedIn: _signedIn);
    if (_session.phase == SessionPhase.ready) unawaited(_storeWatcher?.recoverSpots());
    if (_session.phase != SessionPhase.ready || _deviceRegistered) return;
    _deviceRegistered = true;
    unawaited(() async {
      final id = await _security.deviceId();
      await _securityApi.registerDevice(id, SecuritySettings.deviceLabel());
      // A device already allowed but missing from the book is written back
      // (115) — silently, nothing is asked.
      await PushSetup.ensure(_notify);
      _security.setPolicy(await _securityApi.lockPolicy());
    }());
  }

  @override
  void initState() {
    super.initState();
    unawaited(_security.load());
    _update = UpdateCheck(
      fetch: (uri) async => (await http.get(uri)).body,
    );
    unawaited(_update.check());
    _updateTimer = Timer.periodic(
        const Duration(hours: 6), (_) => unawaited(_update.check()));
    _locale = widget.locale ?? LocaleController(widget.db);
    _session = SessionController(
      db: widget.db,
      auth: widget.auth,
      admin: widget.admin,
      accounting: widget.accounting,
      sync: widget.sync,
      twoStep: widget.twoStep ??
          (widget.auth.isConfigured ? TwoStep(widget.auth.client) : null),
    );
    _router = buildRouter(_session);
    // Before the router is first drawn: the back and the browser's history
    // are heard here first (114).
    // From a page with nothing under it, back goes to its parent (122):
    // a business's home to the picker for someone with several.
    BackFirst.instance.attach(_router, businesses: () => _session.orgs.length);
    BackFirst.instance.cover = _termsBack;
    // A tapped push on Android opens what it is about (115).
    _pushTaps = PushClient.opened.listen((path) => _router.push(path));
    // Kicks the state machine off. The router is already listening, so the
    // first phase it settles on is the first address the person sees.
    TermsController.current = _terms;
    _session.addListener(_onSession);
    _session.boot();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(SessionController.refreshEvery,
        (_) => unawaited(_session.refresh(force: true)));
    if (!kIsWeb && storeBillingPlatform != null) unawaited(_startStore(storeBillingPlatform!));
  }

  Future<void> _startStore(String platform) async {
    await store_plugin.loadLibrary();
    if (!mounted) return;
    final watcher = StoreWatcher(
      billing: store_plugin.PluginStoreBilling(platform),
      verify: (p) => _wavePay.verifyStore(
        platform: platform,
        orgId: p.orgId,
        productId: p.productId,
        transactionId: p.transactionId,
        token: p.token,
      ),
      // A spot's purchase (142), verified as a spot: the spot it names.
      // No price is sent: the Worker takes the store's, or Mara's own.
      verifySpot: (p) => _wavePay.verifySpot(
        platform: platform,
        promotionId: p.spotId,
        productId: p.productId,
        transactionId: p.transactionId,
        token: p.token,
      ),
      onPro: () => unawaited(_session.refresh(force: true)),
      // Said and kept: the console's log and the crash reporter — a code
      // and a product, never a token.
      log: (line) {
        debugPrint(line);
        unawaited(CrashReporting.report(StateError(line)));
      },
      outside: (notice) => BackFirst.instance.messenger.currentState?.showSnackBar(
        SnackBar(content: Builder(builder: (context) => Text(notice.text(context)))),
      ),
    )..start();
    setState(() => _storeWatcher = watcher);
    // A spot paid while the connection or the app died: verified again once
    // signed in (Google hands back an unconsumed purchase only when asked).
    if (_session.phase == SessionPhase.ready) unawaited(watcher.recoverSpots());
  }

  /// The phone's language changed while Mara was open: with no choice made
  /// in Compte, the app follows it at once.
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_locale.chosen == null) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _awayAt ??= DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      final away = _awayAt;
      _awayAt = null;
      final lock = _security.effectiveLock;
      if (away != null &&
          lock != null &&
          DateTime.now().difference(away) >= Duration(minutes: lock)) {
        _session.lockNow();
      }
      unawaited(_session.refresh());
      unawaited(_update.check());
      // A new version of the terms reaches an open app (142's bump).
      if (_signedIn) unawaited(_terms.track(_session.identity?.userId));
      if (_signedIn) unawaited(PushSetup.ensure(_notify));
      if (away != null) _pushPrompt.resumed(DateTime.now().difference(away));
      unawaited(() async {
        _security.setPolicy(await _securityApi.lockPolicy());
      }());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_pushTaps?.cancel());
    _pushPrompt.dispose();
    _notify.bell.dispose();
    BackFirst.instance.detach(_router);
    if (BackFirst.instance.cover == _termsBack) BackFirst.instance.cover = null;
    _refreshTimer?.cancel();
    _updateTimer?.cancel();
    _update.dispose();
    _session.removeListener(_onSession);
    _session.dispose();
    _terms.dispose();
    _security.dispose();
    _storeWatcher?.dispose();
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
      // Built here rather than threaded from main(): they wrap the same
      // client every other repository wraps, and widening KajApp's
      // constructor for each new module would make every test pay for it.
      credit: CreditRepository(widget.auth.client),
      tontine: TontineRepository(widget.auth.client),
      production: ProductionRepository(widget.auth.client),
      notify: _notify,
      analytics: AnalyticsRepository(widget.auth.client),
      sync: widget.sync,
      security: _security,
      securityApi: _securityApi,
      wavePay: _wavePay,
      storeWatcher: _storeWatcher,
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
          // The app's wash behind every page. Scaffolds are transparent in
          // the glass theme, so this is the ground they stand on; inside a
          // business, ProfileTheme paints its own wash over this one.
          // The update banner sits above every page, inside the wash, so a
          // phone on an old APK hears about the new one wherever it is.
          // Keyed by the language: changing it rebuilds every page, so the
          // phrases read through context.tr() follow at once.
          builder: (context, child) => KeyedSubtree(
            key: ValueKey(trCurrent = Localizations.localeOf(context).languageCode),
            child: KajBackground(
              palette: kajPalette,
              // The Conditions d'utilisation first (142): over every page,
              // for whoever is signed in and has not accepted them.
              child: TermsScope(
                controller: _terms,
                child: TermsGate(
                  controller: _terms,
                  navigatorKey: _termsNavigator,
                  onSignOut: _session.signOut,
                  child: UpdateBanner(
                    check: _update,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
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
          // Back closes what is open first, in the whole app (114).
          scaffoldMessengerKey: BackFirst.instance.messenger,
          onNavigationNotification: BackFirst.instance.onNavigationNotification,
        ),
      ),
    );
  }
}

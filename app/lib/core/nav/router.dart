import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/mara_mark.dart';
import '../cauris/cauris_repository.dart';
import '../console/command_center.dart';
import 'package:go_router/go_router.dart';
import 'business_screens.dart' deferred as biz;

import '../../core/courier/courier_repository.dart';
import '../../features/orders/my_orders_screen.dart';
import '../../features/account/legal_screens.dart';
import '../../features/auth/join_or_apply_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/no_org_screen.dart';
import '../../features/auth/org_picker_screen.dart';
import '../../features/auth/pin_screen.dart';
import '../../features/auth/profile_form_screen.dart';
import '../../features/storefront/directory_screen.dart';
import '../../features/storefront/storefront_screen.dart';
import '../storefront/storefront_repository.dart';
import '../storefront/street_cache.dart';
import '../auth/whatsapp_phone.dart';
import '../onboarding/business_creation.dart';
import '../../features/pay/payment_screen.dart';
import '../../features/settings/language_screen.dart';
import '../theme/kaj_theme.dart';
import '../accounting/models.dart';
import '../invoicing/models.dart' show InvoiceDocument;
import '../auth/models.dart';
import '../capture/invoice_reading.dart';
import '../capture/models.dart';
import '../retail/models.dart';
import '../../features/account/two_step_screen.dart';
import '../../features/admin/admin_pill.dart' show AdminTrail;
import 'app_scope.dart';
import 'business_cover.dart';
import 'session.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Every screen in the app, and the address it lives at.
///
/// The app used to be one page. Everything happened at `/`, moving between
/// sign-in, the business picker and a business was a `setState`, and screens
/// were pushed imperatively with no name. Three things followed from that, and
/// all three were things a person actually hit:
///
///   * **Back was wrong.** A `setState` leaves nothing in history, so pressing
///     back from inside a business did not return to the picker — it went back
///     past the app and left it.
///   * **A refresh lost your place.** Every reload started again at the
///     beginning, however deep you were.
///   * **Nothing could be linked.** No page could be bookmarked, sent to a
///     colleague, or opened twice in two tabs.
///
/// Now each screen is a real page. The paths are French because the app is,
/// and they are readable on purpose: somebody reading `/o/<id>/factures` in the
/// address bar can tell what they are looking at.
///
/// **An id in a URL grants nothing.** `orgById()` looks the id up in the list
/// `my_orgs()` returned, which is behind RLS, so typing another business's id
/// resolves to nothing and lands on the picker. The URL says where to look; the
/// server still decides what may be seen.
abstract final class Routes {
  static const splash = '/demarrage';
  static const signIn = '/connexion';
  static const pin = '/code';
  static const twoStep = '/deux-etapes';
  static const join = '/rejoindre';
  static const myProfile = '/mon-profil';
  static const picker = '/entreprises';
  static const newBusiness = '/nouvelle-entreprise';
  /// Creating one's own business, at once (111) — from the no-business
  /// screen, the picker, Compte and the shopper's profile.
  static const createBusiness = '/creer-mon-activite';
  static const console = '/console';
  static const platformAnalytics = '/console/analyses';
  static const trainers = '/console/formateurs';
  static const consolePeople = '/console/personnes';
  static const consoleAudit = '/console/activite';
  static const consoleFeatured = '/console/a-la-une';
  static const consoleShowcase = '/console/vitrines-exemple';
  static const myOrders = '/mes-commandes';
  static const courier = '/livreur';
  /// One running course on a map, for its courier.
  static String courierJob(String orderId) => '/livreur/course/$orderId';
  static const consoleCouriers = '/console/livreurs';
  /// Kaj Pro from the platform's side: the queue of "J'ai payé" and the
  /// number and prices the paywall says (066).
  static const consolePro = '/console/kaj-pro';
  /// The platform's gifts (100): cauris, promotional cauris, a tool opened
  /// until a date — for any business.
  static const consoleCaurisGifts = '/console/kaj-pro/cauris';
  /// The platform's Wave switches and every payment with its payout (076).
  static const consoleWave = '/console/wave';
  /// What each courier owes for the month: the platform's part of the
  /// delivery fees (067).
  static const consoleSettlement = '/console/livreurs/reglement';
  static const applications = '/demandes';
  /// The command center's own sections (104): the businesses, one
  /// business's fiche, the types of business, the request page, the
  /// settings and the journal.
  static const consoleBusinesses = '/console/entreprises';
  static String consoleOrg(String orgId) => '/console/entreprises/$orgId';
  static const consoleKinds = '/console/types';
  static const consoleRequestForm = '/demandes/formulaire';
  static const consoleSettings = '/console/reglages';
  static const consoleJournal = '/console/journal';
  static const language = '/langue';
  static const security = '/securite';
  /// Where Wave sends the person back after paying (076): the payment's own
  /// page, which waits for Wave's word and says what happened.
  static const payment = '/paiement';
  static String paymentOf(String id) => '/paiement/$id';
  static const privacy = '/confidentialite';
  static const terms = '/conditions';
  static const faq = '/aide';

  /// A business, and everything inside it.
  static String org(String id) => '/o/$id';

  /// A shop's public vitrine — reachable signed out, by anyone with the link.
  static String storefront(String slug) => '/s/$slug';

  /// Every open vitrine, as a list or a map — the street's front door.
  static const directory = '/vitrines';
  static String inside(String id, String rest) => '/o/$id/$rest';

  /// A business's settings. Named once here: the vitrine card on the shop
  /// home once typed it by hand as `parametres`, lost the `administration/`
  /// in front, and opened a red « Page Not Found ».
  /// [part] opens one rubrique straight away: 'articles', 'identite',
  /// 'vitrine', 'position' (the vitrine guide's « Faire maintenant »).
  static String orgSettings(String id, {String? part}) =>
      inside(id, 'administration/parametres') +
      (part == null ? '' : '?partie=$part');
}

/// Builds the router. Called once, from `main()`.
///
/// [session] is both the source of truth for which phase the app is in and the
/// thing the router listens to: every phase change re-runs the redirect below,
/// which is what turns "signed out" or "no business yet" into an address rather
/// than a screen swapped in behind the user's back.

/// The pages a shopper reaches — the street, a shop, sign-in, their orders,
/// the help and legal pages — built from what the first download carries.
/// Everything else is inside a business and waits for business_screens.dart.
bool _shopperPath(String location) =>
    location == '/' ||
    location.startsWith('/s/') ||
    const [
      Routes.splash,
      Routes.signIn,
      Routes.pin,
      Routes.twoStep,
      Routes.join,
      Routes.myProfile,
      Routes.picker,
      Routes.myOrders,
      Routes.language,
      Routes.payment,
      Routes.privacy,
      Routes.terms,
      Routes.faq,
      Routes.directory,
    ].any((p) => location == p || location.startsWith('$p/'));

Future<bool>? _businessScreens;
bool _businessScreensReady = false;

/// Loads the business half of the app once (web: one more file, the first
/// time somebody opens a business; Android: nothing to fetch). A failed
/// download — the connection dropped — is asked again next time.
Future<bool> _loadBusinessScreens() => _businessScreens ??= () async {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await biz.loadLibrary();
          _businessScreensReady = true;
          return true;
        } catch (_) {
          await Future<void>.delayed(Duration(seconds: 1 + attempt));
        }
      }
      _businessScreens = null;
      return false;
    }();

/// Starts that download early, while a signed-in person is still on the
/// picker or the splash, so opening the business does not wait for it.
void warmBusinessScreens() => unawaited(_loadBusinessScreens());

GoRouter buildRouter(SessionController session) {
  // Somebody with a business will open it: fetch its screens now.
  void warm() {
    if (session.orgs.isNotEmpty) warmBusinessScreens();
  }

  session.addListener(warm);
  warm();
  // On a phone the business half is part of the app already: loading it is
  // immediate, so it is loaded straight away and never waited for.
  if (!kIsWeb) warmBusinessScreens();

  // A sheet or a full-screen flow over a business's pages (108): its bar
  // goes behind it.
  final cover = BusinessCover();

  /// The one place that decides where a person is allowed to be.
  ///
  /// Written as "which locations does this phase permit" rather than a chain of
  /// ifs, because the failure mode of the other shape is a redirect loop — two
  /// rules each sending the user to the other's page, and a white screen.
  String? redirect(BuildContext context, GoRouterState state) {
    final here = state.matchedLocation;

    bool at(String path) => here == path || here.startsWith('$path/');

    // The language screen answers to no phase: the person who most needs it
    // is the one who cannot read whatever screen their phase would show. The
    // static help and legal pages are the same — reachable from Compte while
    // signed in, and from the sign-in page before; a phase-based redirect must
    // not bounce them back to a business the way it does app screens.
    if (at(Routes.language) ||
        at(Routes.faq) ||
        at(Routes.privacy) ||
        at(Routes.terms) ||
        // A shop's vitrine and the directory of them are for the street: the
        // person opening either is a shopper with no account, sent a link on
        // WhatsApp, and must never be bounced to a sign-in page for looking
        // in a shop window.
        at(Routes.directory) ||
        here.startsWith('/s/')) {
      return null;
    }

    // A location worth coming back to after a gate. The gates themselves and
    // the splash are not destinations; everything else is somebody's place.
    bool isDestination() =>
        here != '/' &&
        !at(Routes.splash) &&
        !at(Routes.signIn) &&
        !at(Routes.pin) &&
        !at(Routes.twoStep);

    // A customer's order ring, pushed (060), opens /o/<shop>/commandes —
    // the Worker cannot tell the shop's ring from the customer's. Somebody
    // who is not of that business is a customer there: their own orders.
    if (session.phase == SessionPhase.noOrg ||
        session.phase == SessionPhase.picking ||
        session.phase == SessionPhase.ready) {
      final id = _orgIdOf(here);
      if (id != null &&
          here == Routes.inside(id, 'commandes') &&
          session.orgById(id) == null) {
        return Routes.myOrders;
      }
    }

    switch (session.phase) {
      case SessionPhase.booting:
      case SessionPhase.resolving:
        // Deliberately not redirecting: a resolve happens *while* somebody is
        // already somewhere (a pull-to-refresh, coming back from settings), and
        // throwing them onto a splash screen every time would be a flicker and
        // a lost place. Only a cold start has nowhere to be.
        return here == '/' ? Routes.splash : null;

      case SessionPhase.signedOut:
        if (at(Routes.signIn)) return null;
        // The front door is the street: a fresh visit lands on the welcome
        // page — the vitrines, with "Se connecter" in the corner — not on a
        // gate. Only a deep address still goes through sign-in, below.
        if (here == '/' || at(Routes.splash)) return Routes.directory;
        // Remember where this reload was headed. The sign-in page is a gate,
        // not a destination: once the person is back in, the redirect below
        // returns them here instead of to the home it would otherwise pick.
        if (isDestination()) session.stashReturnTo(here);
        return Routes.signIn;

      case SessionPhase.locked:
      case SessionPhase.choosingPin:
        if (at(Routes.pin)) return null;
        // Same as the sign-in gate: refreshing a deep page on a device with
        // a code must unlock back into that page, not into the home screen.
        if (isDestination()) session.stashReturnTo(here);
        return Routes.pin;

      case SessionPhase.twoStep:
        // A platform admin's second step (077). Like the code screen, a
        // gate: the page it interrupted is given back once it is passed.
        if (at(Routes.twoStep)) return null;
        if (isDestination()) session.stashReturnTo(here);
        return Routes.twoStep;

      case SessionPhase.noOrg:
        // A gate may have interrupted a shopper's or a courier's page — a
        // refresh on /livreur goes through the code screen like any other.
        // Without this, only members got their page back, and everyone
        // else's refresh landed on the street.
        final back = session.takeReturnTo();
        if (back != null && back != here) return back;
        // Belongs to no business yet, so there is no `/o/...` to be at — but
        // the things somebody in that position does need are all reachable.
        if (at(Routes.join) ||
            at(Routes.myProfile) ||
            at(Routes.myOrders) ||
            at(Routes.security) ||
            at(Routes.payment) ||
            at(Routes.courier) ||
            at(Routes.newBusiness) ||
            at(Routes.createBusiness) ||
            at(Routes.console) ||
            at(Routes.applications)) {
          return null;
        }
        // A signed-in person with no business is a shopper: their home is
        // the street. Becoming a seller, or joining a business with a code,
        // is behind the account corner there (Routes.join).
        return Routes.directory;

      case SessionPhase.picking:
        // A gate we just came through may have interrupted a deep address —
        // send the person back to it. If it names a business this account
        // cannot open, the very next redirect pass lands on the picker.
        final interrupted = session.takeReturnTo();
        if (interrupted != null && interrupted != here) return interrupted;
        // A bookmark straight into a business is honoured here rather than
        // bounced to the picker — that is most of the point of having URLs.
        // `openOrg` refuses an id this person has no membership for, and the
        // guard below then sends them to the picker.
        if (here.startsWith('/o/')) {
          final id = _orgIdOf(here);
          if (id != null && session.orgById(id) != null) {
            session.openOrg(id);
            return null;
          }
          return Routes.picker;
        }
        if (at(Routes.picker) ||
            at(Routes.join) ||
            at(Routes.myProfile) ||
            at(Routes.myOrders) ||
            at(Routes.security) ||
            at(Routes.payment) ||
            at(Routes.courier) ||
            at(Routes.newBusiness) ||
            at(Routes.createBusiness) ||
            at(Routes.console) ||
            at(Routes.applications)) {
          return null;
        }
        // The street is home for everyone now, member or not (the owner's
        // words: signed in, you are still on the main page). The business
        // is one tap away behind the boutique button in the corner.
        return Routes.directory;

      case SessionPhase.ready:
        // Same as `picking`: honour the address a gate interrupted, and let
        // the next redirect pass validate whatever it names.
        final resume = session.takeReturnTo();
        if (resume != null && resume != here) return resume;
        if (here.startsWith('/o/')) {
          final id = _orgIdOf(here);
          if (id == null || session.orgById(id) == null) return Routes.picker;
          session.openOrg(id);
          return null;
        }
        if (at(Routes.picker) ||
            at(Routes.join) ||
            at(Routes.myProfile) ||
            at(Routes.myOrders) ||
            at(Routes.security) ||
            at(Routes.payment) ||
            at(Routes.courier) ||
            at(Routes.newBusiness) ||
            at(Routes.createBusiness) ||
            at(Routes.console) ||
            at(Routes.applications)) {
          return null;
        }
        // `/`, the splash, or a stale sign-in URL: the street, like
        // everyone else. The remembered business stays one tap away — the
        // boutique button in the corner opens it directly.
        return Routes.directory;
    }
  }

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: session,
    redirect: (context, state) {
      // The business the center opened is forgotten once it is left
      // another way (104): its strip is never stale.
      AdminTrail.sawLocation(state.uri.path);
      final to = redirect(context, state);
      // Somewhere inside a business: its screens arrive first (business_
      // screens.dart is deferred). A redirect elsewhere comes back through
      // here with the new address, so only the address that stays is asked.
      // Once they are here the answer is immediate, as before.
      if (to == null &&
          !_businessScreensReady &&
          !_shopperPath(state.matchedLocation)) {
        return _loadBusinessScreens()
            .then((ok) => ok ? null : '/chargement-impossible');
      }
      return to;
    },
    // An address that matches nothing — a stale bookmark, a mistyped link —
    // gets a calm page with the way home, never the router's red debug page.
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _Splash()),
      // Reachable from every phase — see the redirect, which never blocks it.
      // The person who most needs this screen is the one who cannot read the
      // sign-in page, so gating it behind sign-in would be absurd.
      GoRoute(
          path: Routes.language, builder: (_, _) => const LanguageScreen()),
      GoRoute(
          path: Routes.security, builder: (_, _) => biz.SecurityScreen()),
      GoRoute(
        path: '${Routes.payment}/:id',
        builder: (_, state) => PaymentScreen(
          paymentId: state.pathParameters['id']!,
          issue: state.uri.queryParameters['issue'],
        ),
      ),
      GoRoute(path: Routes.splash, builder: (_, _) => const _Splash()),

      // The static legal and help pages. Top-level so they open with no signal
      // and can be linked from anywhere, signed in or not.
      GoRoute(path: Routes.privacy, builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: Routes.terms, builder: (_, _) => const TermsScreen()),
      GoRoute(path: Routes.faq, builder: (_, _) => const FaqScreen()),

      // A shop's public vitrine. Top-level and never redirected — see the
      // redirect above — because the person opening it is a shopper with no
      // account, sent the link on WhatsApp. Anonymous reads, by design (052).
      GoRoute(
        path: '/s/:slug',
        builder: (context, state) {
          final scope = AppScope.of(context);
          return StorefrontScreen(
            slug: state.pathParameters['slug'] ?? '',
            // The street's last look on this phone (street_cache.dart):
            // shown at once on a slow line, and all there is with none.
            storefront: StorefrontRepository(scope.auth.client,
                keep: StreetCache(scope.db)),
            capture: scope.capture,
            session: scope.session,
          );
        },
      ),

      // A customer's own orders (055). Needs a signed-in person: the
      // redirect sends a stranger through sign-in and back here.
      GoRoute(
        path: Routes.myOrders,
        builder: (context, state) => MyOrdersScreen(
          storefront: StorefrontRepository(AppScope.of(context).auth.client),
        ),
      ),

      // The livreur's whole world (056): the pitch, the wait, the board and
      // their courses — the server says which of those this person gets.
      GoRoute(
        path: Routes.courier,
        builder: (context, state) => biz.CourierScreen(
          courier: CourierRepository(AppScope.of(context).auth.client),
        ),
      ),
      GoRoute(
        path: '${Routes.courier}/course/:id',
        builder: (context, state) => biz.JobMapScreen(
          orderId: state.pathParameters['id']!,
          courier: CourierRepository(AppScope.of(context).auth.client),
        ),
      ),

      // Every open vitrine: a list, a map, and "près de moi". Public for the
      // same reason as a single vitrine — the shopper has no account.
      GoRoute(
        path: Routes.directory,
        builder: (context, state) {
          final scope = AppScope.of(context);
          return DirectoryScreen(
            storefront: StorefrontRepository(scope.auth.client,
                keep: StreetCache(scope.db)),
            capture: scope.capture,
            session: scope.session,
          );
        },
      ),

      GoRoute(
        path: Routes.signIn,
        builder: (context, state) {
          final scope = AppScope.of(context);
          return LoginScreen(
            auth: scope.auth,
            // « Créer un compte » from a vitrine's sign-in sheet (F1).
            startWithSignUp: state.uri.queryParameters['compte'] == 'nouveau',
            // Lets the sign-up form save the names, date of birth, title and
            // phone it collects, the moment the account exists.
            onboarding: scope.onboarding,
            onSignedIn: scope.session.handleSignedIn,
            onGoogle: scope.session.signInWithGoogle,
            initialError: scope.session.takeSignInProblem(),
          );
        },
      ),

      GoRoute(
        path: Routes.pin,
        builder: (context, _) {
          final scope = AppScope.of(context);
          return _Live(
            session: scope.session,
            builder: () {
              final creating =
                  scope.session.phase == SessionPhase.choosingPin;
              return PinScreen(
                purpose: creating ? PinPurpose.create : PinPurpose.unlock,
                identity: scope.session.identity!,
                onPinAccepted: (pin) => creating
                    ? scope.session.setPin(pin)
                    : scope.session.unlock(),
                onSignOut: scope.session.signOut,
                onBiometric: !creating &&
                        (scope.security?.biometric ?? false) &&
                        (scope.security?.biometricReady ?? false)
                    ? scope.security!.unlockWithBiometrics
                    : null,
              );
            },
          );
        },
      ),

      GoRoute(
        path: Routes.twoStep,
        builder: (context, _) {
          final scope = AppScope.of(context);
          final step = scope.session.twoStep;
          if (step == null) return const _Splash();
          return TwoStepScreen(
            twoStep: step,
            enrolled: scope.session.twoStepEnrolled,
            onPassed: scope.session.twoStepPassed,
            onSignOut: scope.session.signOut,
          );
        },
      ),

      GoRoute(
        path: Routes.join,
        builder: (context, _) {
          final scope = AppScope.of(context);
          // A build with no server, or an expired token, has nothing to check a
          // code against and nothing to file an application with. That case
          // keeps the old screen, which says so and offers a retry.
          // A cold reload can build this page a frame before the session has
          // read the identity off the device; a null-check here was a white
          // screen on refresh. The splash holds the door for that frame —
          // and, through _Live, steps aside when the identity lands.
          return _Live(
            session: scope.session,
            builder: () {
              final identity = scope.session.identity;
              if (identity == null) return const _Splash();
              if (!scope.auth.hasLiveSession) {
                return NoOrgScreen(
                  identity: identity,
                  onRetry: scope.session.resolveOrgs,
                  onSignOut: scope.session.signOut,
                  // The bootstrap case: the person who runs the platform,
                  // before any business exists.
                  onCreateBusiness: scope.session.isPlatformAdmin
                      ? () => context.push(Routes.newBusiness)
                      : null,
                );
              }
              return JoinOrApplyScreen(
                identity: identity,
                onboarding: scope.onboarding,
                admin: scope.admin,
                onRetry: scope.session.resolveOrgs,
                onSignOut: scope.session.signOut,
                checking: scope.session.phase == SessionPhase.resolving,
              );
            },
          );
        },
      ),

      GoRoute(
        path: Routes.picker,
        builder: (context, _) {
          final scope = AppScope.of(context);
          return _Live(
            session: scope.session,
            builder: () => OrgPickerScreen(
              orgs: scope.session.orgs,
              // A cold load lands here mid-resolve with an empty list; show a
              // spinner rather than a blank page until my_orgs() answers —
              // and the list, when it does, through _Live.
              loading: scope.session.phase == SessionPhase.booting ||
                  scope.session.phase == SessionPhase.resolving,
              // The escape hatch if that resolve never returns.
              onRetry: scope.session.resolveOrgs,
              // `push`, not `go`: opening a business is a step *into* the
              // app, so the picker has to stay underneath it. `go` replaces
              // the location, which is what left back with nowhere to return
              // to and dropped people out of the app entirely.
              onSelected: (org) => context.push(Routes.org(org.id)),
              onSignOut: scope.session.signOut,
              onCreateBusiness:
                  scope.session.isPlatformAdmin && scope.auth.hasLiveSession
                      ? () => context.push(Routes.newBusiness)
                      : null,
              // « + Nouvelle activité » (111): everybody else creates their own.
              onCreateMine:
                  !scope.session.isPlatformAdmin && scope.auth.hasLiveSession
                      ? () => context.push(Routes.createBusiness)
                      : null,
            ),
          );
        },
      ),

      /// The profile form, from anywhere. Reachable by everybody and not only
      /// by somebody who has just signed up: this is where a person fixes the
      /// spelling of their own name.
      GoRoute(
        path: Routes.myProfile,
        builder: (context, _) => ProfileFormScreen(
          onboarding: AppScope.of(context).onboarding,
          title: context.tr('Mes informations'),
          nextLabel: 'Enregistrer',
          intro: 'Ces informations vous suivent dans toutes les entreprises '
              'que vous rejoignez. Elles figurent sur un contrat ou un '
              'bulletin de paie.',
        ),
      ),

      /// Creating a business, then opening it. The new org is opened directly
      /// rather than left to the usual count-based routing: a platform admin's
      /// list is every business there is, so making one would otherwise drop
      /// them on the picker to hunt for what they just made.
      GoRoute(
        path: Routes.newBusiness,
        builder: (context, _) =>
            biz.CreateBusinessScreen(admin: AppScope.of(context).admin),
      ),

      /// Creating one's own business, at once (111): no request to approve.
      /// Created, the person is its owner; the next resolve finds it, the
      /// device code is chosen if there is none yet (108: a business is
      /// what it protects), then its home — which holds its first setup.
      /// The splash carries the moment between: it is no destination, so
      /// the code screen gives back the business, not this flow.
      GoRoute(
        path: Routes.createBusiness,
        builder: (context, _) {
          final scope = AppScope.of(context);
          final session = scope.session;
          return biz.CreateMyBusinessScreen(
            api: SupabaseBusinessCreation(scope.auth.client),
            drafts: LocalDraftStore(scope.db, scope.auth.client?.auth.currentUser?.id),
            whatsApp: SupabaseWhatsAppPhone(scope.auth.client),
            onCreated: (orgId) async {
              session.stashReturnTo(Routes.org(orgId));
              final resolved = session.resolveOrgs();
              if (context.mounted) context.go(Routes.splash);
              await resolved;
            },
          );
        },
      ),

      // ----------------------------------------------------------------
      // Mara's command center (104): one shell — the rail on a computer,
      // the bar on a phone, the one search — around every console page.
      // Each page keeps the address it always had; the sections are pages
      // reached with `go`, so they replace one another without a slide,
      // and what a page opens on top (a fiche) is pushed, with a back.
      // ----------------------------------------------------------------
      ShellRoute(
        builder: (context, state, child) => biz.CommandCenterShell(
          center: CommandCenterRepository(AppScope.of(context).auth.client),
          child: child,
        ),
        routes: [
          _centerPage(Routes.console, (context, state) {
            final scope = AppScope.of(context);
            return biz.TodoSection(
              center: CommandCenterRepository(scope.auth.client),
              admin: scope.admin,
            );
          }),
          _centerPage(Routes.consoleBusinesses, (context, state) {
            final scope = AppScope.of(context);
            return biz.PlatformConsoleScreen(
              admin: scope.admin,
              console: scope.console,
              center: CommandCenterRepository(scope.auth.client),
              cauris: CaurisRepository(scope.auth.client),
              onOpen: (org) => context.push(Routes.consoleOrg(org.id)),
              // « Silencieuses (30 j) » from « À faire ».
              initialActivity: state.uri.queryParameters['activite'],
            );
          }),
          // One business's fiche (106's screen).
          GoRoute(
            path: '${Routes.consoleBusinesses}/:orgId',
            builder: (context, state) => biz.BusinessFicheScreen(
              orgId: state.pathParameters['orgId']!,
              initialTab: state.uri.queryParameters['onglet'],
            ),
          ),
          // The types of business and the request page (107's screens).
          _centerPage(Routes.consoleKinds, (_, _) => biz.KindModelsScreen()),
          // « Activités créées » (111): what « Demandes » was.
          _centerPage(Routes.applications, (context, _) => biz.CreatedBusinessesScreen(
                center: CommandCenterRepository(AppScope.of(context).auth.client),
              )),
          _centerPage(Routes.consoleRequestForm, (_, _) => biz.RequestFormScreen()),
          _centerPage(Routes.platformAnalytics, (context, _) =>
              biz.PlatformAnalyticsScreen(analytics: AppScope.of(context).analytics)),
          _centerPage(Routes.trainers, (context, _) =>
              biz.TrainersScreen(console: AppScope.of(context).console)),
          _centerPage(Routes.consolePeople, (context, state) {
            final scope = AppScope.of(context);
            return biz.PlatformPeopleScreen(
              console: scope.console,
              admin: scope.admin,
              // A person the center's search found.
              initialQuery: state.uri.queryParameters['q'],
              openUserId: state.uri.queryParameters['personne'],
            );
          }),
          _centerPage(Routes.consoleAudit, (context, _) =>
              biz.PlatformAuditScreen(console: AppScope.of(context).console)),
          // The paid spots on the welcome page: a platform decision (054).
          _centerPage(Routes.consoleFeatured, (context, _) =>
              biz.FeaturedScreen(admin: AppScope.of(context).admin)),
          // The platform's own vitrines d'exemple (094).
          _centerPage(Routes.consoleShowcase, (context, _) =>
              biz.ShowcaseScreen(admin: AppScope.of(context).admin)),
          // Who may carry deliveries: also the platform's decision (056).
          _centerPage(Routes.consoleCouriers, (context, _) =>
              biz.CouriersScreen(admin: AppScope.of(context).admin)),
          // The platform's part of the delivery fees, per courier, per
          // month (067).
          _centerPage(Routes.consoleSettlement, (context, _) =>
              biz.SettlementScreen(admin: AppScope.of(context).admin)),
          // Wave checkout's switches and payouts (076).
          _centerPage(Routes.consoleWave, (_, _) => biz.WaveConsoleScreen()),
          // Who said they paid, and what the paywall says (066).
          _centerPage(Routes.consolePro, (context, _) => biz.ProConsoleScreen(
                admin: AppScope.of(context).admin,
                cauris: CaurisRepository(AppScope.of(context).auth.client),
              )),
          _centerPage(Routes.consoleCaurisGifts, (context, _) {
            final scope = AppScope.of(context);
            return biz.CaurisGiftsScreen(
              console: scope.console,
              admin: scope.admin,
              cauris: CaurisRepository(scope.auth.client),
            );
          }),
          _centerPage(Routes.consoleSettings, (context, _) => biz.SettingsSection(
                center: CommandCenterRepository(AppScope.of(context).auth.client),
              )),
          _centerPage(Routes.consoleJournal, (context, _) => biz.JournalSection(
                center: CommandCenterRepository(AppScope.of(context).auth.client),
              )),
        ],
      ),

      // ----------------------------------------------------------------
      // Inside a business: one frame around every page (108) — the bar
      // at the foot, or the rail on a wide screen, stays on the home and
      // on every tool, the place on screen selected. The home is the
      // first page under it and every tool a page under the home, so back
      // from a tool returns to the home, never out of the app.
      // ----------------------------------------------------------------
      ShellRoute(
        observers: [cover],
        builder: (context, state, child) =>
            _businessFrame(context, state, child, cover),
        routes: [
      GoRoute(
        path: '/o/:orgId',
        builder: (context, state) => _withOrg(
          context,
          state,
          (scope, org) => biz.BusinessShell(org: org),
        ),
        routes: [
          GoRoute(
            path: 'journal',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  biz.JournalScreen(accounting: scope.accounting, org: org),
            ),
          ),
          GoRoute(
            path: 'comptabilite',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.AccountingHubScreen(
                accounting: scope.accounting,
                org: org,
                // The chart of accounts screen mirrors what it fetches onto
                // the device, which is what keeps the recording sheets
                // offering real category names once the signal has gone.
                db: scope.db,
              ),
              feature: 'accounting',
            ),
            routes: [
              GoRoute(
                path: 'resultat',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.IncomeStatementScreen(
                      accounting: scope.accounting, org: org),
                  feature: 'accounting',
                ),
              ),
              GoRoute(
                path: 'bilan',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.BalanceSheetScreen(
                      accounting: scope.accounting, org: org),
                  feature: 'accounting',
                ),
              ),
              GoRoute(
                path: 'plan',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.ChartOfAccountsScreen(
                    accounting: scope.accounting,
                    org: org,
                    db: scope.db,
                    canEdit: org.isAdmin,
                  ),
                  feature: 'accounting',
                ),
              ),
              GoRoute(
                path: 'balance',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.TrialBalanceScreen(
                      accounting: scope.accounting, org: org),
                  feature: 'accounting',
                ),
              ),
              GoRoute(
                path: 'compte',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) {
                    final account = state.extra;
                    // Reached by tapping an account, which is where the object
                    // comes from. A cold load of this URL has no account to
                    // show, so it falls back to the list rather than rendering
                    // an empty ledger — see the note on `extra` below.
                    if (account is! LedgerAccountArg) {
                      return _MissingContext(
                        backTo: Routes.inside(org.id, 'comptabilite'),
                      );
                    }
                    return biz.AccountLedgerScreen(
                      accounting: scope.accounting,
                      org: org,
                      account: account.account,
                    );
                  },
                  feature: 'accounting',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'administration',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.AdminHomeScreen(
                admin: scope.admin,
                org: org,
                console: scope.console,
                db: scope.db,
                // Renaming the business changes what my_orgs() returns, and
                // the name in the app bar comes from there rather than from
                // the settings form.
                onOrgChanged: scope.session.resolveOrgs,
              ),
              allow: _admins,
            ),
            routes: [
              GoRoute(
                path: 'acces',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.TeamAccessScreen(
                      admin: scope.admin,
                      orgId: org.id,
                      // The owner's dial (103): the others read it.
                      canSave: org.roles.contains('owner') ||
                          scope.session.isPlatformAdmin),
                  allow: _admins,
                ),
              ),
              // The old « Personnes » screen, folded into Équipe (101): an
              // address kept from before lands there.
              GoRoute(
                path: 'personnel',
                redirect: (context, state) =>
                    Routes.inside(state.pathParameters['orgId']!, 'equipe'),
              ),
              GoRoute(
                path: 'structure',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.StructureScreen(
                    admin: scope.admin,
                    orgId: org.id,
                    profile: org.profile,
                  ),
                  allow: _admins,
                ),
              ),
              GoRoute(
                path: 'console',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.ConsoleScreen(
                    console: scope.console,
                    db: scope.db,
                    org: org,
                  ),
                  allow: (org) => org.isSuperAdmin,
                ),
              ),
              GoRoute(
                path: 'parametres',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.OrgSettingsScreen(
                    admin: scope.admin,
                    orgId: org.id,
                    onSaved: scope.session.resolveOrgs,
                    // The suspend control is the platform's, not the business's:
                    // an owner cannot freeze their own shop. Shown only to a
                    // platform admin, and the server refuses it to anyone else
                    // regardless.
                    canSuspend: scope.session.isPlatformAdmin,
                    suspended: org.suspended,
                    // The plan is the platform's to set too (065); every
                    // member reads which one they are on.
                    canSetPlan: scope.session.isPlatformAdmin,
                    plan: org.plan,
                    // The vitrine's Pro dressing (068) picks from the
                    // shop's articles and photographs.
                    retail: scope.retail,
                    capture: scope.capture,
                    initialPart: state.uri.queryParameters['partie'],
                  ),
                  allow: _admins,
                ),
                routes: [
                  GoRoute(
                    path: 'couleurs',
                    builder: (context, state) => _withOrg(
                      context,
                      state,
                      (scope, org) => biz.OrgColoursScreen(
                        admin: scope.admin,
                        orgId: org.id,
                        profile: org.profile,
                        current: org.theme,
                        onSaved: scope.session.resolveOrgs,
                      ),
                      allow: _admins,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // The orders customers sent from the vitrine (055).
          GoRoute(
            path: 'commandes',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.ShopOrdersScreen(org: org, retail: scope.retail),
            ),
          ),
          GoRoute(
            path: 'factures',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  biz.InvoicesScreen(org: org, invoicing: scope.invoicing),
              feature: 'invoices',
            ),
            routes: [
              GoRoute(
                path: 'nouvelle',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) =>
                      biz.NewInvoiceScreen(org: org, invoicing: scope.invoicing),
                  feature: 'invoices',
                ),
              ),
              GoRoute(
                path: 'facturation',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.BillingDetailsScreen(
                      org: org, invoicing: scope.invoicing),
                  feature: 'invoices',
                ),
              ),
              GoRoute(
                path: 'corriger',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) {
                    // Reached from the document with the document in hand;
                    // a cold load has nothing to correct — see `extra` note.
                    final doc = state.extra;
                    if (doc is! InvoiceDocument) {
                      return _MissingContext(
                        backTo: Routes.inside(org.id, 'factures'),
                      );
                    }
                    return biz.NewInvoiceScreen(
                      org: org,
                      invoicing: scope.invoicing,
                      revisionOf: doc,
                    );
                  },
                  feature: 'invoices',
                ),
              ),
              // Last, so the named siblings are not swallowed by it.
              GoRoute(
                path: ':invoiceId',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.InvoiceDocumentScreen(
                    org: org,
                    invoicing: scope.invoicing,
                    invoiceId: state.pathParameters['invoiceId']!,
                  ),
                  feature: 'invoices',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'compte',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.CompteScreen(org: org),
            ),
          ),
          // Kaj and Kaj Pro side by side: the « Pro » strip, every badged
          // tool and Compte open it.
          GoRoute(
            path: 'kaj-pro',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.ProPlansScreen(
                org: org,
                terms: scope.session.planTerms,
                admin: scope.admin,
                // Kaj Pro by card (082), for an admin, when the platform
                // has opened it; and Stripe's page once it is paid.
                cardButton: org.isAdmin
                    ? (period) => biz.StripeCardButton(
                          orgId: org.id,
                          terms: scope.session.planTerms,
                          period: period,
                        )
                    : null,
                cardManage: org.isAdmin ? biz.StripeManage(orgId: org.id) : null,
                stripeReturn: state.uri.queryParameters['stripe'],
                onPaid: () => scope.session.refresh(force: true),
              ),
            ),
          ),
          GoRoute(
            path: 'rapports',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  biz.ReportsHubScreen(reports: scope.reports, org: org),
            ),
            routes: [
              GoRoute(
                path: 'semaine',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.WeeklySummaryScreen(
                    reports: scope.reports,
                    orgId: org.id,
                    orgName: org.name,
                    currency: org.currency,
                    summaryOnly: org.visibility == 'summary',
                  ),
                ),
              ),
              GoRoute(
                path: 'soldes',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.BalancesScreen(
                    reports: scope.reports,
                    orgId: org.id,
                    currency: org.currency,
                  ),
                ),
              ),
              GoRoute(
                path: 'dons',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.GivingStatementScreen(
                    reports: scope.reports,
                    orgId: org.id,
                    orgName: org.name,
                    currency: org.currency,
                  ),
                ),
              ),
              GoRoute(
                path: 'analyse',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  // A farm's own analyses (101); a shop's, as before.
                  (scope, org) => org.profile == 'farm'
                      ? biz.FarmAnalyticsScreen(
                          analytics: scope.analytics,
                          orgId: org.id,
                          orgName: org.name,
                          currency: org.currency,
                        )
                      : biz.OwnerAnalyticsScreen(
                          analytics: scope.analytics,
                          orgId: org.id,
                          orgName: org.name,
                          currency: org.currency,
                        ),
                  feature: 'analytics',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'photos',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.GalleryScreen(
                org: org,
                capture: scope.capture,
                retail: scope.retail,
              ),
            ),
            routes: [
              GoRoute(
                path: 'document',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) {
                    final arg = state.extra;
                    if (arg is! DocumentArg) {
                      return _MissingContext(
                        backTo: Routes.inside(org.id, 'photos'),
                      );
                    }
                    return biz.DocumentScreen(
                      org: org,
                      document: arg.document,
                      capture: scope.capture,
                      retail: scope.retail,
                      products: arg.products,
                    );
                  },
                ),
              ),
              GoRoute(
                path: 'produits',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) {
                    final arg = state.extra;
                    if (arg is! ConfirmProductsArg) {
                      return _MissingContext(
                        backTo: Routes.inside(org.id, 'photos'),
                      );
                    }
                    return biz.ConfirmProductsScreen(
                      org: org,
                      retail: scope.retail,
                      lines: arg.lines,
                      capture: scope.capture,
                      documentId: arg.documentId,
                    );
                  },
                ),
              ),
            ],
          ),
          // The week's race in the business's league (086).
          GoRoute(
            path: 'classement',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.LeagueScreen(
                org: org,
                cauris: CaurisRepository(scope.auth.client),
              ),
            ),
          ),
          // Le Chemin (097): the business's one path — its steps, its
          // tools, its cauris.
          GoRoute(
            path: 'chemin',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.CheminScreen(
                org: org,
                cauris: CaurisRepository(scope.auth.client),
                // ?partie=depenser|parrainer opens on that section;
                // ?caisse=1 when the home with the till opened it.
                initialPart: state.uri.queryParameters['partie'],
                fromTill: state.uri.queryParameters['caisse'] == '1',
              ),
            ),
          ),
          // What a farm sells on its vitrine (083).
          GoRoute(
            path: 'a-vendre',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.ForSaleScreen(
                org: org,
                retail: scope.retail,
                capture: scope.capture,
              ),
            ),
          ),
          // « Mes services » (098): the shop's, the farm's, the association's.
          GoRoute(
            path: 'services',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.ServicesScreen(
                org: org,
                retail: scope.retail,
                capture: scope.capture,
              ),
              // « Services et réservations » on Mara's switchboard (110).
              feature: 'services',
            ),
          ),
          GoRoute(
            path: 'produits',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.ProductsScreen(
                org: org,
                retail: scope.retail,
                capture: scope.capture,
                access: scope.session.accessFor(org.id),
                // ?q=Savon: the article a « Stock bas » ring is about.
                initialQuery: state.uri.queryParameters['q'],
              ),
            ),
          ),
          GoRoute(
            path: 'corrections',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  biz.CorrectionsScreen(org: org, retail: scope.retail),
              feature: 'corrections',
            ),
          ),
          GoRoute(
            path: 'personnel',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.StaffScreen(org: org, staff: scope.staff),
              feature: 'payroll',
            ),
          ),
          // « Équipe » (100): the people, adding one, their salary.
          GoRoute(
            path: 'equipe',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.TeamScreen(
                org: org,
                admin: scope.admin,
                onboarding: scope.onboarding,
              ),
              allow: _admins,
            ),
          ),
          GoRoute(
            path: 'credits',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.CreditBookScreen(
                org: org,
                credit: scope.credit,
                retail: scope.retail,
                access: scope.session.accessFor(org.id),
              ),
              feature: 'credits',
            ),
            routes: [
              GoRoute(
                path: ':customerId',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.CustomerDebtsScreen(
                    org: org,
                    credit: scope.credit,
                    customerId: state.pathParameters['customerId']!,
                    access: scope.session.accessFor(org.id),
                  ),
                  feature: 'credits',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'tontines',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.TontinesScreen(
                org: org,
                tontine: scope.tontine,
                access: scope.session.accessFor(org.id),
              ),
              feature: 'tontines',
            ),
            routes: [
              GoRoute(
                path: ':tontineId',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => biz.TontineScreen(
                    org: org,
                    tontine: scope.tontine,
                    tontineId: state.pathParameters['tontineId']!,
                    access: scope.session.accessFor(org.id),
                  ),
                  feature: 'tontines',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'notifications',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.NotificationsScreen(notify: scope.notify),
            ),
          ),
          GoRoute(
            path: 'production',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.ProductionScreen(
                org: org,
                production: scope.production,
                retail: scope.retail,
                access: scope.session.accessFor(org.id),
              ),
              feature: 'production',
            ),
          ),
          GoRoute(
            path: 'stock',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  biz.StockScreen(db: scope.db, org: org, farm: scope.farm),
            ),
          ),
          GoRoute(
            path: 'bandes',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  biz.FlocksScreen(db: scope.db, org: org, farm: scope.farm),
            ),
          ),
          GoRoute(
            path: 'troupeau',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => biz.LivestockScreen(
                org: org,
                farm: scope.farm,
                initialTab:
                    int.tryParse(state.uri.queryParameters['onglet'] ?? '') ??
                        0,
              ),
            ),
          ),
        ],
      ),
        ],
      ),
    ],
  );
}

/// The business's frame (108) around the page on screen: its bar or rail,
/// the place selected. Follows the session, as a page does, so the bar
/// arrives with the business on a cold load.
Widget _businessFrame(
  BuildContext context,
  GoRouterState state,
  Widget child,
  BusinessCover cover,
) {
  final session = AppScope.of(context).session;
  return _Live(
    session: session,
    builder: () => biz.BusinessFrame(
      org: session.orgById(state.pathParameters['orgId']),
      location: state.uri.path,
      cover: cover,
      child: child,
    ),
  );
}

/// A page of the command center: a section, reached with `go`, drawn in
/// place rather than slid in.
GoRoute _centerPage(
  String path,
  Widget Function(BuildContext context, GoRouterState state) build,
) =>
    GoRoute(
      path: path,
      pageBuilder: (context, state) =>
          NoTransitionPage(key: state.pageKey, child: build(context, state)),
    );

/// Pulls `:orgId` out of a path without needing a matched route.
///
/// Used by the redirect, which runs before a route is matched and so cannot
/// read `state.pathParameters`.
String? _orgIdOf(String location) {
  final parts = location.split('/');
  // ['', 'o', '<id>', ...]
  if (parts.length >= 3 && parts[1] == 'o' && parts[2].isNotEmpty) {
    return parts[2];
  }
  return null;
}

/// Every screen inside a business needs the business, and the URL carries only
/// its id. This resolves one to the other in the single place, so no route
/// builder has to decide what to do when it cannot.
///
/// Two ways the id can fail to resolve, and they are not the same:
///
///   * **The list has not loaded yet.** A browser refresh straight onto
///     `/o/<id>` rebuilds the app from nothing: the org list is empty until
///     `resolveOrgs()` finishes, and for that whole window `orgById` finds
///     nothing. Showing the "opens from the list" dead-end here is a lie — the
///     business is real and about to arrive — and it is exactly what a reload
///     of a deep business URL was hitting. While the session is still booting
///     or resolving we wait, with a spinner; when the list lands the router
///     rebuilds this and the business appears (or the redirect sends an id this
///     person truly cannot open to the picker).
///   * **The list has loaded and the id is genuinely not in it.** Only then is
///     the fallback honest: the org was archived in another tab, say. The
///     redirect has already refused an id with no membership, so this is a page
///     rather than a crash.
Widget _withOrg(
  BuildContext context,
  GoRouterState state,
  Widget Function(AppScope scope, OrgSummary org) build, {
  bool Function(OrgSummary org)? allow,
  String? feature,
}) {
  final scope = AppScope.of(context);
  // Listening here, and not only through the router: go_router keeps a
  // page's widget until the *address* changes. A reload with a live token
  // lands on `/o/<id>/…` already, so when the org list arrives the address
  // is the same, the redirect returns null, and the router never asks this
  // builder again — the spinner it drew while resolving stayed up forever
  // (the report: "every reload, the loading icon never stops"). With the
  // session as a listenable the gate below redraws itself the moment the
  // phase moves, whatever the router does.
  // Above the business's bar, or beside its rail (108).
  return biz.BusinessPage(child: _Live(
    session: scope.session,
    builder: () {
      final org = scope.session.orgById(state.pathParameters['orgId']);
      if (org == null) {
        final phase = scope.session.phase;
        if (phase == SessionPhase.booting || phase == SessionPhase.resolving) {
          return const _Splash();
        }
        return const _MissingContext(backTo: Routes.picker);
      }
      // The business's colours, on every page inside it — not just the home
      // screen. Each `/o/<id>/...` route is a page of its own (the frame
      // around them draws only the bar), so the palette has to be
      // applied here, at the one place they all pass through, or a
      // business's settings, product list and reports all open in the app's
      // default teal instead of the colour it chose. `homeScreenFor` wraps
      // the home screen the same way; the wash is idempotent, so the home
      // route carrying both is harmless.
      return ProfileTheme(
        profile: org.profile,
        theme: org.theme,
        // The small « Pro » on every page of a business not on Kaj Pro,
        // for its owner and admins (ProStrip decides).
        // A page for the business's administrators (101): anybody else
        // reaching its address — a link, a typed URL — is told so politely
        // rather than shown a form the server would refuse.
        // A tool Mara's switchboard hid for this business (104): its
        // address says so — a bookmark, a bell's link — never the screen.
        child: allow != null && !allow(org)
            ? _AdminOnly(org: org)
            : feature != null &&
                    scope.session.accessFor(org.id).isHidden(feature)
                ? FeatureUnavailableScreen(org: org)
                : biz.ProStrip(org: org, child: build(scope, org)),
      );
    },
  ));
}

/// Who may open the administration's pages and Équipe: the business's
/// administrators (the owner, an admin, Mara's own).
bool _admins(OrgSummary org) => org.isAdmin;

/// « Réservé aux administrateurs »: what somebody else sees at one of their
/// addresses — a word and the way back, never the form.
class _AdminOnly extends StatelessWidget {
  const _AdminOnly({required this.org});

  final OrgSummary org;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('admin-only'),
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: maraDeep,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.lock_outline, size: 48, color: maraCaramel),
              ),
              const SizedBox(height: 18),
              Text(context.tr('Réservé aux administrateurs'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(context.tr('Demandez au propriétaire de l\'entreprise.'),
                  textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => context.go(Routes.org(org.id)),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(context.tr('Retour à l\'accueil')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Pas disponible »: what a tool's address shows once Mara's switchboard
/// hid the tool for this business (104) — a word and the way home.
class FeatureUnavailableScreen extends StatelessWidget {
  const FeatureUnavailableScreen({super.key, required this.org});

  final OrgSummary org;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('feature-unavailable'),
      appBar: AppBar(),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: maraDeep,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.visibility_off_outlined,
                    size: 48, color: maraCaramel),
              ),
              const SizedBox(height: 18),
              Text(context.tr('Pas disponible pour votre activité'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                  context.tr('Cette fonction n\'est pas proposée pour {name}. Pour en parler, contactez Mara.',
                      {'name': org.name}),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => context.go(Routes.org(org.id)),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(context.tr('Retour à l\'accueil')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page that reads the session redraws when the session changes.
///
/// The router re-runs a route's builder only when the match list changes —
/// a different address, a pushed page. A session phase moving from
/// `resolving` to `ready` under an unchanged address is invisible to it, so
/// every builder that decides what to show from `session.phase`,
/// `session.identity` or `session.orgs` goes through this: the decision is
/// made inside a [ListenableBuilder] on the session, not once at the door.
class _Live extends StatelessWidget {
  const _Live({required this.session, required this.builder});

  final SessionController session;
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (_, _) => builder(),
    );
  }
}

/// What a page shows when it was opened cold and the thing it was meant to
/// display was never loaded.
///
/// A handful of screens are opened *with* an object rather than an id — the
/// ledger for one account, one photographed document, the lines read off a
/// delivery note. Those are passed as `extra`, which is not part of the URL and
/// so does not survive a refresh or a shared link.
///
/// The alternative was to give each of them a fetch-by-id path of its own, and
/// that is worth doing when somebody actually wants to link to one. Until then
/// this is the honest behaviour: the address is real and back still works, and
/// a cold load says so and offers the list it came from rather than rendering
/// an empty screen that looks broken.
class _MissingContext extends StatelessWidget {
  const _MissingContext({required this.backTo});

  final String backTo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new_off_outlined, size: 40),
              const SizedBox(height: 16),
              Text(
                context.tr('Cette page s\'ouvre depuis la liste.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(backTo),
                child: Text(context.tr('Voir la liste')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page for an address the app does not have.
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MaraMark(size: 72),
                const SizedBox(height: 24),
                Text(context.tr('Cette page n\'existe pas'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  context.tr('Le lien est peut-être ancien ou incomplet.'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: Text(context.tr('Retour à l\'accueil')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    // Mara's seal on graphite and a caramel hairline of progress — the same page
    // the browser and Android show before the app, so launch reads as one
    // picture rather than three.
    return const Scaffold(
      backgroundColor: maraDeep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MaraStacked(height: 200),
            SizedBox(height: 28),
            SizedBox(
              width: 96,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: maraCaramel,
                backgroundColor: Color(0x2EF3EEE4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The typed payloads for the few pages opened with an object rather than an
/// id. Typed rather than raw so a builder can tell "opened from the list" from
/// "opened cold" without guessing at a Map.
class LedgerAccountArg {
  const LedgerAccountArg(this.account);
  final LedgerAccount account;
}

class DocumentArg {
  const DocumentArg({required this.document, this.products = const []});
  final CapturedDocument document;
  final List<Product> products;
}

class ConfirmProductsArg {
  const ConfirmProductsArg({required this.lines, this.documentId});
  final List<InvoiceLine> lines;
  final String? documentId;
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounting/account_ledger_screen.dart';
import '../../features/accounting/accounting_hub_screen.dart';
import '../../features/accounting/balance_sheet_screen.dart';
import '../../features/accounting/chart_of_accounts_screen.dart';
import '../../features/accounting/income_statement_screen.dart';
import '../../features/accounting/trial_balance_screen.dart';
import '../../features/accounting/journal_screen.dart';
import '../../features/admin/admin_home_screen.dart';
import '../../features/admin/applications_screen.dart';
import '../../features/admin/create_business_screen.dart';
import '../../features/admin/org_colours_screen.dart';
import '../../features/admin/org_settings_screen.dart';
import '../../features/admin/people_screen.dart';
import '../../features/admin/platform_console_screen.dart';
import '../../core/courier/courier_repository.dart';
import '../../features/admin/couriers_screen.dart';
import '../../features/admin/featured_screen.dart';
import '../../features/courier/courier_screen.dart';
import '../../features/courier/job_map_screen.dart';
import '../../features/orders/my_orders_screen.dart';
import '../../features/orders/shop_orders_screen.dart';
import '../../features/admin/platform_people_screen.dart';
import '../../features/admin/platform_audit_screen.dart';
import '../../features/analytics/owner_analytics_screen.dart';
import '../../features/analytics/platform_analytics_screen.dart';
import '../../features/admin/trainers_screen.dart';
import '../../features/account/compte_screen.dart';
import '../../features/account/legal_screens.dart';
import '../../features/admin/structure_screen.dart';
import '../../features/admin/team_access_screen.dart';
import '../../features/auth/join_or_apply_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/no_org_screen.dart';
import '../../features/auth/org_picker_screen.dart';
import '../../features/auth/pin_screen.dart';
import '../../features/auth/profile_form_screen.dart';
import '../../features/capture/confirm_products_screen.dart';
import '../../features/capture/gallery_screen.dart';
import '../../features/church/reports/balances_screen.dart';
import '../../features/church/reports/giving_statement_screen.dart';
import '../../features/church/reports/reports_hub_screen.dart';
import '../../features/church/reports/weekly_summary_screen.dart';
import '../../features/console/console_screen.dart';
import '../../features/credit/credit_book_screen.dart';
import '../../features/farm/flocks_screen.dart';
import '../../features/farm/livestock_screen.dart';
import '../../features/farm/stock_screen.dart';
import '../../features/home/business_shell.dart';
import '../../features/invoicing/billing_details_screen.dart';
import '../../features/storefront/directory_screen.dart';
import '../../features/storefront/storefront_screen.dart';
import '../storefront/storefront_repository.dart';
import '../../features/invoicing/invoice_document_screen.dart';
import '../../features/invoicing/invoices_screen.dart';
import '../../features/invoicing/new_invoice_screen.dart';
import '../../features/notify/notifications_screen.dart';
import '../../features/production/production_screen.dart';
import '../../features/retail/corrections_screen.dart';
import '../../features/retail/products_screen.dart';
import '../../features/retail/staff_screen.dart';
import '../../features/settings/language_screen.dart';
import '../../features/tontine/tontines_screen.dart';
import '../theme/kaj_theme.dart';
import '../accounting/models.dart';
import '../invoicing/models.dart' show InvoiceDocument;
import '../auth/models.dart';
import '../capture/invoice_reading.dart';
import '../capture/models.dart';
import '../retail/models.dart';
import 'app_scope.dart';
import 'session.dart';

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
  static const join = '/rejoindre';
  static const myProfile = '/mon-profil';
  static const picker = '/entreprises';
  static const newBusiness = '/nouvelle-entreprise';
  static const applyForBusiness = '/demander-une-entreprise';
  static const console = '/console';
  static const platformAnalytics = '/console/analyses';
  static const trainers = '/console/formateurs';
  static const consolePeople = '/console/personnes';
  static const consoleAudit = '/console/activite';
  static const consoleFeatured = '/console/a-la-une';
  static const myOrders = '/mes-commandes';
  static const courier = '/livreur';
  /// One running course on a map, for its courier.
  static String courierJob(String orderId) => '/livreur/course/$orderId';
  static const consoleCouriers = '/console/livreurs';
  static const applications = '/demandes';
  static const language = '/langue';
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
}

/// Builds the router. Called once, from `main()`.
///
/// [session] is both the source of truth for which phase the app is in and the
/// thing the router listens to: every phase change re-runs the redirect below,
/// which is what turns "signed out" or "no business yet" into an address rather
/// than a screen swapped in behind the user's back.
GoRouter buildRouter(SessionController session) {
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
        !at(Routes.pin);

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
            at(Routes.courier) ||
            at(Routes.newBusiness) ||
            at(Routes.applyForBusiness) ||
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
            at(Routes.courier) ||
            at(Routes.newBusiness) ||
            at(Routes.applyForBusiness) ||
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
            at(Routes.courier) ||
            at(Routes.newBusiness) ||
            at(Routes.applyForBusiness) ||
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
    redirect: redirect,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _Splash()),
      // Reachable from every phase — see the redirect, which never blocks it.
      // The person who most needs this screen is the one who cannot read the
      // sign-in page, so gating it behind sign-in would be absurd.
      GoRoute(
          path: Routes.language, builder: (_, _) => const LanguageScreen()),
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
            storefront: StorefrontRepository(scope.auth.client),
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
        builder: (context, state) => CourierScreen(
          courier: CourierRepository(AppScope.of(context).auth.client),
        ),
      ),
      GoRoute(
        path: '${Routes.courier}/course/:id',
        builder: (context, state) => JobMapScreen(
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
            storefront: StorefrontRepository(scope.auth.client),
            capture: scope.capture,
            session: scope.session,
          );
        },
      ),

      GoRoute(
        path: Routes.signIn,
        builder: (context, _) {
          final scope = AppScope.of(context);
          return LoginScreen(
            auth: scope.auth,
            // Lets the sign-up form save the names, date of birth, title and
            // phone it collects, the moment the account exists.
            onboarding: scope.onboarding,
            onSignedIn: scope.session.handleSignedIn,
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
              );
            },
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
              onBusinesses:
                  scope.session.isPlatformAdmin && scope.auth.hasLiveSession
                      ? () => context.push(Routes.console)
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
          title: 'Mes informations',
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
            CreateBusinessScreen(admin: AppScope.of(context).admin),
      ),

      /// Asking for another business, for somebody who already has one. A
      /// platform admin creates directly instead — they are the person who
      /// would otherwise be approving their own request.
      GoRoute(
        path: Routes.applyForBusiness,
        builder: (context, _) {
          final scope = AppScope.of(context);
          return CreateBusinessScreen(
            admin: scope.admin,
            onboarding: scope.onboarding,
            asApplication: true,
          );
        },
      ),

      GoRoute(
        path: Routes.console,
        builder: (context, _) {
          final scope = AppScope.of(context);
          return PlatformConsoleScreen(
            admin: scope.admin,
            console: scope.console,
          );
        },
      ),

      GoRoute(
        path: Routes.platformAnalytics,
        builder: (context, _) =>
            PlatformAnalyticsScreen(analytics: AppScope.of(context).analytics),
      ),

      GoRoute(
        path: Routes.trainers,
        builder: (context, _) =>
            TrainersScreen(console: AppScope.of(context).console),
      ),

      GoRoute(
        path: Routes.consolePeople,
        builder: (context, _) {
          final scope = AppScope.of(context);
          return PlatformPeopleScreen(
            console: scope.console,
            admin: scope.admin,
          );
        },
      ),

      GoRoute(
        path: Routes.consoleAudit,
        builder: (context, _) =>
            PlatformAuditScreen(console: AppScope.of(context).console),
      ),

      // The paid spots on the welcome page: a platform decision (054).
      GoRoute(
        path: Routes.consoleFeatured,
        builder: (context, _) =>
            FeaturedScreen(admin: AppScope.of(context).admin),
      ),

      // Who may carry deliveries: also the platform's decision (056).
      GoRoute(
        path: Routes.consoleCouriers,
        builder: (context, _) =>
            CouriersScreen(admin: AppScope.of(context).admin),
      ),

      GoRoute(
        path: Routes.applications,
        builder: (context, _) =>
            ApplicationsScreen(onboarding: AppScope.of(context).onboarding),
      ),

      // ----------------------------------------------------------------
      // Inside a business
      // ----------------------------------------------------------------
      GoRoute(
        path: '/o/:orgId',
        builder: (context, state) => _withOrg(
          context,
          state,
          (scope, org) => BusinessShell(org: org),
        ),
        routes: [
          GoRoute(
            path: 'journal',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  JournalScreen(accounting: scope.accounting, org: org),
            ),
          ),
          GoRoute(
            path: 'comptabilite',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => AccountingHubScreen(
                accounting: scope.accounting,
                org: org,
                // The chart of accounts screen mirrors what it fetches onto
                // the device, which is what keeps the recording sheets
                // offering real category names once the signal has gone.
                db: scope.db,
              ),
            ),
            routes: [
              GoRoute(
                path: 'resultat',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => IncomeStatementScreen(
                      accounting: scope.accounting, org: org),
                ),
              ),
              GoRoute(
                path: 'bilan',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => BalanceSheetScreen(
                      accounting: scope.accounting, org: org),
                ),
              ),
              GoRoute(
                path: 'plan',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => ChartOfAccountsScreen(
                    accounting: scope.accounting,
                    org: org,
                    db: scope.db,
                    canEdit: org.isAdmin,
                  ),
                ),
              ),
              GoRoute(
                path: 'balance',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => TrialBalanceScreen(
                      accounting: scope.accounting, org: org),
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
                    return AccountLedgerScreen(
                      accounting: scope.accounting,
                      org: org,
                      account: account.account,
                    );
                  },
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'administration',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => AdminHomeScreen(
                admin: scope.admin,
                org: org,
                console: scope.console,
                db: scope.db,
                // Renaming the business changes what my_orgs() returns, and
                // the name in the app bar comes from there rather than from
                // the settings form.
                onOrgChanged: scope.session.resolveOrgs,
              ),
            ),
            routes: [
              GoRoute(
                path: 'acces',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) =>
                      TeamAccessScreen(admin: scope.admin, orgId: org.id),
                ),
              ),
              GoRoute(
                path: 'personnel',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => PeopleScreen(
                    admin: scope.admin,
                    orgId: org.id,
                    orgName: org.name,
                    // Sets the ceiling on who this person may manage.
                    callerRoles: org.roles,
                  ),
                ),
              ),
              GoRoute(
                path: 'structure',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => StructureScreen(
                    admin: scope.admin,
                    orgId: org.id,
                    profile: org.profile,
                  ),
                ),
              ),
              GoRoute(
                path: 'console',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => ConsoleScreen(
                    console: scope.console,
                    db: scope.db,
                    org: org,
                  ),
                ),
              ),
              GoRoute(
                path: 'parametres',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => OrgSettingsScreen(
                    admin: scope.admin,
                    orgId: org.id,
                    onSaved: scope.session.resolveOrgs,
                    // The suspend control is the platform's, not the business's:
                    // an owner cannot freeze their own shop. Shown only to a
                    // platform admin, and the server refuses it to anyone else
                    // regardless.
                    canSuspend: scope.session.isPlatformAdmin,
                    suspended: org.suspended,
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'couleurs',
                    builder: (context, state) => _withOrg(
                      context,
                      state,
                      (scope, org) => OrgColoursScreen(
                        admin: scope.admin,
                        orgId: org.id,
                        profile: org.profile,
                        current: org.theme,
                        onSaved: scope.session.resolveOrgs,
                      ),
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
              (scope, org) => ShopOrdersScreen(org: org, retail: scope.retail),
            ),
          ),
          GoRoute(
            path: 'factures',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  InvoicesScreen(org: org, invoicing: scope.invoicing),
            ),
            routes: [
              GoRoute(
                path: 'nouvelle',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) =>
                      NewInvoiceScreen(org: org, invoicing: scope.invoicing),
                ),
              ),
              GoRoute(
                path: 'facturation',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => BillingDetailsScreen(
                      org: org, invoicing: scope.invoicing),
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
                    return NewInvoiceScreen(
                      org: org,
                      invoicing: scope.invoicing,
                      revisionOf: doc,
                    );
                  },
                ),
              ),
              // Last, so the named siblings are not swallowed by it.
              GoRoute(
                path: ':invoiceId',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => InvoiceDocumentScreen(
                    org: org,
                    invoicing: scope.invoicing,
                    invoiceId: state.pathParameters['invoiceId']!,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'compte',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => CompteScreen(org: org),
            ),
          ),
          GoRoute(
            path: 'rapports',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  ReportsHubScreen(reports: scope.reports, org: org),
            ),
            routes: [
              GoRoute(
                path: 'semaine',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => WeeklySummaryScreen(
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
                  (scope, org) => BalancesScreen(
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
                  (scope, org) => GivingStatementScreen(
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
                  (scope, org) => OwnerAnalyticsScreen(
                    analytics: scope.analytics,
                    orgId: org.id,
                    orgName: org.name,
                    currency: org.currency,
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'photos',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => GalleryScreen(
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
                    return DocumentScreen(
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
                    return ConfirmProductsScreen(
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
          GoRoute(
            path: 'produits',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => ProductsScreen(
                org: org,
                retail: scope.retail,
                capture: scope.capture,
                access: scope.session.accessFor(org.id),
              ),
            ),
          ),
          GoRoute(
            path: 'corrections',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  CorrectionsScreen(org: org, retail: scope.retail),
            ),
          ),
          GoRoute(
            path: 'personnel',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => StaffScreen(org: org, staff: scope.staff),
            ),
          ),
          GoRoute(
            path: 'credits',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => CreditBookScreen(
                org: org,
                credit: scope.credit,
                retail: scope.retail,
                access: scope.session.accessFor(org.id),
              ),
            ),
            routes: [
              GoRoute(
                path: ':customerId',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => CustomerDebtsScreen(
                    org: org,
                    credit: scope.credit,
                    customerId: state.pathParameters['customerId']!,
                    access: scope.session.accessFor(org.id),
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'tontines',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => TontinesScreen(
                org: org,
                tontine: scope.tontine,
                access: scope.session.accessFor(org.id),
              ),
            ),
            routes: [
              GoRoute(
                path: ':tontineId',
                builder: (context, state) => _withOrg(
                  context,
                  state,
                  (scope, org) => TontineScreen(
                    org: org,
                    tontine: scope.tontine,
                    tontineId: state.pathParameters['tontineId']!,
                    access: scope.session.accessFor(org.id),
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'notifications',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => NotificationsScreen(notify: scope.notify),
            ),
          ),
          GoRoute(
            path: 'production',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => ProductionScreen(
                org: org,
                production: scope.production,
                retail: scope.retail,
                access: scope.session.accessFor(org.id),
              ),
            ),
          ),
          GoRoute(
            path: 'stock',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  StockScreen(db: scope.db, org: org, farm: scope.farm),
            ),
          ),
          GoRoute(
            path: 'bandes',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) =>
                  FlocksScreen(db: scope.db, org: org, farm: scope.farm),
            ),
          ),
          GoRoute(
            path: 'troupeau',
            builder: (context, state) => _withOrg(
              context,
              state,
              (scope, org) => LivestockScreen(
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
  );
}

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
  Widget Function(AppScope scope, OrgSummary org) build,
) {
  final scope = AppScope.of(context);
  // Listening here, and not only through the router: go_router keeps a
  // page's widget until the *address* changes. A reload with a live token
  // lands on `/o/<id>/…` already, so when the org list arrives the address
  // is the same, the redirect returns null, and the router never asks this
  // builder again — the spinner it drew while resolving stayed up forever
  // (the report: "every reload, the loading icon never stops"). With the
  // session as a listenable the gate below redraws itself the moment the
  // phase moves, whatever the router does.
  return _Live(
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
      // screen. Each `/o/<id>/...` route is a page of its own (they replace
      // the shell rather than nest under it), so the palette has to be
      // applied here, at the one place they all pass through, or a
      // business's settings, product list and reports all open in the app's
      // default teal instead of the colour it chose. `homeScreenFor` wraps
      // the home screen the same way; the wash is idempotent, so the home
      // route carrying both is harmless.
      return ProfileTheme(
        profile: org.profile,
        theme: org.theme,
        child: build(scope, org),
      );
    },
  );
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
              const Text(
                "Cette page s'ouvre depuis la liste.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(backTo),
                child: const Text('Voir la liste'),
              ),
            ],
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

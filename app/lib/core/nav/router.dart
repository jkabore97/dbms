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
import '../../features/invoicing/invoice_document_screen.dart';
import '../../features/invoicing/invoices_screen.dart';
import '../../features/invoicing/new_invoice_screen.dart';
import '../../features/notify/notifications_screen.dart';
import '../../features/production/production_screen.dart';
import '../../features/retail/products_screen.dart';
import '../../features/retail/staff_screen.dart';
import '../../features/settings/language_screen.dart';
import '../../features/tontine/tontines_screen.dart';
import '../accounting/models.dart';
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
  static const applications = '/demandes';
  static const language = '/langue';

  /// A business, and everything inside it.
  static String org(String id) => '/o/$id';
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
    // is the one who cannot read whatever screen their phase would show.
    if (at(Routes.language)) return null;

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
        // Belongs to no business yet, so there is no `/o/...` to be at — but
        // the things somebody in that position does need are all reachable.
        if (at(Routes.join) ||
            at(Routes.myProfile) ||
            at(Routes.newBusiness) ||
            at(Routes.applyForBusiness) ||
            at(Routes.console) ||
            at(Routes.applications)) {
          return null;
        }
        return Routes.join;

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
            at(Routes.myProfile) ||
            at(Routes.newBusiness) ||
            at(Routes.applyForBusiness) ||
            at(Routes.console) ||
            at(Routes.applications)) {
          return null;
        }
        return Routes.picker;

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
            at(Routes.myProfile) ||
            at(Routes.newBusiness) ||
            at(Routes.applyForBusiness) ||
            at(Routes.console) ||
            at(Routes.applications)) {
          return null;
        }
        // `/`, the splash, or a stale sign-in URL: go to the open business.
        final open = session.lastOrgId;
        return open == null ? Routes.picker : Routes.org(open);
    }
  }

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: session,
    redirect: redirect,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Splash()),
      // Reachable from every phase — see the redirect, which never blocks it.
      // The person who most needs this screen is the one who cannot read the
      // sign-in page, so gating it behind sign-in would be absurd.
      GoRoute(
          path: Routes.language, builder: (_, __) => const LanguageScreen()),
      GoRoute(path: Routes.splash, builder: (_, __) => const _Splash()),

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
          final creating = scope.session.phase == SessionPhase.choosingPin;
          return PinScreen(
            purpose: creating ? PinPurpose.create : PinPurpose.unlock,
            identity: scope.session.identity!,
            onPinAccepted: (pin) =>
                creating ? scope.session.setPin(pin) : scope.session.unlock(),
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
          if (!scope.auth.hasLiveSession) {
            return NoOrgScreen(
              identity: scope.session.identity!,
              onRetry: scope.session.resolveOrgs,
              onSignOut: scope.session.signOut,
              // The bootstrap case: the person who runs the platform, before
              // any business exists.
              onCreateBusiness: scope.session.isPlatformAdmin
                  ? () => context.push(Routes.newBusiness)
                  : null,
            );
          }
          return JoinOrApplyScreen(
            identity: scope.session.identity!,
            onboarding: scope.onboarding,
            admin: scope.admin,
            onRetry: scope.session.resolveOrgs,
            onSignOut: scope.session.signOut,
            checking: scope.session.phase == SessionPhase.resolving,
          );
        },
      ),

      GoRoute(
        path: Routes.picker,
        builder: (context, _) {
          final scope = AppScope.of(context);
          return OrgPickerScreen(
            orgs: scope.session.orgs,
            // `push`, not `go`: opening a business is a step *into* the
            // app, so the picker has to stay underneath it. `go` replaces the
            // location, which is what left back with nowhere to return to and
            // dropped people out of the app entirely.
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
              // Last, so `nouvelle` and `facturation` are not swallowed by it.
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
/// The redirect above has already refused an id this person has no membership
/// for, so reaching the fallback means the org list changed underneath — a
/// business archived in another tab, say. Sending them to the picker is the
/// honest answer to that, and it is a page rather than a crash.
Widget _withOrg(
  BuildContext context,
  GoRouterState state,
  Widget Function(AppScope scope, OrgSummary org) build,
) {
  final scope = AppScope.of(context);
  final org = scope.session.orgById(state.pathParameters['orgId']);
  if (org == null) return const _MissingContext(backTo: Routes.picker);
  return build(scope, org);
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

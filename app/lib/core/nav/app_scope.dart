import 'package:flutter/widgets.dart';

import '../accounting/accounting_repository.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_repository.dart';
import '../capture/capture_repository.dart';
import '../console/console_repository.dart';
import '../db/local_db.dart';
import '../farm/farm_repository.dart';
import '../invoicing/invoicing_repository.dart';
import '../l10n/locale_controller.dart';
import '../onboarding/onboarding_repository.dart';
import '../reports/reports_repository.dart';
import '../retail/retail_repository.dart';
import '../retail/staff.dart';
import '../sync/sync_service.dart';
import 'session.dart';

/// The repositories, reachable from anywhere below the router.
///
/// They used to be threaded down through constructors from `main()`, which
/// worked while one widget owned the whole tree. A route builder has no parent
/// to be handed them by — it is called by the router with nothing but the URL —
/// so they live here instead and each builder takes what it needs.
///
/// This is deliberately not a general-purpose service locator. It holds exactly
/// what `main()` constructs, it is created once, and nothing writes to it. The
/// screens keep taking their repositories as constructor arguments, so they
/// stay testable without any of this: the scope is read at the route boundary
/// and nowhere deeper.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.session,
    required this.localeController,
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
    required super.child,
  });

  final SessionController session;
  final LocaleController localeController;
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

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

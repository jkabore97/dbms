import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/console/console_repository.dart';
import '../../core/db/local_db.dart';
import 'activity_log_tab.dart';
import 'database_tab.dart';
import 'device_tab.dart';

/// The super admin's console.
///
/// Three tabs, and they are three tabs because they answer three different
/// kinds of question that get asked in the same five minutes:
///
///   * ACTIVITÉ — what happened, and who did it. Nothing else in the app can
///     answer this. The ledger has been its own audit trail since the first
///     schema, which covers money and nothing else; every decision about who
///     may touch the money has been silently mutable until 008.
///   * BASE DE DONNÉES — what is actually stored. A super admin who can only
///     see the screens has to trust the screens, and the screens are the thing
///     they are checking.
///   * APPAREIL — what this phone is still holding. The one place where the
///     honest answer to "did my work save" lives, including the failures,
///     which until now were written to a column nobody ever read.
///
/// Reached only by an owner or a super admin — the entry point is hidden
/// otherwise — but hiding it is a courtesy, not the protection. Every function
/// behind here is gated on `is_org_admin()` server-side and returns nothing to
/// anybody else, so a non-admin who arrived here anyway sees empty lists.
class ConsoleScreen extends StatelessWidget {
  const ConsoleScreen({
    super.key,
    required this.console,
    required this.db,
    required this.org,
  });

  final ConsoleRepository console;
  final LocalDb db;
  final OrgSummary org;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Console'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.history), text: 'Activité'),
              Tab(icon: Icon(Icons.storage_outlined), text: 'Données'),
              Tab(icon: Icon(Icons.phone_android), text: 'Appareil'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ActivityLogTab(console: console, org: org),
            DatabaseTab(console: console, org: org),
            DeviceTab(db: db, org: org),
          ],
        ),
      ),
    );
  }
}

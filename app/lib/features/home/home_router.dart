import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/reports/reports_repository.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/staff.dart';
import '../church/church_home_screen.dart';
import '../farm/farm_home_screen.dart';
import '../retail/store_home_screen.dart';
import 'profile_pending_screen.dart';

/// Which screen a business opens on.
///
/// The org's `profile` column decides, never the build and never a setting on
/// the device: the same APK in the same hand shows a church to Israel and a
/// farm to Ignace. An unrecognised profile falls through to the pending screen
/// rather than failing, so a profile added server-side cannot break the app
/// already installed on someone's phone.
Widget homeScreenFor({
  required LocalDb db,
  required OrgSummary org,
  ReportsRepository? reports,
  FarmRepository? farm,
  RetailRepository? retail,
  StaffRepository? staff,
  CaptureRepository? capture,
  Widget? accountAction,
  VoidCallback? onHistory,
}) {
  return switch (org.profile) {
    'church' => ChurchHomeScreen(
        db: db,
        orgId: org.id,
        orgName: org.name,
        reports: reports,
        org: org,
        capture: capture,
        accountAction: accountAction,
        onHistory: onHistory,
      ),
    'farm' => FarmHomeScreen(
        db: db,
        org: org,
        farm: farm,
        capture: capture,
        accountAction: accountAction,
      ),
    'retail' => StoreHomeScreen(
        org: org,
        retail: retail,
        staff: staff,
        capture: capture,
        accountAction: accountAction,
      ),
    // Anything else — a profile added server-side that this build has never
    // heard of — lands here rather than failing.
    _ => ProfilePendingScreen(org: org, accountAction: accountAction),
  };
}

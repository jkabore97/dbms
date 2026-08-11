import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../church/church_home_screen.dart';
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
  Widget? accountAction,
}) {
  return switch (org.profile) {
    'church' => ChurchHomeScreen(
        db: db,
        orgId: org.id,
        orgName: org.name,
        accountAction: accountAction,
      ),
    // 'farm' and 'retail' are real profiles with no module yet.
    _ => ProfilePendingScreen(org: org, accountAction: accountAction),
  };
}

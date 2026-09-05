import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

import '../../core/auth/models.dart';
import '../auth/org_picker_screen.dart'
    show iconForProfile, localizedProfile;

/// The landing screen for an org whose profile has no module yet — the farm
/// and the retail shop, until those land.
///
/// The org resolved correctly and the person is where they should be; there is
/// simply nothing to record here yet. Saying that plainly beats dropping a
/// farmer into a screen built for counting offerings.
class ProfilePendingScreen extends StatelessWidget {
  const ProfilePendingScreen({
    super.key,
    required this.org,
    this.accountAction,
  });

  final OrgSummary org;
  final Widget? accountAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(org.name),
        actions: [?accountAction],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iconForProfile(org.profile),
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  org.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  localizedProfile(context, org.profile),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  Strings.of(context).moduleComingSoon(
                      localizedProfile(context, org.profile).toLowerCase()),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

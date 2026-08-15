import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/console/console_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/nav/router.dart';

/// The administration hub.
///
/// Reached only by someone who administers this org — the entry point is
/// hidden otherwise — but hiding it is a courtesy, not the protection. Every
/// screen behind here is protected by the policies in 004 and 005, so an
/// admin-only action attempted by a non-admin fails at the server whether or
/// not the button was ever on screen.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({
    super.key,
    required this.admin,
    required this.org,
    this.console,
    this.db,
    this.onOrgChanged,
  });

  final AdminRepository admin;
  final OrgSummary org;

  /// The activity log and the database view. Null in a build with no server,
  /// where there is nothing to read.
  final ConsoleRepository? console;

  /// Needed by the console's device tab, which reads this phone's outbox.
  final LocalDb? db;

  /// Called when something here changes what `my_orgs()` would return — the
  /// business's name, most obviously.
  final VoidCallback? onOrgChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(Strings.of(context).administration)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    org.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    org.roles.map(_roleWord).join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _AdminTile(
            icon: Icons.group_outlined,
            title: Strings.of(context).people,
            subtitle: Strings.of(context).peopleSubtitle,
            onTap: () =>
                context.push(Routes.inside(org.id, 'administration/personnel')),
          ),
          _AdminTile(
            icon: Icons.account_tree_outlined,
            title: Strings.of(context).sitesAndDepartments,
            subtitle: Strings.of(context).structureSubtitle,
            onTap: () =>
                context.push(Routes.inside(org.id, 'administration/structure')),
          ),
          _AdminTile(
            icon: Icons.settings_outlined,
            title: Strings.of(context).orgSettingsTitle,
            subtitle: Strings.of(context).orgSettingsSubtitle,
            onTap: () => context
                .push(Routes.inside(org.id, 'administration/parametres')),
          ),

          // Last, and behind the narrower role test. Everything above is
          // running the business; this is looking at the machinery underneath
          // it, and it is the only screen in the app that says what every
          // colleague has been doing.
          if (org.isSuperAdmin && console != null && db != null) ...[
            const SizedBox(height: 8),
            _AdminTile(
              icon: Icons.terminal,
              title: Strings.of(context).consoleTitle,
              subtitle: Strings.of(context).consoleSubtitle,
              onTap: () =>
                  context.push(Routes.inside(org.id, 'administration/console')),
            ),
          ],
        ],
      ),
    );
  }

  static String _roleWord(String role) => switch (role) {
        'owner' => 'Propriétaire',
        'super_admin' => 'Super administrateur',
        'admin' => 'Administrateur',
        _ => role,
      };
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Icon(icon, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

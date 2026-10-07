import 'package:flutter/material.dart';

import '../../core/theme/kaj_card.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/admin/models.dart' show roleLabel, roleLabels;
import '../../core/auth/models.dart';
import '../../core/console/console_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../account/pro_sheet.dart';
import 'package:kaj_app/core/l10n/tr.dart';

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
    final scope = AppScope.maybeOf(context);
    final roles = [
      for (final r in org.roles)
        if (roleLabels.containsKey(r)) context.tr(roleLabel(r)),
    ];

    return Scaffold(
      backgroundColor: maraPaper,
      appBar: AppBar(
        title: Text(context.tr('Administration')),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: context.tr('Les vitrines'),
            onPressed: () => context.go(Routes.directory),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // The business, graphite with its caramel mark — the app's own
          // colours, whatever the business's palette.
          Container(
            key: const Key('admin-header'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: maraDeep,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: maraCaramel,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.admin_panel_settings_outlined,
                      color: maraDeep, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        org.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: maraPaper, fontWeight: FontWeight.w800),
                      ),
                      if (roles.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          roles.join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: maraCaramel, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // The business's people: one place, Équipe (101 folded the old
          // « Personnes » screen into it).
          _AdminTile(
            key: const Key('admin-team'),
            icon: Icons.groups_outlined,
            title: context.tr('Équipe'),
            subtitle: context.tr('Les personnes, leur responsabilité, les invitations'),
            onTap: () => context.push(Routes.inside(org.id, 'equipe')),
          ),
          _AdminTile(
            icon: Icons.account_tree_outlined,
            title: context.tr('Sites et départements'),
            subtitle: context.tr('La structure de l\'activité'),
            onTap: () =>
                context.push(Routes.inside(org.id, 'administration/structure')),
          ),
          // The dial is a Pro tool (066): on a Free business it is drawn
          // with the badge and opens the door to pay. Reading the scope
          // softly — this screen also lives in bare test trees.
          _AdminTile(
            icon: Icons.key_outlined,
            title: context.tr('Accès de l\'équipe'),
            subtitle: context.tr('Qui voit quoi, qui modifie quoi'),
            pro: scope?.session.accessFor(org.id).isProLocked('team_access') ??
                false,
            onTap: () {
              final s = scope;
              if (s != null &&
                  s.session.accessFor(org.id).isProLocked('team_access')) {
                ProSheet.open(
                  context,
                  org: org,
                  terms: s.session.planTerms,
                  admin: admin,
                  canRequest: org.isAdmin,
                  feature: 'team_access',
                );
                return;
              }
              context.push(Routes.inside(org.id, 'administration/acces'));
            },
          ),
          _AdminTile(
            icon: Icons.settings_outlined,
            title: context.tr('Paramètres de l\'activité'),
            subtitle: context.tr('Nom et monnaie'),
            onTap: () => context.push(Routes.orgSettings(org.id)),
          ),

          // Last, and behind the narrower role test (the owner, a super
          // administrator). Everything above is running the business; this
          // is looking at the machinery underneath it, and it is the only
          // screen in the app that says what every colleague has been doing.
          if (org.isSuperAdmin && console != null && db != null) ...[
            const SizedBox(height: 8),
            _AdminTile(
              key: const Key('admin-console'),
              icon: Icons.terminal,
              title: context.tr('Console'),
              subtitle: context.tr('Journal d\'activité, données, état de l\'appareil'),
              onTap: () =>
                  context.push(Routes.inside(org.id, 'administration/console')),
            ),
          ],
        ],
      ),
    );
  }
}

/// One door of the hub: a paper square with its picture, a word, a line.
class _AdminTile extends StatelessWidget {
  const _AdminTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.pro = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Behind Mara Pro on this business (066): badged, never hidden.
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KajCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        minVerticalPadding: 14,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: maraPaper,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 26, color: pro ? maraBrown : maraDeep),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700, color: maraDeep)),
        subtitle: Text(subtitle),
        trailing: pro
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: maraBrown,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(context.tr('Pro'),
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: maraPaper, fontWeight: FontWeight.w800)),
              )
            : const Icon(Icons.chevron_right, color: maraGrey),
        onTap: onTap,
      ),
    );
  }
}

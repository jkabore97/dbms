import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../l10n/strings.dart';
import '../admin/invite_generator_sheet.dart';
import 'support.dart';

/// One screen for everything that used to be scattered across a long popup
/// menu: who you are, the business you are in, help, and the legal pages.
///
/// It replaces the account menu (AccountMenu) entirely. The rule that shaped it:
/// a person looking for "how do I reach support" or "where are my settings"
/// should find one door marked Compte and, behind it, four plain headings —
/// not a list of fifteen icons to read through. Every destination the old menu
/// offered is still here, grouped; nothing was dropped.
///
/// It reads the session itself rather than being handed a dozen callbacks, so
/// it stays a real page with an address (`/o/<id>/compte`) that the back button
/// and a reload both respect.
class CompteScreen extends StatelessWidget {
  const CompteScreen({super.key, required this.org});

  final OrgSummary org;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final session = scope.session;
    final live = scope.auth.hasLiveSession;
    final admin = org.isAdmin && live;
    final platform = session.isPlatformAdmin && live;
    final access = session.accessFor(org.id);
    final identity = session.identity;

    String inside(String rest) => Routes.inside(org.id, rest);

    return Scaffold(
      appBar: AppBar(title: Text(Strings.of(context).account)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Who you are.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(
                    (identity?.label ?? '?').characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(identity?.label ?? '',
                          style: Theme.of(context).textTheme.titleMedium),
                      if (identity?.phone != null)
                        Text(identity!.phone!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---- Mon compte ----
          const _Section(title: 'Mon compte'),
          if (live)
            _Tile(
              icon: Icons.badge_outlined,
              title: Strings.of(context).myProfile,
              onTap: () => context.push(Routes.myProfile),
            ),
          _Tile(
            icon: Icons.language,
            title: Strings.of(context).language,
            onTap: () => context.push(Routes.language),
          ),
          if (session.orgs.length > 1)
            _Tile(
              icon: Icons.swap_horiz,
              title: Strings.of(context).switchBusiness,
              onTap: () => context.go(Routes.picker),
            ),
          _Tile(
            icon: Icons.logout,
            title: Strings.of(context).signOut,
            onTap: () => _confirmSignOut(context, scope, session),
          ),

          // ---- Mon entreprise ----
          if (live) ...[
            const _Section(title: 'Mon entreprise'),
            if (admin)
              _Tile(
                icon: Icons.admin_panel_settings_outlined,
                title: Strings.of(context).administration,
                onTap: () => context.push(inside('administration')),
              ),
            // Owner-only, the same full visibility the server requires for
            // the analytics functions themselves.
            if (org.visibility == 'full' && org.profile == 'retail')
              _Tile(
                icon: Icons.insights_outlined,
                title: 'Analyses',
                onTap: () => context.push(inside('rapports/analyse')),
              ),
            if (access.canSee('reports'))
              _Tile(
                icon: Icons.menu_book_outlined,
                title: Strings.of(context).accounting,
                onTap: () => context.push(inside('comptabilite')),
              ),
            // Undo a sale or a purchase entered by mistake — or test data.
            // Owner/admin only, and only where there are sales and deliveries
            // to undo; the server refuses everyone else regardless.
            if (admin && org.profile == 'retail')
              _Tile(
                icon: Icons.history_toggle_off_outlined,
                title: 'Corrections',
                onTap: () => context.push(inside('corrections')),
              ),
            if (access.canSee('credits'))
              _Tile(
                icon: Icons.handshake_outlined,
                title: Strings.of(context).creditBook,
                onTap: () => context.push(inside('credits')),
              ),
            if (access.canSee('tontines'))
              _Tile(
                icon: Icons.group_outlined,
                title: Strings.of(context).tontines,
                onTap: () => context.push(inside('tontines')),
              ),
            if (access.canSee('production'))
              _Tile(
                icon: Icons.soup_kitchen_outlined,
                title: Strings.of(context).production,
                onTap: () => context.push(inside('production')),
              ),
            if (access.canSee('staff'))
              _Tile(
                icon: Icons.groups_outlined,
                title: Strings.of(context).staffLabel,
                onTap: () => context.push(inside('personnel')),
              ),
            if (admin)
              _Tile(
                icon: Icons.person_add_alt,
                title: Strings.of(context).inviteSomeone,
                onTap: () => InviteGeneratorSheet.open(context,
                    orgId: org.id, onboarding: scope.onboarding),
              ),
            if (!session.isPlatformAdmin)
              _Tile(
                icon: Icons.business_center_outlined,
                title: Strings.of(context).applyForBusiness,
                onTap: () => context.push(Routes.applyForBusiness),
              ),
          ],

          // ---- Plateforme (platform admin only) ----
          if (platform) ...[
            const _Section(title: 'Plateforme'),
            _Tile(
              icon: Icons.business_outlined,
              title: Strings.of(context).businesses,
              onTap: () => context.push(Routes.console),
            ),
            _Tile(
              icon: Icons.inbox_outlined,
              title: Strings.of(context).applications,
              onTap: () => context.push(Routes.applications),
            ),
            _Tile(
              icon: Icons.add_business_outlined,
              title: Strings.of(context).newBusiness,
              onTap: () => context.push(Routes.newBusiness),
            ),
          ],

          // ---- Aide ----
          const _Section(title: 'Aide'),
          _Tile(
            icon: Icons.support_agent_outlined,
            title: 'Contacter le support',
            subtitle: 'Sur WhatsApp',
            onTap: () => Support.openWhatsApp(context),
          ),
          _Tile(
            icon: Icons.help_outline,
            title: 'Questions fréquentes',
            onTap: () => context.push(Routes.faq),
          ),

          // ---- À propos ----
          const _Section(title: 'À propos'),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: 'Politique de confidentialité',
            onTap: () => context.push(Routes.privacy),
          ),
          _Tile(
            icon: Icons.description_outlined,
            title: "Conditions d'utilisation",
            onTap: () => context.push(Routes.terms),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Text('Kaj', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    AppScope scope,
    dynamic session,
  ) async {
    final pending = await scope.db.pendingCount();
    if (!context.mounted) return;
    if (pending == 0) {
      session.signOut();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.of(context).unsentDataTitle),
        content: Text(Strings.of(context).unsentDataBody(pending)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Strings.of(context).stayConnected),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Strings.of(context).signOut),
          ),
        ],
      ),
    );
    if (confirmed == true) session.signOut();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

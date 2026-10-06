import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/security/security_settings.dart';
import '../../core/nav/router.dart';
import '../../l10n/strings.dart';
import '../admin/invite_generator_sheet.dart';
import '../cauris/path_card.dart';
import '../cauris/unlock_sheet.dart';
import 'pro_sheet.dart';
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

    // The door to pay (066): every badged tool opens it, and so does the
    // Kaj Pro tile below. Only an admin of the business may say "J'ai payé".
    void openPro() => ProSheet.open(
      context,
      org: org,
      terms: session.planTerms,
      admin: scope.admin,
      canRequest: org.isAdmin,
    );
    VoidCallback gated(String feature, VoidCallback go) =>
        access.isProLocked(feature)
            ? () => ProSheet.open(
                  context,
                  org: org,
                  terms: session.planTerms,
                  admin: scope.admin,
                  canRequest: org.isAdmin,
                  feature: feature,
                )
            : go;
    // Its price in cauris (085), on the grey badge.
    int? costOf(String feature) =>
        session.featuresFor(org.id)?.toolOf(feature)?.cost;

    return Scaffold(
      appBar: AppBar(title: Text(Strings.of(context).account)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Who you are: one card, and the way to your profile.
          KajCard(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              leading: CircleAvatar(
                radius: 24,
                child: Text(
                  (identity?.label ?? '?').characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              title: Text(
                identity?.label ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                [
                  if (identity?.phone != null) identity!.phone!,
                  if (live) Strings.of(context).myProfile,
                ].join(' · '),
              ),
              trailing: live ? const Icon(Icons.chevron_right) : null,
              onTap: live ? () => context.push(Routes.myProfile) : null,
            ),
          ),

          _Group(
            title: 'Mon compte',
            children: [
              if (live)
                _Tile(
                  icon: Icons.shield_outlined,
                  title: 'Sécurité',
                  subtitle: _securityLine(scope),
                  onTap: () => context.push(Routes.security),
                ),
              _Tile(
                icon: Icons.language,
                title: Strings.of(context).language,
                onTap: () => context.push(Routes.language),
              ),
              if (live && !session.isPlatformAdmin)
                _Tile(
                  icon: Icons.business_center_outlined,
                  title: Strings.of(context).applyForBusiness,
                  onTap: () => PathGate.guard(context, org, 'second_business',
                      () => context.push(Routes.applyForBusiness)),
                ),
              if (session.orgs.length > 1)
                _Tile(
                  icon: Icons.swap_horiz,
                  title: Strings.of(context).switchBusiness,
                  onTap: () => context.go(Routes.picker),
                ),
            ],
          ),

          if (live)
            _Group(
              title: org.name,
              children: [
                if (admin)
                  _Tile(
                    icon: Icons.admin_panel_settings_outlined,
                    title: Strings.of(context).administration,
                    onTap: () => context.push(inside('administration')),
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
                    onTap: () => InviteGeneratorSheet.open(
                      context,
                      orgId: org.id,
                      onboarding: scope.onboarding,
                    ),
                  ),
                // The plan, said plainly (066): what this business is on, and
                // the door to the other one. Drawn for every member so an
                // employee who meets a badge knows what it is.
                // Cauris (084): what doing well earns. Businesses only: an
                // association does not compete.
                if (admin && org.profile != 'church' && org.profile != 'association')
                  _Tile(
                    key: const Key('compte-cauris'),
                    icon: Icons.savings_outlined,
                    title: 'Mes cauris',
                    subtitle: 'Gagnés en vendant bien, à dépenser en outils Pro',
                    onTap: () => context.push(inside('cauris')),
                  ),
                // Académie Mara (087): every member learns, each at their
                // own level.
                _Tile(
                  key: const Key('compte-academy'),
                  icon: Icons.school_outlined,
                  title: 'Académie Mara',
                  subtitle: 'Des leçons de deux minutes, en images',
                  onTap: () => context.push(inside('academie')),
                ),
                _Tile(
                  icon: Icons.workspace_premium_outlined,
                  title: org.isPro ? 'Mara Pro' : 'Passer à Mara Pro',
                  subtitle: org.isPro
                      ? 'Formule active'
                      : 'Paie, analyses, comptabilité, équipe sans limite…',
                  onTap: openPro,
                ),
              ],
            ),

          if (live)
            _Group(
              title: 'Outils',
              children: [
                // Owner-only, the same full visibility the server requires for
                // the analytics functions themselves.
                if (org.visibility == 'full' && org.profile == 'retail')
                  _Tile(
                    icon: Icons.insights_outlined,
                    title: 'Analyses',
                    pro: access.isProLocked('analytics'),
                    proCost: costOf('analytics'),
                    onTap: gated(
                      'analytics',
                      () => context.push(inside('rapports/analyse')),
                    ),
                  ),
                if (access.canSee('reports'))
                  _Tile(
                    icon: Icons.menu_book_outlined,
                    title: Strings.of(context).accounting,
                    pro: access.isProLocked('accounting'),
                    proCost: costOf('accounting'),
                    onTap: gated(
                      'accounting',
                      () => context.push(inside('comptabilite')),
                    ),
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
                    onTap: () => PathGate.open(context, org, 'credits',
                        () => context.push(inside('credits'))),
                  ),
                if (access.canSee('tontines'))
                  _Tile(
                    icon: Icons.group_outlined,
                    title: Strings.of(context).tontines,
                    pro: access.isProLocked('tontines'),
                    proCost: costOf('tontines'),
                    onTap: gated(
                      'tontines',
                      () => context.push(inside('tontines')),
                    ),
                  ),
                if (access.canSee('production'))
                  _Tile(
                    icon: Icons.precision_manufacturing_outlined,
                    title: Strings.of(context).production,
                    onTap: () => context.push(inside('production')),
                  ),
              ],
            ),

          if (platform)
            _Group(
              title: 'Plateforme',
              children: [
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
            ),

          _Group(
            title: 'Aide',
            children: [
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
            ],
          ),

          _Group(
            title: 'À propos',
            children: [
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
            ],
          ),

          const SizedBox(height: 24),
          // Leaving, alone and apart: never next to a tap meant for
          // something else.
          OutlinedButton.icon(
            onPressed: () => _confirmSignOut(context, scope, session),
            icon: const Icon(Icons.logout),
            label: Text(Strings.of(context).signOut),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text('Mara', style: TextStyle(fontWeight: FontWeight.w600)),
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

/// A titled card of rows with hairlines between them (the settings fold).
/// Draws nothing when every row is conditional and none applies.
/// "Verrouillé après 5 min · empreinte" — where the phone's lock stands.
String _securityLine(AppScope scope) {
  final s = scope.security;
  if (s == null) return 'Code, appareils, mot de passe';
  final lock = s.effectiveLock;
  return [
    lock == null ? 'Jamais verrouillé' : 'Verrouillé après ${SecuritySettings.label(lock)}',
    if (s.biometric && s.biometricReady) 'empreinte',
    if (s.hideAmounts) 'montants cachés',
  ].join(' · ');
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          KajCard(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerHighest,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.pro = false,
    this.proCost,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// The tool is behind Kaj Pro on this business (066): drawn, greyed, with
  /// the badge — never hidden. The tap opens the door to pay.
  final bool pro;

  /// Its price in cauris, when the business may unlock it with them (085).
  final int? proCost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: pro ? theme.colorScheme.onSurfaceVariant : null,
      ),
      title: Text(
        title,
        style: pro
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: pro
          ? ProCostBadge(cost: proCost)
          : const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}


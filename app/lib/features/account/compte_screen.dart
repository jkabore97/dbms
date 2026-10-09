import 'package:flutter/material.dart';

import '../../core/l10n/locale_controller.dart';
import '../../core/theme/kaj_card.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/security/security_settings.dart';
import '../../core/nav/router.dart';
import '../../l10n/strings.dart';
import 'package:intl/intl.dart';

import '../../core/cauris/feature_states.dart';
import '../cauris/path_card.dart';
import '../cauris/unlock_sheet.dart';
import '../notify/notification_settings_sheet.dart';
import 'pro_sheet.dart';
import 'support.dart';
import '../offline/offline_sheet.dart';
import '../home/activity_switch.dart';
import '../common/attention_banner.dart';
import '../../core/notify/bell.dart';
import '../admin/admin_pill.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/shopper/shopper_repository.dart';
import '../shopper/shopper_profile_screen.dart' show DeleteAccountDialog;
import '../../core/notify/bell_room.dart';

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
  const CompteScreen({super.key, required this.org, this.shopper});

  final OrgSummary org;

  /// Where « Supprimer mon compte » sends its request; the live one when
  /// not given (a test passes its own).
  final ShopperRepository? shopper;

  Future<void> _askDeletion(BuildContext context) async {
    final scope = AppScope.of(context);
    final repo = shopper ?? ShopperRepository(scope.auth.client);
    final names = scope.session.orgs.map((o) => o.name).join(', ');
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteAccountDialog(
        message: context.tr('Votre compte est lié à {names} : vos ventes, votre stock et votre équipe y portent votre nom. Mara reçoit votre demande, vous contacte si une activité doit être transmise ou fermée, puis supprime votre compte et vos données personnelles sous 30 jours.', {'names': names}),
        confirmLabel: context.tr('Envoyer la demande'),
        // Read by Mara's team in Signalements, so in French whatever the
        // person's language.
        delete: () => repo.report(
          topic: 'other',
          message: 'Demande de suppression de compte (depuis Compte). Activités : $names.',
        ),
      ),
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(context.tr('Demande envoyée : Mara supprime votre compte et vous prévient.'))));
    }
  }

  /// The rows of Compte › Outils for this business, in order, by key.
  ///
  /// A shop and a farm see what they sell and make; an association keeps
  /// its books (comptabilité), its carnet — a cotisation, the hall's rent, a
  /// loan to a member are debts with no article — and its tontines, and
  /// never the shop's tools: no production (nothing is made from
  /// ingredients), no analyses or corrections of sales and deliveries.
  /// A tool Mara's switchboard hid here (104) is not listed: the carnet,
  /// the tontines and production through the dial's own keys, the rest
  /// by name.
  static List<String> toolsFor(OrgSummary org, OrgAccess access,
          {required bool admin}) =>
      [
        // Owner-only, the same full visibility the server requires for the
        // analytics functions themselves. A shop's, and a farm's (101).
        if (org.visibility == 'full' &&
            (org.profile == 'retail' || org.profile == 'farm') &&
            !access.isHidden('analytics'))
          'analytics',
        if (access.canSee('reports') && !access.isHidden('accounting'))
          'accounting',
        // Undo a sale or a purchase entered by mistake — or test data.
        // Owner/admin only, and only where there are sales and deliveries to
        // undo; the server refuses everyone else regardless.
        if (admin && org.profile == 'retail' && !access.isHidden('corrections'))
          'corrections',
        if (access.canSee('credits')) 'credits',
        if (access.canSee('tontines')) 'tontines',
        if (access.canSee('production') && !org.isAssociation) 'production',
      ];

  /// The row for the business's people (100): « Équipe » for an admin
  /// (adding people, their salary); for somebody the owner gave the staff
  /// tool (031's dial) who is not an admin, the payroll they were trusted
  /// with — unless Mara's switchboard hid the payroll (104); nothing for
  /// anyone else.
  static String? peopleRow(OrgAccess access, {required bool admin}) => admin
      ? 'team'
      : (access.canSee('staff') && !access.isHidden('payroll')
          ? 'payroll'
          : null);

  /// « 1 personne offerte », « Équipe sans limite », the seat taken — or,
  /// before the first setup, what opens it.
  static String? teamLine(BuildContext context, TeamSeats? t) {
    if (t == null) return null;
    if (t.unlimited) return context.tr('Équipe sans limite');
    if (!t.setupDone) return context.tr('Terminez la mise en route pour inviter une personne');
    if (t.open) return context.tr('1 personne offerte');
    return context.tr('Votre personne offerte est là');
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final session = scope.session;
    final live = scope.auth.hasLiveSession;
    final admin = org.isAdmin && live;
    final platform = session.isPlatformAdmin && live;
    final access = session.accessFor(org.id);
    final identity = session.identity;
    // The platform's help number (113), asked before « Contacter le support ».
    if (live) Support.warm(scope.auth.client);

    String inside(String rest) => Routes.inside(org.id, rest);
    final tools = toolsFor(org, access, admin: admin);
    final switchMode = live
        ? ActivitySwitch.of(context, org)
        : ActivitySwitch.modeFor(activities: session.orgs.length);

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
    // Its price in cauris (085), on the grey badge. An association earns
    // no cauris (084): its badge says a price only once Mara has given it
    // some to spend (100).
    int? costOf(String feature) =>
        org.isAssociation && !_hasWallet(session.featuresFor(org.id))
            ? null
            : session.featuresFor(org.id)?.toolOf(feature)?.cost;

    return Scaffold(
      // « Admin » (104): the command center, for a platform admin.
      appBar: AppBar(
        title: Text(Strings.of(context).account),
        actions: const [AdminPill(), SizedBox(width: 8), bellRoom],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Why « Compte » has a red number on a shop's or an association's
          // bar (122): the carnet's credits past their date — the carnet
          // opens from here, folded under Outils.
          if (live && tools.contains('credits') && scope.notify.isConfigured)
            _LateCredits(
              bell: scope.notify.bell,
              orgId: org.id,
              onOpen: () => PathGate.open(context, org, 'credits',
                  () => context.push(inside('credits'))),
            ),
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

          // Préférences: the language, French by default, English on demand.
          _Group(
            title: context.tr('Préférences'),
            children: [
              _LanguageChoice(controller: scope.localeController),
              // What rings, this device's ring with the app closed, and
              // « M'envoyer une notification test » (115).
              if (live)
                _Tile(
                  key: const Key('compte-notifications'),
                  icon: Icons.notifications_outlined,
                  title: context.tr('Notifications'),
                  subtitle: context.tr('Ce qui sonne, et une notification test'),
                  onTap: () => NotificationSettingsSheet.open(context,
                      notify: scope.notify, audiences: const {'shop', 'customer'}),
                ),
              // Working with no signal: the business's admins prepare it.
              if (admin) OfflineTile(org: org),
            ],
          ),

          _Group(
            title: context.tr('Mon compte'),
            children: [
              if (live)
                _Tile(
                  icon: Icons.shield_outlined,
                  title: context.tr('Sécurité'),
                  subtitle: _securityLine(scope),
                  onTap: () => context.push(Routes.security),
                ),
              // Another business of one's own, created at once (111); a
              // second needs Mara Pro (099), said by the lock and the gate.
              if (live && !session.isPlatformAdmin)
                _Tile(
                  key: const Key('compte-second-business'),
                  icon: Icons.business_center_outlined,
                  title: context.tr('Créer une autre activité'),
                  locked: PathGate.locks(context, org, 'second_business'),
                  onTap: () => PathGate.guard(context, org, 'second_business',
                      () => context.push(Routes.createBusiness)),
                ),
              // « Changer d'activité »: the picker with several; with one
              // that is the person's own (122), the sheet — a second one, or
              // why it needs Mara Pro.
              if (switchMode != ActivitySwitchMode.none)
                _Tile(
                  key: const Key('compte-switch'),
                  icon: Icons.swap_horiz,
                  title: Strings.of(context).switchBusiness,
                  onTap: () => ActivitySwitch.open(context, org, switchMode),
                ),
            ],
          ),

          // What the person buys on the street, as anyone does (113): the
          // shopper's own pages, the same for every kind of business.
          if (live)
            _Group(
              title: context.tr('Mes achats'),
              children: [
                _Tile(
                  key: const Key('compte-my-orders'),
                  icon: Icons.receipt_long_outlined,
                  title: context.tr('Mes commandes'),
                  onTap: () => context.push(Routes.myOrders),
                ),
                _Tile(
                  key: const Key('compte-favourites'),
                  icon: Icons.favorite_border,
                  title: context.tr('Mes vitrines favorites'),
                  onTap: () => context.push(Routes.favourites),
                ),
                _Tile(
                  key: const Key('compte-addresses'),
                  icon: Icons.home_work_outlined,
                  title: context.tr('Mes adresses de livraison'),
                  onTap: () => context.push(Routes.addresses),
                ),
              ],
            ),

          if (live)
            _Group(
              open: true,
              title: org.name,
              children: [
                if (admin)
                  _Tile(
                    icon: Icons.admin_panel_settings_outlined,
                    title: Strings.of(context).administration,
                    onTap: () => context.push(inside('administration')),
                  ),
                // « Équipe » (100): the people, adding one, their salary —
                // one place where « Personnel » and « Inviter » were two.
                if (peopleRow(access, admin: admin) == 'team')
                  _Tile(
                    key: const Key('compte-team'),
                    icon: Icons.groups_outlined,
                    title: context.tr('Équipe'),
                    subtitle: teamLine(context, session.featuresFor(org.id)?.team),
                    onTap: () => context.push(inside('equipe')),
                  )
                else if (peopleRow(access, admin: admin) == 'payroll')
                  _Tile(
                    key: const Key('compte-payroll'),
                    icon: Icons.payments_outlined,
                    title: context.tr('Paie et journées'),
                    pro: access.isProLocked('payroll'),
                    proCost: costOf('payroll'),
                    onTap: gated('payroll', () => context.push(inside('personnel'))),
                  ),
                // An association earns no cauris (084), but spends what Mara
                // gives it (100): its wallet shows once there is something
                // in it.
                if (admin && org.isAssociation && _hasWallet(session.featuresFor(org.id)))
                  _Tile(
                    key: const Key('compte-cauris'),
                    icon: Icons.savings_outlined,
                    title: context.tr('Mes cauris'),
                    subtitle: _walletLine(context, session.featuresFor(org.id)!),
                    onTap: () => context.push(inside('chemin')),
                  ),
                // The plan, said plainly (066): what this business is on, and
                // the door to the other one. Drawn for every member so an
                // employee who meets a badge knows what it is.
                // Le Chemin (097): the steps, the tools they open and the
                // cauris they pay. Businesses only: an association does not
                // compete.
                if (admin && !org.isAssociation)
                  _Tile(
                    key: const Key('compte-chemin'),
                    icon: Icons.route_outlined,
                    title: context.tr('Mon chemin'),
                    subtitle: context.tr('{n} cauris', {
                      'n': session.featuresFor(org.id)?.balance ?? 0,
                    }),
                    onTap: () => context.push(inside('chemin')),
                  ),
                _Tile(
                  icon: Icons.workspace_premium_outlined,
                  title: org.isPro ? context.tr('Mara Pro') : context.tr('Passer à Mara Pro'),
                  subtitle: org.isPro
                      ? context.tr('Formule active')
                      : context.tr('Paie, analyses, comptabilité, équipe sans limite…'),
                  onTap: openPro,
                ),
              ],
            ),

          if (live)
            _Group(
              title: context.tr('Outils'),
              children: [
                if (tools.contains('analytics'))
                  _Tile(
                    icon: Icons.insights_outlined,
                    title: context.tr('Analyses'),
                    pro: access.isProLocked('analytics'),
                    proCost: costOf('analytics'),
                    onTap: gated(
                      'analytics',
                      () => context.push(inside('rapports/analyse')),
                    ),
                  ),
                if (tools.contains('accounting'))
                  _Tile(
                    key: const Key('compte-accounting'),
                    icon: Icons.menu_book_outlined,
                    title: Strings.of(context).accounting,
                    pro: access.isProLocked('accounting'),
                    proCost: costOf('accounting'),
                    onTap: gated(
                      'accounting',
                      () => context.push(inside('comptabilite')),
                    ),
                  ),
                if (tools.contains('corrections'))
                  _Tile(
                    icon: Icons.history_toggle_off_outlined,
                    title: context.tr('Corrections'),
                    onTap: () => context.push(inside('corrections')),
                  ),
                if (tools.contains('credits'))
                  _Tile(
                    key: const Key('compte-credits'),
                    icon: Icons.handshake_outlined,
                    title: Strings.of(context).creditBook,
                    locked: PathGate.locks(context, org, 'credits'),
                    onTap: () => PathGate.open(context, org, 'credits',
                        () => context.push(inside('credits'))),
                  ),
                if (tools.contains('tontines'))
                  _Tile(
                    key: const Key('compte-tontines'),
                    icon: Icons.group_outlined,
                    title: Strings.of(context).tontines,
                    pro: access.isProLocked('tontines'),
                    proCost: costOf('tontines'),
                    onTap: gated(
                      'tontines',
                      () => context.push(inside('tontines')),
                    ),
                  ),
                if (tools.contains('production'))
                  _Tile(
                    key: const Key('compte-production'),
                    icon: Icons.precision_manufacturing_outlined,
                    title: Strings.of(context).production,
                    locked: PathGate.locks(context, org, 'production'),
                    onTap: () => PathGate.open(context, org, 'production',
                        () => context.push(inside('production'))),
                  ),
              ],
            ),

          if (platform)
            _Group(
              title: context.tr('Plateforme'),
              children: [
                _Tile(
                  icon: Icons.business_outlined,
                  title: Strings.of(context).businesses,
                  onTap: () => AdminTrail.enter(context, to: Routes.consoleBusinesses),
                ),
                _Tile(
                  icon: Icons.inbox_outlined,
                  title: context.tr('Activités créées'),
                  onTap: () => AdminTrail.enter(context, to: Routes.applications),
                ),
                _Tile(
                  icon: Icons.add_business_outlined,
                  title: Strings.of(context).newBusiness,
                  onTap: () => context.push(Routes.newBusiness),
                ),
              ],
            ),

          _Group(
            title: context.tr('Aide'),
            children: [
              _Tile(
                icon: Icons.support_agent_outlined,
                title: context.tr('Contacter le support'),
                subtitle: context.tr('Sur WhatsApp'),
                onTap: () => Support.openWhatsApp(context),
              ),
              _Tile(
                icon: Icons.help_outline,
                title: context.tr('Questions fréquentes'),
                onTap: () => context.push(Routes.faq),
              ),
            ],
          ),

          _Group(
            title: context.tr('À propos'),
            children: [
              _Tile(
                icon: Icons.privacy_tip_outlined,
                title: context.tr('Politique de confidentialité'),
                onTap: () => context.push(Routes.privacy),
              ),
              _Tile(
                icon: Icons.description_outlined,
                title: context.tr('Conditions d\'utilisation'),
                onTap: () => context.push(Routes.terms),
              ),
            ],
          ),

          // Google Play's rule, and a person's right: every account can ask to
          // be deleted from inside the app. A member's account carries the
          // business's books (sales, stock, pay) under their name, so the
          // server never deletes it on the spot (113's
          // delete_my_account_check): the request goes to Mara, through
          // « Signaler un problème » (À faire › Signalements), with the
          // person's contact, and Mara closes the account.
          if (live)
            _Group(
              title: context.tr('Mes données'),
              children: [
                _Tile(
                  key: const Key('compte-delete-account'),
                  icon: Icons.delete_outline,
                  title: context.tr('Supprimer mon compte'),
                  subtitle: context.tr('Mara vous le confirme sous 30 jours'),
                  onTap: () => _askDeletion(context),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(context.tr('Mara'), style: const TextStyle(fontWeight: FontWeight.w600)),
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

/// « 2 crédits ont dépassé leur date de remboursement », with « Ouvrir le
/// carnet » — live with the bar's own number.
class _LateCredits extends StatelessWidget {
  const _LateCredits({required this.bell, required this.orgId, required this.onOpen});

  final Bell bell;
  final String orgId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: bell,
        builder: (context, _) {
          final n = bell.homeCount(orgId, 'credit');
          if (n <= 0) return const SizedBox.shrink();
          return AttentionBanner(
            key: const Key('compte-credit-attention'),
            icon: Icons.handshake_outlined,
            margin: const EdgeInsets.only(top: 4, bottom: 12),
            title: n == 1
                ? context.tr('1 crédit a dépassé sa date de remboursement')
                : context.tr('{n} crédits ont dépassé leur date de remboursement', {'n': n}),
            stays: context.tr('Le chiffre rouge sur « Compte » reste tant que ces crédits ne sont pas remboursés : ouvrir cette page ne l\'efface pas.'),
            items: [
              AttentionItem(
                id: 'credits',
                label: Strings.of(context).creditBook,
                chip: context.tr('En retard'),
                actionLabel: context.tr('Ouvrir le carnet'),
                onAction: onOpen,
              ),
            ],
          );
        },
      );
}

/// The wallet is worth a row: something in it, or promotional points.
bool _hasWallet(FeatureStates? f) =>
    f != null && (f.balance > 0 || f.promo.isNotEmpty);

/// « 250 cauris · dont 200 avant le 30/11 ».
String _walletLine(BuildContext context, FeatureStates f) => [
      context.tr('{n} cauris', {'n': f.balance}),
      if (f.promo.isNotEmpty)
        context.tr('dont {n} à utiliser avant le {date}', {
          'n': f.promo.first.points,
          'date': DateFormat('dd/MM').format(f.promo.first.until),
        }),
    ].join(' · ');

/// A titled card of rows with hairlines between them (the settings fold).
/// Draws nothing when every row is conditional and none applies.
/// "Verrouillé après 5 min · empreinte" — where the phone's lock stands.
String _securityLine(AppScope scope) {
  final s = scope.security;
  if (s == null) return translate(trCurrent, 'Code, appareils, mot de passe');
  final lock = s.effectiveLock;
  return [
    lock == null
        ? translate(trCurrent, 'Jamais verrouillé')
        : translate(trCurrent, 'Verrouillé après {delay}',
            {'delay': translate(trCurrent, SecuritySettings.label(lock))}),
    if (s.biometric && s.biometricReady) translate(trCurrent, 'empreinte'),
    if (s.hideAmounts) translate(trCurrent, 'montants cachés'),
  ].join(' · ');
}

/// The language (Compte › Préférences): a choice between the two, each
/// named in itself, the current one ticked — applied at once and kept on
/// the phone (122: « switches from English to French, not a switch to
/// activate English »). Until one is tapped it follows the phone.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({required this.controller});

  final LocaleController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Padding(
          key: const Key('compte-language'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.translate),
              const SizedBox(width: 16),
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: true,
                  segments: const [
                    // Each language named in itself.
                    ButtonSegment(value: 'fr', label: Text('Français')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {
                    controller.effective.languageCode == 'en' ? 'en' : 'fr'
                  },
                  onSelectionChanged: (s) => controller.choose(Locale(s.first)),
                ),
              ),
            ],
          ),
        ),
      );
}

/// A titled group of rows that folds open and shut, so Compte reads as a
/// short list of headings rather than one long page.
class _Group extends StatefulWidget {
  const _Group({required this.title, required this.children, this.open = false});

  final String title;
  final List<Widget> children;

  /// Folded unless said: the business's own group opens, the rest wait.
  final bool open;

  @override
  State<_Group> createState() => _GroupState();
}

class _GroupState extends State<_Group> {
  late bool _open = widget.open;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final children = widget.children;
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('group-$title'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(
                children: [
                  Expanded(
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
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        size: 20, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
          if (_open) KajCard(
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
    this.locked = false,
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

  /// Still ahead on the earned path (089): greyed, with a lock.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: pro || locked ? theme.colorScheme.onSurfaceVariant : null,
      ),
      title: Text(
        title,
        style: pro || locked
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: pro
          ? ProCostBadge(cost: proCost)
          : locked
              ? Icon(Icons.lock, size: 20, color: theme.colorScheme.onSurfaceVariant)
              : const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}


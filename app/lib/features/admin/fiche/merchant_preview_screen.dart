import 'package:flutter/material.dart';

import '../../../core/access/org_access.dart';
import '../../../core/access/plan_terms.dart';
import '../../../core/auth/models.dart';
import '../../../core/cauris/feature_states.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/nav/session.dart';
import '../../../core/notify/notifications_repository.dart';
import '../../../core/theme/kaj_theme.dart';
import '../../../core/theme/mara_mark.dart';
import '../../account/compte_screen.dart';
import '../../home/business_shell.dart';
import '../../pro/pro_strip.dart';
import 'look_only_view.dart';

/// « Voir comme le commerçant » (106): a business's home and its Compte,
/// drawn exactly as its owner sees them — the owner's role, the plan's
/// locks, what Mara's switchboard hides — on a phone's width, beside the
/// command center. Look, scroll, never touch: every tap, every field and
/// every keyboard press stays out, so nothing can be saved from here.
///
/// That is a courtesy of the app and nothing more. The person looking is a
/// platform admin, and the server lets a platform admin write; the
/// preview's lock is that no button in it can be reached.
class MerchantPreviewScreen extends StatefulWidget {
  const MerchantPreviewScreen({super.key, required this.org});

  /// The business as the platform's list has it (my_orgs, 010).
  final OrgSummary org;

  static Future<void> open(BuildContext context, OrgSummary org) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) => MerchantPreviewScreen(org: org),
      ));

  @override
  State<MerchantPreviewScreen> createState() => _MerchantPreviewScreenState();
}

class _MerchantPreviewScreenState extends State<MerchantPreviewScreen> {
  OwnerViewSession? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final scope = AppScope.read(context);
    if (scope == null) return;
    // What the owner's phone reads: the business's states — its plan, its
    // unlocks, what the switchboard hides (feature_states, 104). Without
    // them (no signal) the preview says the plan from the list alone.
    FeatureStates? states;
    try {
      states = await scope.admin.featureStates(widget.org.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _session = OwnerViewSession(
        real: scope.session,
        org: ownerOf(widget.org),
        states: states,
      );
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final session = _session;
    return Scaffold(
      key: const Key('merchant-preview'),
      backgroundColor: const Color(0xFF2A2927),
      appBar: AppBar(
        backgroundColor: maraDeep,
        foregroundColor: maraPaper,
        title: Text(context.tr('Voir comme le commerçant'),
            style: const TextStyle(color: maraPaper, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreviewBanner(name: widget.org.name),
          Expanded(
            child: _loading || session == null
                ? const Center(child: CircularProgressIndicator(color: maraCaramel))
                : LayoutBuilder(builder: (context, box) {
                    final owner = session.org;
                    final pages = [
                      (context.tr('Accueil'), _homeOf(owner)),
                      (context.tr('Compte'), _compteOf(owner)),
                    ];
                    // A desk: the two screens side by side, each a phone.
                    if (box.maxWidth >= 860) {
                      return Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (label, page) in pages)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                                child: Column(
                                  children: [
                                    Text(label,
                                        style: const TextStyle(
                                            color: maraCaramel,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.1)),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: _OwnerFrame(
                                        base: scope,
                                        session: session,
                                        width: 390,
                                        child: page,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }
                    // A phone: one screen at a time.
                    return DefaultTabController(
                      length: pages.length,
                      child: Column(
                        children: [
                          TabBar(
                            labelColor: maraCaramel,
                            unselectedLabelColor: maraPaper,
                            indicatorColor: maraCaramel,
                            tabs: [for (final (label, _) in pages) Tab(text: label)],
                          ),
                          Expanded(
                            child: TabBarView(
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                for (final (_, page) in pages)
                                  _OwnerFrame(
                                    base: scope,
                                    session: session,
                                    width: box.maxWidth,
                                    framed: false,
                                    child: page,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
          ),
        ],
      ),
    );
  }

  /// The business's home as its address draws it (_withOrg + BusinessShell).
  Widget _homeOf(OrgSummary owner) => ProfileTheme(
        profile: owner.profile,
        theme: owner.theme,
        child: ProStrip(org: owner, child: BusinessShell(org: owner)),
      );

  Widget _compteOf(OrgSummary owner) => ProfileTheme(
        profile: owner.profile,
        theme: owner.theme,
        child: ProStrip(org: owner, child: CompteScreen(org: owner)),
      );
}

/// The business as its owner's org list has it: the owner's role, its
/// effective plan — not the platform admin's « platform_admin ».
OrgSummary ownerOf(OrgSummary org) => OrgSummary(
      id: org.id,
      name: org.name,
      profile: org.profile,
      slug: org.slug,
      currency: org.currency,
      roles: const ['owner'],
      visibility: 'full',
      theme: org.theme,
      suspended: org.suspended,
      plan: org.plan,
      ownerName: org.ownerName,
    );

/// What the owner's phone is told it may see and use: the plan's locks as
/// for any member (a platform admin has none — the owner does), and what
/// the switchboard hides (104).
OrgAccess ownerAccess(OrgSummary owner, FeatureStates? states, PlanTerms terms) {
  final pro = owner.isPro || (states?.isPro ?? false);
  final locked = pro
      ? const <String>{}
      : terms.proFeatures.toSet().difference(states?.unlocked ?? const {});
  final hidden = states?.hidden ?? const <String>{};
  return locked.isEmpty && hidden.isEmpty
      ? OrgAccess.allEdit
      : OrgAccess.admin(proLocked: locked, hidden: hidden);
}

/// The session the preview draws with: one business, its owner's role,
/// plan and visibility; every other answer the real session's. Nothing
/// here moves anything: no resolve, no refresh, no sign-out, no feature
/// reload, no chart cached.
class OwnerViewSession extends SessionController {
  OwnerViewSession({
    required this.real,
    required this.org,
    required this.states,
  }) : _access = ownerAccess(org, states, real.planTerms),
       super(
          db: real.db,
          auth: real.auth,
          admin: real.admin,
          accounting: real.accounting,
        );

  final SessionController real;

  /// The business with the owner's role (see [ownerOf]).
  final OrgSummary org;
  final FeatureStates? states;
  final OrgAccess _access;

  @override
  SessionPhase get phase => SessionPhase.ready;
  @override
  LocalIdentity? get identity => real.identity;
  @override
  List<OrgSummary> get orgs => [org];
  @override
  OrgSummary? orgById(String? id) => id == org.id ? org : null;
  @override
  String? get lastOrgId => org.id;
  @override
  OrgAccess accessFor(String? orgId) =>
      orgId == org.id ? _access : OrgAccess.allEdit;
  @override
  FeatureStates? featuresFor(String? orgId) => orgId == org.id ? states : null;
  @override
  bool get isPlatformAdmin => false;
  @override
  PlanTerms get planTerms => real.planTerms;
  @override
  bool get orgsFromCache => false;
  @override
  String? get notice => null;

  @override
  Future<bool> adoptGoogleSession() async => false;
  @override
  Future<void> reloadFeatures(String orgId) async {}
  @override
  Future<void> cacheChart(OrgSummary org) async {}
  @override
  Future<void> refresh({bool force = false}) async {}
  @override
  Future<void> resolveOrgs() async {}
  @override
  Future<void> signOut() async {}
  @override
  void openOrg(String orgId) {}
  @override
  void leaveOrg() {}
  @override
  bool lockNow() => false;
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('merchant-preview-banner'),
      color: maraCaramel,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, color: maraBlack),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Vous voyez {name} comme son propriétaire', {'name': name}),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: maraBlack, fontWeight: FontWeight.w800),
                ),
                Text(
                  context.tr('Son rôle, sa formule, ce que Mara lui montre. Lecture seule : rien ne s\'enregistre d\'ici.'),
                  style: theme.textTheme.bodySmall?.copyWith(color: maraBlack),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('merchant-preview-close'),
            style: TextButton.styleFrom(foregroundColor: maraBlack),
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(context.tr('Quitter')),
          ),
        ],
      ),
    );
  }
}

/// One screen of the business on a phone's width, under the owner's
/// scope, to look at and scroll only (see [LookOnlyView]).
class _OwnerFrame extends StatelessWidget {
  const _OwnerFrame({
    required this.base,
    required this.session,
    required this.width,
    required this.child,
    this.framed = true,
  });

  /// The app's scope: the same repositories (every read is the real one).
  final AppScope base;

  /// The owner's eyes.
  final SessionController session;
  final double width;
  final bool framed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = base;
    final view = LookOnlyView(
      width: width,
      child: AppScope(
        session: session,
        localeController: s.localeController,
        db: s.db,
        auth: s.auth,
        admin: s.admin,
        reports: s.reports,
        accounting: s.accounting,
        console: s.console,
        farm: s.farm,
        invoicing: s.invoicing,
        retail: s.retail,
        staff: s.staff,
        capture: s.capture,
        onboarding: s.onboarding,
        credit: s.credit,
        tontine: s.tontine,
        production: s.production,
        // The bell reads nothing: the platform admin's own bell is not
        // the owner's.
        notify: NotificationsRepository(null),
        analytics: s.analytics,
        sync: s.sync,
        security: s.security,
        securityApi: s.securityApi,
        wavePay: s.wavePay,
        child: child,
      ),
    );
    if (!framed) return view;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: maraGrey.withValues(alpha: 0.5), width: 6),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(22), child: view),
    );
  }
}

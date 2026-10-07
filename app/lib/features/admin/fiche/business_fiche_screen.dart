import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/auth/models.dart';
import '../../../core/console/command_center.dart';
import '../../../core/console/fiche_repository.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/theme/mara_mark.dart';
import '../../auth/org_picker_screen.dart' show kindSingular;
import '../cauris_gifts_screen.dart' show KindBadge;
import '../team_screen.dart';
import 'fiche_features_tab.dart';
import 'fiche_identity_tab.dart';
import 'fiche_journal_tab.dart';
import 'fiche_overview_tab.dart';
import 'fiche_pro_tab.dart';
import 'fiche_vitrine_tab.dart';
import 'fiche_widgets.dart';
import 'merchant_preview_screen.dart';

/// The fiche entreprise (batch 104, 106): one business — a shop, a farm or
/// an association — on one page of the command center, as only the
/// platform sees it. Aperçu · Identité · Vitrine · Fonctions · Équipe ·
/// Pro et cauris · Journal, and « Voir comme le commerçant ».
///
/// Everything it changes goes through the server's platform functions,
/// which refuse anybody but a platform admin and write each change in the
/// journal with its undo; the owner is told when Mara changes their
/// vitrine or their identity. The screen is drawn for a platform admin
/// only — a courtesy; the server is the lock.
class BusinessFicheScreen extends StatefulWidget {
  const BusinessFicheScreen({
    super.key,
    required this.orgId,
    this.initialTab,
    this.fiche,
    this.center,
  });

  final String orgId;

  /// The tab to open on: one of [FicheTab]'s keys ('apercu', 'identite',
  /// 'vitrine', 'fonctions', 'equipe', 'pro', 'journal').
  final String? initialTab;

  /// The server, for a test; the app's own otherwise.
  final FicheRepository? fiche;

  /// The command center's journal and its « Annuler » (105), for a test.
  final CommandCenterRepository? center;

  @override
  State<BusinessFicheScreen> createState() => _BusinessFicheScreenState();
}

class _BusinessFicheScreenState extends State<BusinessFicheScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: FicheTab.values.length,
    vsync: this,
    initialIndex: FicheTab.indexOf(widget.initialTab),
  );
  FicheRepository? _fiche;
  OrgOverview? _overview;
  String? _error;
  bool _loading = true;

  /// Bumped after every change, so the tabs that read the business again.
  int _version = 0;

  FicheRepository get fiche =>
      _fiche ??= widget.fiche ?? FicheRepository(AppScope.read(context)?.auth.client);
  CommandCenterRepository? _center;
  CommandCenterRepository get center => _center ??=
      widget.center ?? CommandCenterRepository(AppScope.read(context)?.auth.client);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      // The business's states for the owner's own screens folded in here
      // (the vitrine editor, Équipe): its plan, unlocks, what is hidden.
      final session = AppScope.read(context)?.session;
      if (session != null && session.orgById(widget.orgId) != null) {
        unawaited(session.reloadFeatures(widget.orgId));
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await fiche.overview(widget.orgId);
      if (!mounted) return;
      setState(() {
        _overview = o;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  /// After a change made from a tab: the fiche, the session's list (the
  /// name in the picker, the plan's badge) and the tabs read again.
  Future<void> _changed() async {
    setState(() => _version++);
    final session = AppScope.read(context)?.session;
    await _load();
    if (session != null) {
      unawaited(session.refresh(force: true));
      if (session.orgById(widget.orgId) != null) {
        unawaited(session.reloadFeatures(widget.orgId));
      }
    }
  }

  /// The business as the app's screens take it: the platform's own list
  /// entry when the session has it, else the fiche's figures.
  OrgSummary _org(OrgOverview o) =>
      AppScope.maybeOf(context)?.session.orgById(widget.orgId) ??
      OrgSummary(
        id: o.id,
        name: o.name,
        profile: o.profile,
        slug: o.slug,
        currency: o.currency,
        roles: const ['platform_admin'],
        suspended: o.suspendedAt != null,
        plan: o.plan,
        ownerName: o.owner?.name,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = _overview;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      key: const Key('business-fiche'),
      appBar: AppBar(
        backgroundColor: maraDeep,
        foregroundColor: maraPaper,
        titleSpacing: 0,
        title: o == null
            ? Text(context.tr('Fiche entreprise'))
            : Row(
                children: [
                  KindBadge(profile: o.profile),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: maraPaper, fontWeight: FontWeight.w800)),
                        Text(
                          '${kindSingular(context, o.profile)} · ${o.slug}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: maraPaper.withValues(alpha: 0.75)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (o != null)
            wide
                ? Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FilledButton.icon(
                      key: const Key('fiche-preview'),
                      style: FilledButton.styleFrom(
                          backgroundColor: maraCaramel, foregroundColor: maraBlack),
                      onPressed: () => MerchantPreviewScreen.open(context, _org(o)),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(context.tr('Voir comme le commerçant')),
                    ),
                  )
                : IconButton(
                    key: const Key('fiche-preview'),
                    tooltip: context.tr('Voir comme le commerçant'),
                    onPressed: () => MerchantPreviewScreen.open(context, _org(o)),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _loading ? null : _changed,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: maraCaramel,
          unselectedLabelColor: maraPaper.withValues(alpha: 0.8),
          indicatorColor: maraCaramel,
          tabs: [
            for (final t in FicheTab.values)
              Tab(
                key: Key('fiche-tab-${t.key}'),
                height: 48,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, size: 18),
                    const SizedBox(width: 6),
                    Text(context.tr(t.label)),
                  ],
                ),
              ),
          ],
        ),
      ),
      body: o == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error ?? '', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: Text(context.tr('Réessayer')),
                          ),
                        ],
                      ),
                    ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                FicheOverviewTab(
                  overview: o,
                  onTab: (t) => _tabs.animateTo(t.index),
                  onPreview: () => MerchantPreviewScreen.open(context, _org(o)),
                ),
                FicheIdentityTab(
                  key: ValueKey('identity-$_version'),
                  overview: o,
                  fiche: fiche,
                  center: center,
                  onChanged: _changed,
                ),
                FicheVitrineTab(
                  key: ValueKey('vitrine-$_version'),
                  overview: o,
                  org: _org(o),
                  onChanged: _changed,
                ),
                FicheFeaturesTab(
                  key: ValueKey('features-$_version'),
                  overview: o,
                  fiche: fiche,
                  center: center,
                  onChanged: _changed,
                ),
                _TeamTab(org: _org(o)),
                FicheProTab(
                  key: ValueKey('pro-$_version'),
                  overview: o,
                  org: _org(o),
                  center: center,
                  onChanged: _changed,
                ),
                FicheJournalTab(
                  key: ValueKey('journal-$_version'),
                  org: _org(o),
                  center: center,
                  onChanged: _changed,
                ),
              ],
            ),
    );
  }
}

/// Équipe: the owner's own screen, as Mara (103: the platform may do what
/// the owner may), without its own top bar.
class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.org});

  final OrgSummary org;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return TeamScreen(
      org: org,
      admin: scope.admin,
      onboarding: scope.onboarding,
      embedded: true,
    );
  }
}

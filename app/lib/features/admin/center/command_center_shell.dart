import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/console/command_center.dart';
import '../../../core/format/money.dart';
import '../../../core/format/money_text.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/nav/router.dart';
import '../../../core/nav/session.dart';
import '../../../core/theme/mara_mark.dart';
import '../../../core/theme/scroll_hint.dart';
import '../../../core/notify/notifications_repository.dart';
import '../admin_pill.dart';
import '../../notify/notifications_screen.dart' show NotificationBell;
import 'center_search.dart';
import '../../../core/notify/bell_room.dart';

/// One page of a place: its name and its address. [leaves] marks a page
/// outside the center (the street).
class CenterPage {
  const CenterPage(this.label, this.route, {this.leaves = false});

  final String label;
  final String route;
  final bool leaves;
}

/// One of the center's five places (135): its question, its place on the
/// rail and the bar, its pages. The first page is where the place opens;
/// [owns] are the further addresses it is the place of (a business's
/// fiche under Clients, the types of business under Réglages). [tabs]
/// draws the pages as a switcher at the top.
class CenterSection {
  const CenterSection({
    required this.key,
    required this.label,
    required this.question,
    required this.icon,
    required this.pages,
    this.owns = const [],
    this.tabs = true,
  });

  final String key;
  final String label;
  final String question;
  final IconData icon;
  final List<CenterPage> pages;
  final List<String> owns;
  final bool tabs;

  String get root => pages.first.route;
}

/// The five places (135), each answering one question, in the rail's and
/// the bar's order. Every page of before is one of their pages, or a page
/// one of them owns: no address was lost.
List<CenterSection> centerSections(BuildContext context) => [
  CenterSection(
    key: 'today',
    label: context.tr('Aujourd\'hui'),
    question: context.tr('Qu\'est-ce qui m\'attend ?'),
    icon: Icons.today_outlined,
    tabs: false,
    pages: [
      CenterPage(context.tr('Aujourd\'hui'), Routes.console),
      CenterPage(context.tr('Analyses'), Routes.platformAnalytics),
    ],
    owns: const [Routes.consoleNotifications],
  ),
  CenterSection(
    key: 'clients',
    label: context.tr('Clients'),
    question: context.tr('Qui sont mes clients ?'),
    icon: Icons.groups_outlined,
    pages: [
      CenterPage(context.tr('Activités'), Routes.consoleBusinesses),
      // People create their business at once (111): the ones created,
      // newest first, are clients — so here (135).
      CenterPage(context.tr('Créées'), Routes.applications),
      CenterPage(context.tr('Personnes'), Routes.consolePeople),
      CenterPage(context.tr('Livreurs'), Routes.consoleCouriers),
      CenterPage(context.tr('Formateurs'), Routes.trainers),
    ],
    owns: const ['${Routes.consoleBusinesses}/', '${Routes.consoleCouriers}/dossier/'],
  ),
  CenterSection(
    key: 'money',
    label: context.tr('Argent'),
    question: context.tr('Combien ça rapporte ?'),
    icon: Icons.account_balance_wallet_outlined,
    pages: [
      CenterPage(context.tr('Pro'), Routes.consolePro),
      CenterPage(context.tr('Paiements'), Routes.consoleWave),
      CenterPage(context.tr('Livreurs'), Routes.consoleSettlement),
      CenterPage(context.tr('Cauris'), Routes.consoleCaurisGifts),
    ],
  ),
  CenterSection(
    key: 'street',
    label: context.tr('La rue'),
    question: context.tr('Que voient les clients ?'),
    icon: Icons.storefront_outlined,
    pages: [
      CenterPage(context.tr('À la une'), Routes.consoleFeatured),
      CenterPage(context.tr('Exemples'), Routes.consoleShowcase),
      CenterPage(context.tr('Signalements'), Routes.consoleReports),
    ],
  ),
  CenterSection(
    key: 'settings',
    label: context.tr('Réglages'),
    question: context.tr('Quelles sont les règles ?'),
    icon: Icons.tune,
    tabs: false,
    pages: [CenterPage(context.tr('Réglages'), Routes.consoleSettings)],
    owns: const [
      '${Routes.consoleSettings}/',
      Routes.consoleKinds,
      Routes.consoleRequestForm,
      Routes.consoleJournal,
      Routes.consoleAudit,
    ],
  ),
];

/// The place an address belongs to: the longest page (or owned prefix)
/// that matches it. « Aujourd'hui » only at its own address.
CenterSection sectionFor(List<CenterSection> sections, String path) {
  CenterSection best = sections.first;
  var length = -1;
  for (final s in sections) {
    for (final route in [
      for (final p in s.pages)
        if (!p.leaves) p.route,
      ...s.owns,
    ]) {
      final hit = route.endsWith('/')
          ? path.startsWith(route)
          : route == Routes.console
          ? path == route
          : path == route || path.startsWith('$route/');
      if (hit && route.length > length) {
        best = s;
        length = route.length;
      }
    }
  }
  return best;
}

/// The page of [section] an address is (or is under): its tab lit.
CenterPage? pageFor(CenterSection section, String path) {
  CenterPage? on;
  for (final p in section.pages) {
    if (p.leaves) continue;
    final hit = p.route == Routes.console
        ? path == p.route
        : path == p.route || path.startsWith('${p.route}/');
    if (hit && (on == null || p.route.length > on.route.length)) on = p;
  }
  return on;
}

/// Where back goes from a page a place opens beneath its first (135):
/// the analyses and the bell to « Aujourd'hui », a card's page to the
/// cards, the types and the creation flow to « Création », the journal to
/// « Sécurité, journal ». Null: the first page of a place (back leaves).
String? centerParent(String path) {
  if (path == Routes.platformAnalytics || path == Routes.consoleNotifications) {
    return Routes.console;
  }
  if (path.startsWith('${Routes.consoleSettings}/')) return Routes.consoleSettings;
  if (path == Routes.consoleKinds || path == Routes.consoleRequestForm) {
    return Routes.consoleSettingsCard('creation');
  }
  if (path == Routes.consoleJournal || path == Routes.consoleAudit) {
    return Routes.consoleSettingsCard('securite');
  }
  return null;
}

/// The pages that have their own search field, filtering the page in place
/// (135 review): the businesses, the people, the cauris gifts' business,
/// Réglages' « Chercher un réglage… ». On them the top bar's search is a
/// button — one field per screen — and Ctrl/Cmd+K still opens it.
const centerOwnSearch = {
  Routes.consoleBusinesses,
  Routes.consolePeople,
  Routes.consoleCaurisGifts,
  Routes.consoleSettings,
};

/// From this width the places stand in a rail at the left.
const centerWideFrom = 900.0;

/// Mara's command center: the rail (a computer) or the bar (a phone) with
/// the five places, the one search at the top (Ctrl/Cmd+K on a computer),
/// the place's pages as a switcher, and the page itself — the console's
/// screens, unchanged.
class CommandCenterShell extends StatefulWidget {
  const CommandCenterShell({
    super.key,
    required this.center,
    required this.child,
    this.platformAdmin,
    this.location,
  });

  final CommandCenterRepository center;
  final Widget child;

  /// Whether to open (tests say it outright); null reads the session.
  final bool? platformAdmin;

  /// The address shown (tests); null reads the router.
  final String? location;

  @override
  State<CommandCenterShell> createState() => _CommandCenterShellState();
}

class _CommandCenterShellState extends State<CommandCenterShell> {
  PlatformTodo? _badges;
  DateTime? _badgesAt;
  PlatformToday? _today;
  PlatformOverview? _overview;
  DateTime? _moneyAt;
  bool _moneyDone = false;

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  /// What waits, on the rail: asked when the center opens and again on a
  /// change of place, at most every half minute.
  Future<void> _loadBadges() async {
    final at = _badgesAt;
    if (at != null && DateTime.now().difference(at) < const Duration(seconds: 30)) return;
    _badgesAt = DateTime.now();
    if (!widget.center.isConfigured) return;
    try {
      final todo = await widget.center.todo();
      if (mounted) setState(() => _badges = todo);
    } catch (_) {}
  }

  /// « Argent »'s card: asked the first time the place is open, and again
  /// on coming back to it after five minutes — a computer left open for
  /// days never shows last month's money as this month's.
  Future<void> _loadMoney() async {
    final at = _moneyAt;
    if (!widget.center.isConfigured) return;
    if (at != null && DateTime.now().difference(at) < const Duration(minutes: 5)) return;
    _moneyAt = DateTime.now();
    try {
      final today = await widget.center.today();
      if (mounted) setState(() => _today = today);
    } catch (_) {}
    try {
      final overview = await widget.center.overview();
      if (mounted) setState(() => _overview = overview);
    } catch (_) {}
    if (mounted) setState(() => _moneyDone = true);
  }

  int _badge(String section) {
    final b = _badges;
    if (b == null) return 0;
    return switch (section) {
      // The lines « VOUS ATTEND · N » draws (135 review): one number on
      // the badge and on the page.
      'today' => b.badge,
      _ => 0,
    };
  }

  String _path(BuildContext context) {
    final given = widget.location;
    if (given != null) return Uri.parse(given).path;
    try {
      return GoRouter.of(context).state.uri.path;
    } catch (_) {
      return Routes.console;
    }
  }

  void _openSearch() => showCenterSearch(context, widget.center);

  void _go(CenterSection s) {
    unawaited(_loadBadges());
    context.go(s.root);
  }

  @override
  Widget build(BuildContext context) {
    final given = widget.platformAdmin;
    if (given != null) return given ? _center(context) : const _NotForYou();
    final session = AppScope.maybeOf(context)?.session;
    if (session == null) return const _NotForYou();
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.isPlatformAdmin) return _center(context);
        // A cold load of /console asks the server who this is first.
        if (session.phase == SessionPhase.booting || session.phase == SessionPhase.resolving) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return const _NotForYou();
      },
    );
  }

  Widget _center(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null || widget.location != null) return _frame(context);
    // The router's own address, so the rail follows a push inside a page.
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => _frame(context),
    );
  }

  Widget _frame(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= centerWideFrom;
    final sections = centerSections(context);
    final path = _path(context);
    final current = sectionFor(sections, path);
    final parent = centerParent(path);
    // The keyboard up: the page keeps the height, the money card waits.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (current.key == 'money') unawaited(_loadMoney());
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          wide: wide,
          // One search field per screen (135 review): a page with its own
          // field keeps the top bar's search as a button.
          compact: centerOwnSearch.contains(path),
          place: current.label,
          onSearch: _openSearch,
          onLeave: () => AdminTrail.leave(context),
        ),
        if (current.key == 'money' && !typing)
          _MoneyCard(
            today: _today,
            overview: _overview,
            loaded: _moneyDone || !widget.center.isConfigured,
          ),
        if (current.tabs && current.pages.length > 1)
          _PageTabs(
            section: current,
            path: path,
            trailing: current.key == 'street'
                // « Voir la rue »: the real street. A phone keeps the
                // switcher's room — the arrow alone, its name in the tooltip.
                ? MediaQuery.sizeOf(context).width < 600
                      ? IconButton.filled(
                          key: const Key('center-see-street'),
                          tooltip: context.tr('Voir la rue'),
                          style: IconButton.styleFrom(
                            backgroundColor: maraBlack,
                            foregroundColor: maraPaper,
                          ),
                          onPressed: () => AdminTrail.goOut(context, Routes.directory),
                          icon: const Icon(Icons.open_in_new, size: 20),
                        )
                      : FilledButton.icon(
                          key: const Key('center-see-street'),
                          style: FilledButton.styleFrom(
                            backgroundColor: maraBlack,
                            foregroundColor: maraPaper,
                          ),
                          onPressed: () => AdminTrail.goOut(context, Routes.directory),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(context.tr('Voir la rue')),
                        )
                : null,
          ),
        // A page beneath a place's first: the way back to it, said. A
        // card's page has its own arrow in its bar.
        if (parent != null && !path.startsWith('${Routes.consoleSettings}/'))
          _Crumb(label: _parentLabel(context, parent), onTap: () => context.go(parent)),
        // The header took the status bar: the page must not pad for it
        // again. Read from inside the Scaffold (the Builder), never from the
        // shell's own context above it: there the keyboard is still in
        // viewInsets, and handing that back to the page made its own
        // Scaffold take the keyboard off a second time — a body of zero
        // height, the page all white as soon as a field was touched (120).
        Expanded(
          child: Builder(
            builder: (inside) => MediaQuery.removePadding(
              context: inside,
              removeTop: true,
              // « The list continues » (122) on every center page.
              child: ScrollHint(child: widget.child),
            ),
          ),
        ),
      ],
    );
    final scaffold = wide
        ? Scaffold(
            body: Row(
              children: [
                _Rail(
                  sections: sections,
                  current: current,
                  badge: _badge,
                  onTap: _go,
                  extended: MediaQuery.sizeOf(context).width >= 1100,
                ),
                Expanded(child: body),
              ],
            ),
          )
        : Scaffold(
            body: body,
            bottomNavigationBar: _PhoneBar(
              sections: sections,
              current: current,
              badge: _badge,
              onTap: _go,
            ),
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openSearch,
      },
      child: Focus(
        autofocus: true,
        // Back from a page beneath a place's first returns to it (135);
        // from the first page of a place it leaves the center the way it
        // came, rather than out of the app.
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            final up = centerParent(_path(context));
            if (up != null) {
              context.go(up);
            } else {
              AdminTrail.leave(context);
            }
          },
          child: scaffold,
        ),
      ),
    );
  }

  String _parentLabel(BuildContext context, String parent) {
    if (parent == Routes.console) return context.tr('Aujourd\'hui');
    if (parent == Routes.consoleSettingsCard('creation')) {
      return context.tr('Réglages › Création');
    }
    if (parent == Routes.consoleSettingsCard('securite')) {
      return context.tr('Réglages › Sécurité, journal');
    }
    return context.tr('Réglages');
  }
}

/// The graphite band at the top: whose center this is, the one search,
/// and the way out.
class _Header extends StatelessWidget {
  const _Header({
    required this.wide,
    required this.onSearch,
    required this.onLeave,
    this.compact = false,
    this.place = '',
  });

  final bool wide;

  /// The page has its own search field: the top bar's is a button, and
  /// the band says the place.
  final bool compact;
  final String place;
  final VoidCallback onSearch;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: maraDeep,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 20 : 12, 8, 8, 8),
          child: Row(
            children: [
              if (!wide) ...[
                const Icon(Icons.shield_outlined, color: maraCaramel, size: 22),
                const SizedBox(width: 8),
              ],
              if (compact) ...[
                Expanded(
                  child: Text(
                    place,
                    key: const Key('center-place'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: maraPaper,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('center-search'),
                  tooltip: defaultTargetPlatform == TargetPlatform.macOS
                      ? context.tr('Rechercher partout (⌘ K)')
                      : context.tr('Rechercher partout (Ctrl K)'),
                  onPressed: onSearch,
                  icon: const Icon(Icons.search, color: maraPaper),
                ),
              ] else
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Material(
                        key: const Key('center-search'),
                        color: maraPaper.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onSearch,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            child: Row(
                              children: [
                                const Icon(Icons.search, color: maraPaper, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    wide
                                        ? context.tr(
                                            'Rechercher une entreprise, une personne, une commande',
                                          )
                                        : context.tr('Rechercher'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: maraPaper.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ),
                                if (wide)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: maraPaper.withValues(alpha: 0.4)),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    // The keys as this keyboard says them.
                                    child: Text(
                                      defaultTargetPlatform == TargetPlatform.macOS
                                          ? '⌘ K'
                                          : context.tr('Ctrl K'),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: maraPaper.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              // The platform's own bell (115): requests, couriers, spots.
              if (AppScope.maybeOf(context)?.notify case final notify?)
                IconButtonTheme(
                  data: IconButtonThemeData(
                    style: IconButton.styleFrom(foregroundColor: maraPaper),
                  ),
                  child: NotificationBell(
                    notify: notify,
                    scope: NotifyScope.platform,
                    listRoute: Routes.consoleNotifications,
                  ),
                ),
              IconButton(
                key: const Key('center-leave'),
                tooltip: context.tr('Quitter le centre admin'),
                onPressed: onLeave,
                icon: const Icon(Icons.close, color: maraPaper),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Argent »'s dark card (135): what Mara earned this month, as
/// platform_today counts it — the Pro payments confirmed, the paid spots,
/// Mara's part of the deliveries — and the businesses on Pro today. No
/// number is made up: before the server answers, it says so.
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.today, required this.overview, required this.loaded});

  final PlatformToday? today;
  final PlatformOverview? overview;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = today;
    final money = moneyFormat('XOF');
    final soft = maraPaper.withValues(alpha: 0.75);
    final parts = t == null
        ? null
        : [
            context.tr('Pro {amount}', {'amount': money.format(t.money['pro'] ?? 0)}),
            context.tr('mises en avant {amount}', {'amount': money.format(t.money['spots'] ?? 0)}),
            context.tr('livraisons {amount}', {
              'amount': money.format(t.money['delivery_cut'] ?? 0),
            }),
          ].join(' · ');
    final pro = overview?.pro;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        key: const Key('center-money-card'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [maraBlack, maraDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Revenus de Mara · ce mois'),
              style: theme.textTheme.labelLarge?.copyWith(color: soft),
            ),
            const SizedBox(height: 2),
            if (t == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  loaded
                      ? context.tr('Les chiffres du mois ne sont pas arrivés.')
                      : context.tr('Un instant…'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: maraPaper),
                ),
              )
            else
              MoneyText(
                money.format(t.earnedMonth),
                textKey: const Key('center-money-total'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: maraPaper,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            if (parts != null || pro != null)
              Text(
                [
                  if (pro != null)
                    pro > 1
                        ? context.tr('{n} abonnés Pro', {'n': pro})
                        : context.tr('{n} abonné Pro', {'n': pro}),
                  ?parts,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: soft),
              ),
          ],
        ),
      ),
    );
  }
}

/// A place's pages, as a switcher across the top.
class _PageTabs extends StatelessWidget {
  const _PageTabs({required this.section, required this.path, this.trailing});

  final CenterSection section;
  final String path;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = pageFor(section, path);
    // The whole width, every page on screen (a word too long for its
    // share is drawn smaller, never cut nor slid out of sight).
    final switcher = Container(
      key: const Key('center-tabs'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final p in section.pages)
            // A long word gets a wider share: every word drawn the same size.
            Expanded(
              flex: p.label.length + 6,
              child: _Segment(
                key: Key('center-tab-${p.route}'),
                label: p.label,
                selected: identical(p, on),
                onTap: () => p.leaves ? AdminTrail.goOut(context, p.route) : context.go(p.route),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              // A computer: a switcher, not a band across the whole screen.
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 110.0 * section.pages.length),
                child: switcher,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The page open: a white pill, as the mockup draws it.
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))]
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The way back from a page beneath a place's first (135).
class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        key: const Key('center-crumb'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(
            children: [
              const Icon(Icons.arrow_back, size: 18, color: maraBrown),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: maraBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.sections,
    required this.current,
    required this.badge,
    required this.onTap,
    required this.extended,
  });

  final List<CenterSection> sections;
  final CenterSection current;
  final int Function(String) badge;
  final void Function(CenterSection) onTap;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('center-rail'),
      color: maraDeep,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: extended ? 232 : 96,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                child: extended
                    ? Row(
                        children: [
                          const MaraMark(size: 34),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.tr('Centre admin'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: maraCaramel,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(child: MaraMark(size: 40)),
              ),
              for (final s in sections)
                _RailItem(
                  section: s,
                  selected: s.key == current.key,
                  badge: badge(s.key),
                  extended: extended,
                  onTap: () => onTap(s),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.section,
    required this.selected,
    required this.badge,
    required this.extended,
    required this.onTap,
  });

  final CenterSection section;
  final bool selected;
  final int badge;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? maraCaramel : maraPaper.withValues(alpha: 0.86);
    final icon = Badge(
      isLabelVisible: badge > 0,
      label: Text('$badge'),
      child: Icon(section.icon, color: ink),
    );
    final label = Text(
      section.label,
      maxLines: extended ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: extended ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        color: ink,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        fontSize: extended ? 14 : 11.5,
      ),
    );
    // A computer's wide rail says each place's question under its name.
    final question = Text(
      section.question,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: maraPaper.withValues(alpha: 0.6), fontSize: 11.5),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        key: Key('center-section-${section.key}'),
        color: selected ? maraPaper.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: extended
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: extended
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [label, const SizedBox(height: 1), question],
                        ),
                      ),
                    ],
                  )
                : Column(children: [icon, const SizedBox(height: 4), label]),
          ),
        ),
      ),
    );
  }
}

/// A phone's bar: the five places, always a word, never « Plus » (135).
class _PhoneBar extends StatelessWidget {
  const _PhoneBar({
    required this.sections,
    required this.current,
    required this.badge,
    required this.onTap,
  });

  final List<CenterSection> sections;
  final CenterSection current;
  final int Function(String) badge;
  final void Function(CenterSection) onTap;

  @override
  Widget build(BuildContext context) {
    final index = sections.indexWhere((s) => s.key == current.key);
    // The business bar's rule (133's B-2): the labels held to 1.15 × large
    // text, 1.0 on a phone under 360 px — at 1.3 « Aujourd'hui » and
    // « Réglages » broke mid-word in a fifth of 320 px (135 review).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: MediaQuery.sizeOf(context).width < 360 ? 1.0 : 1.15,
      child: NavigationBar(
        key: const Key('center-bar'),
        selectedIndex: index < 0 ? 0 : index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => onTap(sections[i]),
        destinations: [
          for (final s in sections)
            NavigationDestination(
              key: Key('center-bar-${s.key}'),
              icon: Badge(
                isLabelVisible: badge(s.key) > 0,
                label: Text('${badge(s.key)}'),
                child: Icon(s.icon),
              ),
              label: s.label,
              tooltip: s.question,
            ),
        ],
      ),
    );
  }
}

/// Anybody else at a center address: a word and the way back. The server
/// refuses every one of its functions to them anyway.
class _NotForYou extends StatelessWidget {
  const _NotForYou();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('center-not-for-you'),
      appBar: AppBar(actions: const [bellRoom]),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                context.tr('Réservé à la plateforme'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(Routes.directory),
                child: Text(context.tr('Retour à l\'accueil')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

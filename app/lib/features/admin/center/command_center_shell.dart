import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/console/command_center.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/nav/router.dart';
import '../../../core/nav/session.dart';
import '../../../core/theme/mara_mark.dart';
import '../../../core/notify/notifications_repository.dart';
import '../admin_pill.dart';
import '../../notify/notifications_screen.dart' show NotificationBell;
import 'center_search.dart';
import '../../../core/notify/bell_room.dart';

/// One page of a section: its name and its address. [leaves] marks a page
/// outside the center (the street).
class CenterPage {
  const CenterPage(this.label, this.route, {this.leaves = false});

  final String label;
  final String route;
  final bool leaves;
}

/// One section of the command center: its place on the rail, its pages.
/// The first page is where the section opens; [owns] are the further
/// addresses it is the section of (a business's fiche under Entreprises).
class CenterSection {
  const CenterSection({
    required this.key,
    required this.label,
    required this.icon,
    required this.pages,
    this.owns = const [],
  });

  final String key;
  final String label;
  final IconData icon;
  final List<CenterPage> pages;
  final List<String> owns;

  String get root => pages.first.route;
}

/// The ten sections, in the rail's order. The console's screens from
/// before are folded in as their pages (none of them drawn twice).
List<CenterSection> centerSections(BuildContext context) => [
      CenterSection(
        key: 'todo',
        label: context.tr('À faire'),
        icon: Icons.checklist_rtl,
        pages: [
          CenterPage(context.tr('Aujourd\'hui'), Routes.console),
          CenterPage(context.tr('Analyses'), Routes.platformAnalytics),
        ],
      ),
      CenterSection(
        key: 'businesses',
        label: context.tr('Entreprises'),
        icon: Icons.business_outlined,
        pages: [CenterPage(context.tr('Entreprises'), Routes.consoleBusinesses)],
        owns: const ['${Routes.consoleBusinesses}/'],
      ),
      CenterSection(
        key: 'kinds',
        label: context.tr('Types d\'activité'),
        icon: Icons.category_outlined,
        pages: [CenterPage(context.tr('Types d\'activité'), Routes.consoleKinds)],
      ),
      // People create their business at once (111): what was « Demandes »
      // is the businesses created, and the page that shapes the creation.
      CenterSection(
        key: 'requests',
        label: context.tr('Activités créées'),
        icon: Icons.add_business_outlined,
        pages: [
          CenterPage(context.tr('Activités créées'), Routes.applications),
          CenterPage(context.tr('Parcours de création'), Routes.consoleRequestForm),
        ],
      ),
      CenterSection(
        key: 'street',
        label: context.tr('Vitrines et rue'),
        icon: Icons.storefront_outlined,
        pages: [
          CenterPage(context.tr('À la une'), Routes.consoleFeatured),
          CenterPage(context.tr('Vitrines d\'exemple'), Routes.consoleShowcase),
          CenterPage(context.tr('Livreurs'), Routes.consoleCouriers),
          CenterPage(context.tr('La rue'), Routes.directory, leaves: true),
        ],
      ),
      CenterSection(
        key: 'pro',
        label: context.tr('Pro et cauris'),
        icon: Icons.workspace_premium_outlined,
        pages: [
          CenterPage(context.tr('Mara Pro'), Routes.consolePro),
          CenterPage(context.tr('Offrir des cauris'), Routes.consoleCaurisGifts),
        ],
      ),
      CenterSection(
        key: 'payments',
        label: context.tr('Paiements'),
        icon: Icons.account_balance_wallet_outlined,
        pages: [
          CenterPage(context.tr('Paiements Wave'), Routes.consoleWave),
          CenterPage(context.tr('Règlement des livreurs'), Routes.consoleSettlement),
        ],
      ),
      CenterSection(
        key: 'people',
        label: context.tr('Personnes'),
        icon: Icons.people_outline,
        pages: [
          CenterPage(context.tr('Personnes'), Routes.consolePeople),
          CenterPage(context.tr('Formateurs'), Routes.trainers),
        ],
      ),
      CenterSection(
        key: 'settings',
        label: context.tr('Réglages'),
        icon: Icons.tune,
        pages: [CenterPage(context.tr('Réglages'), Routes.consoleSettings)],
      ),
      CenterSection(
        key: 'journal',
        label: context.tr('Journal'),
        icon: Icons.history,
        pages: [
          CenterPage(context.tr('Actions de Mara'), Routes.consoleJournal),
          CenterPage(context.tr('Activité'), Routes.consoleAudit),
        ],
      ),
    ];

/// The four a phone keeps on its bar; the rest are under « Plus ».
const phoneSections = ['todo', 'businesses', 'requests', 'pro'];

/// The section an address belongs to: the longest page (or owned prefix)
/// that matches it. « À faire » only at its own address.
CenterSection sectionFor(List<CenterSection> sections, String path) {
  CenterSection best = sections.first;
  var length = -1;
  for (final s in sections) {
    for (final route in [for (final p in s.pages) if (!p.leaves) p.route, ...s.owns]) {
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

/// From this width the sections stand in a rail at the left.
const centerWideFrom = 900.0;

/// Mara's command center: the rail (a computer) or the bar (a phone), the
/// one search at the top (Ctrl/Cmd+K on a computer), the section's pages
/// as tabs, and the page itself — the console's screens, unchanged.
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

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  /// What waits, on the rail: asked when the center opens and again on a
  /// change of section, at most every half minute.
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

  int _badge(String section) {
    final b = _badges;
    if (b == null) return 0;
    return switch (section) {
      'todo' => b.waiting,
      // The businesses created this week (111): no request waits now.
      'requests' => b['new_7'],
      'pro' => b['pro_paid'],
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
        if (session.phase == SessionPhase.booting ||
            session.phase == SessionPhase.resolving) {
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
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(wide: wide, onSearch: _openSearch, onLeave: () => AdminTrail.leave(context)),
        if (current.pages.length > 1) _PageTabs(section: current, path: path),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
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
        // Back from the first page of a section leaves the center the way
        // it came, rather than out of the app.
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) AdminTrail.leave(context);
          },
          child: scaffold,
        ),
      ),
    );
  }
}

/// The graphite band at the top: whose center this is, the one search,
/// and the way out.
class _Header extends StatelessWidget {
  const _Header({required this.wide, required this.onSearch, required this.onLeave});

  final bool wide;
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
                                      ? context.tr('Rechercher une entreprise, une personne, une commande')
                                      : context.tr('Rechercher'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: maraPaper.withValues(alpha: 0.85)),
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
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: maraPaper.withValues(alpha: 0.8))),
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
                      style: IconButton.styleFrom(foregroundColor: maraPaper)),
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

/// A section's pages, as tabs across the top.
class _PageTabs extends StatelessWidget {
  const _PageTabs({required this.section, required this.path});

  final CenterSection section;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The page this address is (or is under).
    CenterPage? on;
    for (final p in section.pages) {
      if (p.leaves) continue;
      final hit = p.route == Routes.console
          ? path == p.route
          : path == p.route || path.startsWith('${p.route}/');
      if (hit && (on == null || p.route.length > on.route.length)) on = p;
    }
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        key: const Key('center-tabs'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            for (final p in section.pages)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('center-tab-${p.route}'),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.label),
                      if (p.leaves) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new, size: 14),
                      ],
                    ],
                  ),
                  selected: identical(p, on),
                  showCheckmark: false,
                  selectedColor: maraDeep,
                  labelStyle: TextStyle(
                    color: identical(p, on) ? maraCaramel : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                  // « La rue » leaves the center: nothing kept to return to.
                  onSelected: (_) =>
                      p.leaves ? AdminTrail.goOut(context, p.route) : context.go(p.route),
                ),
              ),
          ],
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
                            child: Text(context.tr('Centre admin'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                    color: maraCaramel, fontWeight: FontWeight.w800)),
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
      backgroundColor: maraCaramel,
      textColor: maraBlack,
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
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: extended
                ? Row(children: [icon, const SizedBox(width: 14), Expanded(child: label)])
                : Column(children: [icon, const SizedBox(height: 4), label]),
          ),
        ),
      ),
    );
  }
}

/// A phone's bar: the four most used, and « Plus » for the others.
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
    final onBar = [
      for (final k in phoneSections) sections.firstWhere((s) => s.key == k),
    ];
    final rest = [for (final s in sections) if (!phoneSections.contains(s.key)) s];
    final index = onBar.indexWhere((s) => s.key == current.key);
    Widget icon(IconData data, int n) => Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          child: Icon(data),
        );
    return NavigationBar(
      key: const Key('center-bar'),
      selectedIndex: index < 0 ? onBar.length : index,
      onDestinationSelected: (i) {
        if (i < onBar.length) {
          onTap(onBar[i]);
        } else {
          _more(context, rest);
        }
      },
      destinations: [
        for (final s in onBar)
          NavigationDestination(icon: icon(s.icon, badge(s.key)), label: s.label),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz),
          label: context.tr('Plus'),
        ),
      ],
    );
  }

  Future<void> _more(BuildContext context, List<CenterSection> rest) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final s in rest)
              ListTile(
                key: Key('center-more-${s.key}'),
                minVerticalPadding: 14,
                leading: Icon(s.icon),
                title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                selected: s.key == current.key,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheet).pop();
                  onTap(s);
                },
              ),
          ],
        ),
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
      appBar: AppBar(actions: const [bellRoom], ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, size: 48),
              const SizedBox(height: 16),
              Text(context.tr('Réservé à la plateforme'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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

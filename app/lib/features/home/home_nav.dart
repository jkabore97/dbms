import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/theme/scroll_hint.dart';
import '../../l10n/strings.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';

/// One place a business's home screen leads to.
class HomeDestination {
  const HomeDestination({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selectedIcon,
    this.badge = 0,
    this.route,
  });

  final IconData icon;
  final IconData? selectedIcon;

  /// Always on screen under the icon. The row of bare icons this replaced
  /// had a name for every button, but only behind a long press nobody makes:
  /// the owner's report was that the pictures alone said nothing.
  final String label;
  final VoidCallback onTap;

  /// A count worth seeing before opening (orders waiting); 0 shows nothing.
  final int badge;

  /// The page this place is, under the business: `produits`, `factures`,
  /// '' for the home itself (108). The bar stays on every page of the
  /// business and shows this place selected there and on every page under
  /// it. Null for a door out (the street, the vitrine).
  final String? route;
}

/// The bar's keeper (108): the frame around every page of a business holds
/// the places its home screen lays out, so the bar — and the rail on a wide
/// screen — stays on every tool page, not only on the home.
///
/// The home publishes its [HomeNav] here on each build instead of drawing
/// it; the frame draws it. A home with no frame above it (a test, a build
/// that shows a home alone) draws its own bar, as before.
class BusinessNav extends ChangeNotifier {
  HomeNav? _nav;
  BuildContext? _owner;
  String _drawn = '';
  bool _disposed = false;

  /// The business whose frame holds this keeper.
  String? orgId;

  /// The places each business's home last said, for this run of the app
  /// (132): what the frame draws the next time that business opens,
  /// before its home has said them again.
  /// Kept with the language they were said in: after a change of
  /// language they are not drawn again in the old one.
  static final Map<String, (String, HomeNav)> _known = {};

  /// What [orgId]'s home last said in [language], if anything.
  static HomeNav? lastKnown(String orgId, String language) {
    final known = _known[orgId];
    return known != null && known.$1 == language ? known.$2 : null;
  }

  @visibleForTesting
  static void forgetKnown() => _known.clear();

  /// The places, while the home that published them is still on screen.
  /// Their actions are the home's own.
  HomeNav? get nav => (_owner?.mounted ?? false) ? _nav : null;

  void publish(BuildContext owner, HomeNav nav) {
    _owner = owner;
    _nav = nav;
    final org = orgId;
    if (org != null) _known[org] = (owner.trLanguage, nav);
    final drawn = nav.signature;
    if (drawn == _drawn) return;
    _drawn = drawn;
    // Asked from the home's build: the frame redraws on the next frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Forgets the places (the frame now holds another business).
  void publishNothing() {
    _nav = null;
    _owner = null;
    _drawn = '';
  }

  /// The pages holding input not saved yet ([UnsavedInput]), each asked
  /// at the moment of a tap on the bar or the rail.
  final Set<bool Function()> _unsaved = {};

  void holdUnsaved(bool Function() dirty) => _unsaved.add(dirty);
  void releaseUnsaved(bool Function() dirty) => _unsaved.remove(dirty);

  /// Whether leaving now would lose what somebody typed.
  bool get hasUnsaved => _unsaved.any((dirty) => dirty());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Where the frame's [BusinessNav] is found, and how much of the screen its
/// bar (bottom) or rail (left) takes — every page of the business stands
/// inside that (BusinessPage).
class BusinessNavHost extends InheritedWidget {
  const BusinessNavHost({
    super.key,
    required this.nav,
    required this.insets,
    required super.child,
  });

  final BusinessNav nav;
  final EdgeInsets insets;

  /// The keeper, without listening: a home publishing to it must not be
  /// rebuilt by what it published.
  static BusinessNav? navOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BusinessNavHost>()?.nav;

  /// The room the bar or the rail takes; zero outside a business frame.
  static EdgeInsets insetsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BusinessNavHost>()?.insets ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(BusinessNavHost oldWidget) =>
      insets != oldWidget.insets || nav != oldWidget.nav;
}

/// The labelled bar at the foot of every business home screen — the shop,
/// the farm and the association alike.
///
/// It replaces a row of up to eight bare icons in the top bar: tools worked
/// in all day, a one-off setting and the door out to the street side by
/// side, with nothing to tell them apart but a picture, and at the top of the
/// screen, the one place a thumb at a counter cannot reach.
///
/// The rule is five places at most, each with its word: the home screen
/// itself, the three tools reached for every day, and **Plus**, a short
/// labelled list for the rest. A tool the owner's dial hides is simply not
/// passed in, and the bar closes up around it. The top bar keeps the name of
/// the business, the bell and the account.
///
/// Inside a business the bar stays (108): the frame around every page of the
/// business draws it (BusinessFrame), the place of the page on screen shown
/// selected, and a tap switches tool. A tool still opens as its own page,
/// with its own address, and back from it returns to the home. On a wide
/// screen the same places stand in a labelled rail down the left side.
class HomeNav {
  const HomeNav({
    required this.home,
    this.primary = const [],
    this.more = const [],
  });

  /// The home screen itself — always first, always the one selected.
  final HomeDestination home;

  /// The everyday tools, most used first. Up to three take their own place
  /// on the bar (four when nothing else needs Plus); the rest go under Plus.
  final List<HomeDestination> primary;

  /// The tools consulted rather than worked in, under Plus.
  final List<HomeDestination> more;

  static const maxSlots = 5;

  /// From this width the places stand in a rail at the left (a tablet on
  /// its side, a computer).
  static const wideFrom = 840.0;

  static const moreLabel = 'Plus';

  /// How many everyday tools take their own place on the bar.
  int get _onBar => more.isEmpty && primary.length <= maxSlots - 1
      ? primary.length
      : math.min(primary.length, maxSlots - 2);

  /// What Plus lists: everyday tools that did not fit, then the rest.
  List<HomeDestination> get overflow => [...primary.skip(_onBar), ...more];

  /// The places on the bar, in order, with Plus last when it has anything.
  List<HomeDestination> slots(BuildContext context) {
    final rest = overflow;
    return [
      home,
      ...primary.take(_onBar),
      if (rest.isNotEmpty)
        HomeDestination(
          icon: Icons.more_horiz,
          label: context.tr(moreLabel),
          // What waits under Plus, added up (115): its lines say which.
          badge: rest.fold(0, (n, p) => n + p.badge),
          onTap: () => showMore(context, rest),
        ),
    ];
  }

  /// The same places, each opened by [open] with its route instead of the
  /// home's own action (132): what the frame draws before the home has
  /// said its places — the home that said them may be gone.
  HomeNav detached(void Function(HomeDestination place) open) {
    HomeDestination copy(HomeDestination p) => HomeDestination(
          icon: p.icon,
          selectedIcon: p.selectedIcon,
          label: p.label,
          badge: p.badge,
          route: p.route,
          onTap: () => open(p),
        );
    return HomeNav(
      home: copy(home),
      primary: [for (final p in primary) copy(p)],
      more: [for (final p in more) copy(p)],
    );
  }

  /// The places a business's home lays out, before its home has said
  /// them (132) — the first frame of a business, every time on an iPhone
  /// it came late: the shop's Vente, Articles, Commandes, Factures; the
  /// farm's Accueil, Stock, Bandes, Factures; the association's Accueil,
  /// Rapports, Factures — and Plus with what everybody has under it. The
  /// home's own places replace them at once, the bar's height unchanged.
  /// Null for a kind this build does not know. [open] is the frame's way
  /// into a place.
  static HomeNav? defaultsFor(
    BuildContext context,
    OrgSummary org,
    OrgAccess access,
    void Function(HomeDestination place) open,
  ) {
    final s = Strings.of(context);
    HomeDestination at(IconData icon, String label, String route, {IconData? selected}) =>
        HomeDestination(icon: icon, selectedIcon: selected, label: label, route: route, onTap: () {});
    final common = [
      if (org.isAdmin) at(Icons.groups_outlined, context.tr('Équipe'), 'equipe'),
      if (org.isAdmin) at(Icons.admin_panel_settings_outlined, context.tr('Administration'), 'administration'),
      at(Icons.account_circle_outlined, s.account, 'compte'),
    ];
    final nav = switch (org.profile) {
      'retail' => HomeNav(
          home: at(Icons.payments_outlined, s.sale, '', selected: Icons.payments),
          primary: [
            if (access.canSee('products')) at(Icons.sell_outlined, s.productsLabel, 'produits'),
            if (access.canSee('orders')) at(Icons.inbox_outlined, context.tr('Commandes'), 'commandes'),
            if (access.canSee('invoices')) at(Icons.receipt_long_outlined, s.invoices, 'factures'),
          ],
          more: common,
        ),
      'farm' => HomeNav(
          home: at(Icons.agriculture_outlined, context.tr('Accueil'), '', selected: Icons.agriculture),
          primary: [
            at(Icons.inventory_2_outlined, s.stock, 'stock'),
            at(Icons.pets_outlined, s.flocks, 'bandes'),
            if (access.canSee('invoices')) at(Icons.receipt_long_outlined, s.invoices, 'factures'),
          ],
          more: common,
        ),
      'association' || 'church' => HomeNav(
          home: at(Icons.volunteer_activism_outlined, context.tr('Accueil'), '',
              selected: Icons.volunteer_activism),
          primary: [
            if (org.visibility != 'summary' && access.canSee('reports'))
              at(Icons.history, s.history, 'journal'),
            if (access.canSee('reports')) at(Icons.assessment_outlined, s.reports, 'rapports'),
            if (access.canSee('invoices')) at(Icons.receipt_long_outlined, s.invoices, 'factures'),
          ],
          more: common,
        ),
      _ => null,
    };
    return nav?.detached(open);
  }

  /// What the bar shows, as one string: the frame redraws when it changes.
  String get signature => [
        for (final p in [home, ...primary, ...more])
          '${p.label}|${p.route}|${p.badge}|${p.icon.codePoint}',
      ].join(';');

  bool _wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wideFrom;

  /// The bar for the Scaffold's foot, or null on a wide screen (the rail
  /// carries it) or when there is nowhere to go but here — or inside a
  /// business frame, which draws it on every page (108).
  Widget? bar(BuildContext context) {
    if (BusinessNavHost.navOf(context) != null) return null;
    if (_wide(context)) return null;
    final places = slots(context);
    if (places.length < 2) return null;
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (i) {
        if (i > 0) places[i].onTap();
      },
      destinations: [
        for (final p in places)
          NavigationDestination(
            icon: placeIcon(p, p.icon),
            selectedIcon: placeIcon(p, p.selectedIcon ?? p.icon),
            label: p.label,
          ),
      ],
    );
  }

  /// The home screen's Scaffold, with the rail at its left on a wide screen.
  /// Inside a business frame the places go to the frame instead, which
  /// draws them around this page and every other page of the business.
  Widget frame(BuildContext context, Widget scaffold) {
    final host = BusinessNavHost.navOf(context);
    if (host != null) {
      host.publish(context, this);
      return scaffold;
    }
    if (!_wide(context)) return scaffold;
    final places = slots(context);
    if (places.length < 2) return scaffold;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: 0,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) {
                if (i > 0) places[i].onTap();
              },
              destinations: [
                for (final p in places)
                  NavigationRailDestination(
                    icon: placeIcon(p, p.icon),
                    selectedIcon: placeIcon(p, p.selectedIcon ?? p.icon),
                    label: Text(p.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: scaffold),
        ],
      ),
    );
  }

  /// A place's count, as the bell says its own (115): « 9+ » past nine.
  static Widget placeIcon(HomeDestination p, IconData icon) => Badge(
        isLabelVisible: p.badge > 0,
        label: Text(p.badge > 9 ? '9+' : '${p.badge}'),
        child: Icon(icon),
      );

  /// Plus: every remaining tool as a line with its name, never a grid of
  /// pictures — the point of the change. [onPick] is the frame's way into a
  /// place (108); [here] marks the line of the page on screen.
  static Future<void> showMore(
    BuildContext context,
    List<HomeDestination> items, {
    void Function(HomeDestination item)? onPick,
    HomeDestination? here,
  }) {
    return showMaraSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        // The owner (122): « In the 3 dot list … an animated arrow showing
        // the list continues at the bottom ».
        child: ScrollHint(child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final item in items)
              ListTile(
                leading: placeIcon(item, item.icon),
                title: Text(item.label),
                selected: identical(item, here),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheet).pop();
                  (onPick ?? (i) => i.onTap())(item);
                },
              ),
          ],
        )),
      ),
    );
  }
}

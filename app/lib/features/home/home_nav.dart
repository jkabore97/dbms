import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One place a business's home screen leads to.
class HomeDestination {
  const HomeDestination({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selectedIcon,
    this.badge = 0,
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
/// The bar launches: a tool opens as its own page, with its own address and
/// a way back, as it did from the icon row — so the home screen is the one
/// place that is ever "selected". On a wide screen the same places stand in
/// a labelled rail down the left side instead.
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
          label: moreLabel,
          onTap: () => showMore(context, rest),
        ),
    ];
  }

  bool _wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wideFrom;

  /// The bar for the Scaffold's foot, or null on a wide screen (the rail
  /// carries it) or when there is nowhere to go but here.
  Widget? bar(BuildContext context) {
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
            icon: _icon(p, p.icon),
            selectedIcon: _icon(p, p.selectedIcon ?? p.icon),
            label: p.label,
          ),
      ],
    );
  }

  /// The home screen's Scaffold, with the rail at its left on a wide screen.
  Widget frame(BuildContext context, Widget scaffold) {
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
                    icon: _icon(p, p.icon),
                    selectedIcon: _icon(p, p.selectedIcon ?? p.icon),
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

  static Widget _icon(HomeDestination p, IconData icon) => Badge(
        isLabelVisible: p.badge > 0,
        label: Text('${p.badge}'),
        child: Icon(icon),
      );

  /// Plus: every remaining tool as a line with its name, never a grid of
  /// pictures — the point of the change.
  static Future<void> showMore(
    BuildContext context,
    List<HomeDestination> items,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final item in items)
              ListTile(
                leading: _icon(item, item.icon),
                title: Text(item.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheet).pop();
                  item.onTap();
                },
              ),
          ],
        ),
      ),
    );
  }
}

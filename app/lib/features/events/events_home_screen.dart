import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/events/events_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/notify/bell_room.dart';
import '../../core/retail/staff.dart';
import '../../core/theme/app_bar_title.dart';
import '../home/home_nav.dart';
import 'events_screens.dart';

/// An Événementiel's home (153): its cards, and the bar — Cartes, Modèles,
/// Invités, Plus. No till, no stock, no vitrine: the business is its
/// events. « Nouvelle carte » is the big button; the card's words and
/// pictures are edited on the site itself (piece 2).
class EventsHomeScreen extends StatefulWidget {
  const EventsHomeScreen({
    super.key,
    required this.org,
    required this.events,
    this.staff,
    this.accountAction,
    this.now,
  });

  final OrgSummary org;
  final EventsRepository events;
  final StaffRepository? staff;

  /// The bell and the account button, as on every home.
  final Widget? accountAction;

  /// The clock, for the tests.
  final DateTime Function()? now;

  @override
  State<EventsHomeScreen> createState() => _EventsHomeScreenState();
}

class _EventsHomeScreenState extends State<EventsHomeScreen> {
  int _tick = 0;

  Future<void> _create() async {
    final made = await startNewCard(context, widget.events, widget.org, now: widget.now);
    if (made == null || !mounted) return;
    setState(() => _tick++);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EventScreen(events: widget.events, org: widget.org, eventId: made.id, first: made),
    ));
    if (mounted) setState(() => _tick++);
  }

  Future<void> _open(String rest) async {
    await context.push(Routes.inside(widget.org.id, rest));
    if (mounted) setState(() => _tick++);
  }

  /// The Événementiel's places: Cartes (this screen), Modèles, Invités;
  /// under Plus, the team, the administration, the person.
  HomeNav _nav() {
    final org = widget.org;
    return HomeNav(
      home: HomeDestination(
        icon: Icons.celebration_outlined,
        selectedIcon: Icons.celebration,
        label: context.tr('Cartes'),
        onTap: () {},
        route: '',
        alsoRoutes: const ['evenements'],
      ),
      primary: [
        HomeDestination(
          icon: Icons.auto_awesome_mosaic_outlined,
          selectedIcon: Icons.auto_awesome_mosaic,
          label: context.tr('Modèles'),
          route: 'modeles',
          onTap: () => _open('modeles'),
        ),
        HomeDestination(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: context.tr('Invités'),
          route: 'invites',
          onTap: () => _open('invites'),
        ),
      ],
      more: [
        if (widget.staff != null && org.isAdmin)
          HomeDestination(
            icon: Icons.groups_outlined,
            label: context.tr('Équipe'),
            route: 'equipe',
            group: PlusGroup.team,
            onTap: () => _open('equipe'),
          ),
        if (org.isAdmin)
          HomeDestination(
            icon: Icons.admin_panel_settings_outlined,
            label: context.tr('Administration'),
            route: 'administration',
            group: PlusGroup.team,
            onTap: () => _open('administration'),
          ),
        HomeDestination(
          icon: Icons.account_circle_outlined,
          label: context.tr('Mon compte'),
          route: 'compte',
          group: PlusGroup.me,
          onTap: () => _open('compte'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = _nav();
    return nav.frame(
      context,
      Scaffold(
        bottomNavigationBar: nav.bar(context),
        appBar: AppBar(
          title: AppBarTitle(widget.org.name),
          actions: [
            if (widget.accountAction != null) widget.accountAction!,
            bellRoom,
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('event-new'),
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: Text(context.tr('Nouvelle carte')),
        ),
        body: EventsList(events: widget.events, org: widget.org, reloadTick: _tick),
      ),
    );
  }
}

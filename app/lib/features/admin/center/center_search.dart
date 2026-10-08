import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/console/command_center.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/router.dart';
import '../../../core/theme/mara_mark.dart';
import '../../auth/org_picker_screen.dart' show iconForProfile, kindColour, kindInk, kindSingular;
import '../admin_pill.dart';

/// The one search (105's platform_search): businesses, people, orders.
/// A computer opens it with Ctrl/Cmd+K too.
Future<void> showCenterSearch(BuildContext context, CommandCenterRepository center) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  return showDialog<void>(
    context: context,
    builder: (dialog) => wide
        ? Dialog(
            alignment: Alignment.topCenter,
            insetPadding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
              child: CenterSearch(center: center, outer: context),
            ),
          )
        : Dialog.fullscreen(child: CenterSearch(center: center, outer: context)),
  );
}

class CenterSearch extends StatefulWidget {
  const CenterSearch({super.key, required this.center, required this.outer});

  final CommandCenterRepository center;

  /// The page under the search, where what is chosen opens.
  final BuildContext outer;

  @override
  State<CenterSearch> createState() => _CenterSearchState();
}

class _CenterSearchState extends State<CenterSearch> {
  final _query = TextEditingController();
  Timer? _debounce;
  SearchResults? _results;
  bool _busy = false;
  String? _error;
  int _asked = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _typed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _results = null;
        _error = null;
      });
      return;
    }
    final asked = ++_asked;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.center.search(q.trim());
      if (!mounted || asked != _asked) return;
      setState(() {
        _results = r;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || asked != _asked) return;
      setState(() {
        _error = describeError(e);
        _busy = false;
      });
    }
  }

  void _close() => Navigator.of(context).pop();

  void _openBusiness(BusinessHit b) {
    _close();
    widget.outer.push(Routes.consoleOrg(b.id));
  }

  void _openPerson(PersonHit p) {
    _close();
    final q = p.email ?? p.phone ?? p.name ?? '';
    widget.outer.go(Uri(path: Routes.consolePeople,
        queryParameters: {'q': q, 'personne': p.id}).toString());
  }

  void _openOrder(OrderHit o) {
    _close();
    showModalBottomSheet<void>(
      context: widget.outer,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => OrderSheet(order: o, outer: widget.outer),
    );
  }

  void _first() {
    final r = _results;
    if (r == null) return;
    if (r.businesses.isNotEmpty) return _openBusiness(r.businesses.first);
    if (r.people.isNotEmpty) return _openPerson(r.people.first);
    if (r.orders.isNotEmpty) return _openOrder(r.orders.first);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _results;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: maraDeep,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.tr('Fermer'),
                    onPressed: _close,
                    icon: const Icon(Icons.arrow_back, color: maraPaper),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('center-search-field'),
                      controller: _query,
                      autofocus: true,
                      onChanged: _typed,
                      onSubmitted: (_) => _first(),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(color: maraPaper, fontSize: 17),
                      cursorColor: maraCaramel,
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: context.tr('Nom, adresse, téléphone, e-mail, n° de commande…'),
                        hintStyle: TextStyle(color: maraPaper.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  )
                else if (r == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.tr('Une entreprise par son nom, son adresse ou le téléphone de son propriétaire ; une personne par son nom, son téléphone ou son e-mail ; une commande par son numéro ou son client.'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else if (r.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.tr('Rien ne correspond.')),
                  )
                else ...[
                  if (r.businesses.isNotEmpty) ...[
                    _Group(context.tr('Entreprises')),
                    for (final b in r.businesses)
                      ListTile(
                        key: Key('hit-org-${b.id}'),
                        leading: _KindIcon(profile: b.profile),
                        title: Text(b.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                decoration: b.archived ? TextDecoration.lineThrough : null)),
                        subtitle: Text([
                          kindSingular(context, b.profile),
                          ?b.owner,
                          ?(b.ownerPhone ?? b.phone),
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openBusiness(b),
                      ),
                  ],
                  if (r.people.isNotEmpty) ...[
                    _Group(context.tr('Personnes')),
                    for (final p in r.people)
                      ListTile(
                        key: Key('hit-person-${p.id}'),
                        leading: CircleAvatar(
                            child: Text(p.label.characters.first.toUpperCase())),
                        title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          ?p.phone,
                          ?p.email,
                          context.tr('{n} entreprise(s)', {'n': p.businesses}),
                        ].join(' · ')),
                        trailing: p.platform
                            ? Chip(label: Text(context.tr('Mara')), visualDensity: VisualDensity.compact)
                            : const Icon(Icons.chevron_right),
                        onTap: () => _openPerson(p),
                      ),
                  ],
                  if (r.orders.isNotEmpty) ...[
                    _Group(context.tr('Commandes')),
                    for (final o in r.orders)
                      ListTile(
                        key: Key('hit-order-${o.id}'),
                        leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
                        title: Text(
                          context.tr('Commande {id} · {who}',
                              {'id': o.shortId, 'who': o.customer ?? '—'}),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text([
                          ?o.orgName,
                          moneyFormat(o.currency).format(o.total),
                          orderStatusLabel(context, o.status),
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openOrder(o),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 0.8, color: maraBrown, fontWeight: FontWeight.w800)),
      );
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.profile});

  final String profile;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: kindColour(profile), borderRadius: BorderRadius.circular(10)),
        child: Icon(iconForProfile(profile), color: kindInk(profile), size: 22),
      );
}

/// An order's status in a word.
String orderStatusLabel(BuildContext context, String status) => switch (status) {
      'pending' => context.tr('En attente'),
      'accepted' => context.tr('Acceptée'),
      'ready' => context.tr('Prête'),
      // Carried by a courier (056); « picked_up » is collected at the
      // counter — finished, for a pickup.
      'in_transit' => context.tr('En route'),
      'picked_up' => context.tr('Récupérée'),
      'delivered' => context.tr('Livrée'),
      'refused' => context.tr('Refusée'),
      'cancelled' => context.tr('Annulée'),
      _ => status,
    };

/// One order, opened from the search: what it is, and where to act on it.
class OrderSheet extends StatelessWidget {
  const OrderSheet({super.key, required this.order, required this.outer});

  final OrderHit order;
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = order;
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(value,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const Key('order-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Commande {id}', {'id': o.shortId}),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(moneyFormat(o.currency).format(o.total),
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 12),
            line(context.tr('Entreprise'), o.orgName ?? '—'),
            line(context.tr('Client'), [?o.customer, ?o.phone].join(' · ')),
            line(context.tr('État'), orderStatusLabel(context, o.status)),
            line(context.tr('Remise'),
                o.fulfilment == 'delivery' ? context.tr('Livraison') : context.tr('Retrait')),
            if (o.at != null) line(context.tr('Passée le'), DateFormat('dd/MM/yyyy HH:mm').format(o.at!)),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('order-open-shop'),
                onPressed: () {
                  Navigator.of(context).pop();
                  AdminTrail.openBusiness(outer, o.orgId, page: Routes.inside(o.orgId, 'commandes'));
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(context.tr('Ouvrir ses commandes')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  outer.push(Routes.consoleOrg(o.orgId));
                },
                icon: const Icon(Icons.badge_outlined),
                label: Text(context.tr('Fiche de l\'entreprise')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

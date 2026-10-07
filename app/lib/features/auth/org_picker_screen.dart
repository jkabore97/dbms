import 'dart:async';

import '../../core/theme/kaj_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';

import '../../core/auth/models.dart';
import '../../l10n/strings.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Shown when someone belongs to more than one business — the accountant who
/// keeps books for a church and a farm, or an owner with two shops.
///
/// There is no "remember my choice": picking the wrong set of books and not
/// noticing is worse than one extra tap at launch.
///
/// Each activity wears its kind (100): a colour and a picture for a shop, a
/// farm, an association, and the owner's name under it, so a platform admin
/// — whose list is every business — recognises one at a glance. A long list
/// gets a search box; a mixed one gets a chip per kind.
class OrgPickerScreen extends StatefulWidget {
  const OrgPickerScreen({
    super.key,
    required this.orgs,
    required this.onSelected,
    this.loading = false,
    this.onRetry,
    this.onSignOut,
    this.onCreateBusiness,
    this.onBusinesses,
    this.title,
  });

  final List<OrgSummary> orgs;
  final void Function(OrgSummary org) onSelected;

  /// True while the business list is still being fetched. It matters because
  /// this screen can be opened cold — a bookmark or a reload straight onto
  /// `/entreprises` — before any org has arrived, and for a platform admin the
  /// list is *every* business there is, a heavier query that is slow on a thin
  /// connection. Without this the screen drew an empty page during that whole
  /// window, which reads as broken. An empty list is either "still loading"
  /// (spinner) or, once loaded, "you belong to none" (a message) — never a
  /// blank.
  final bool loading;

  /// Retries the resolve from the loading state's escape hatch. A resolve that
  /// stalls should recover on its own within seconds, but if it does not, this
  /// screen must never be a trap: after a short wait it offers a way to try
  /// again rather than spin forever.
  final VoidCallback? onRetry;

  final VoidCallback? onSignOut;

  /// Null for everyone except a platform admin, whose list here is every
  /// business there is rather than the ones they were invited to.
  final VoidCallback? onCreateBusiness;

  /// Also platform-admin only: the list here is already every business, so
  /// this is the natural place to reach the one screen that can rename,
  /// archive or delete one.
  final VoidCallback? onBusinesses;

  /// Null takes the localized default. Passed only by callers that mean
  /// something narrower than "choose".
  final String? title;

  /// More than this many activities and the search box appears; below it,
  /// the whole list fits on a phone and a box would only be in the way.
  static const searchFrom = 6;

  @override
  State<OrgPickerScreen> createState() => _OrgPickerScreenState();
}

class _OrgPickerScreenState extends State<OrgPickerScreen> {
  final _search = TextEditingController();

  /// 'retail' | 'farm' | 'association', or null for all of them.
  String? _kind;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widget = this.widget;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? Strings.of(context).pickBusiness),
        actions: [
          IconButton(
            onPressed: () => context.go(Routes.directory),
            icon: const Icon(Icons.storefront_outlined),
            tooltip: context.tr('Les vitrines'),
          ),
          if (widget.onBusinesses != null)
            IconButton(
              onPressed: widget.onBusinesses,
              icon: const Icon(Icons.business_outlined),
              tooltip: Strings.of(context).manageBusinesses,
            ),
          if (widget.onCreateBusiness != null)
            IconButton(
              onPressed: widget.onCreateBusiness,
              icon: const Icon(Icons.add_business_outlined),
              tooltip: Strings.of(context).newBusiness,
            ),
          if (widget.onSignOut != null)
            IconButton(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
              tooltip: Strings.of(context).signOut,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child:
              widget.orgs.isEmpty ? _empty(context) : _list(context, theme),
        ),
      ),
    );
  }

  /// Loading or truly empty — never a blank page. While the list is still on
  /// its way this is a spinner; once it has arrived empty (a rare state, since
  /// the router sends someone who belongs to nothing to the waiting room) it
  /// is a plain message rather than a screen that looks broken.
  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.loading) {
      return _LoadingWithEscape(
          onRetry: widget.onRetry, onSignOut: widget.onSignOut);
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.business_outlined,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            context.tr('Aucune entreprise pour l\'instant.'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, ThemeData theme) {
    final orgs = widget.orgs;
    final counts = <String, int>{};
    for (final o in orgs) {
      final k = kindOfProfile(o.profile);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    // A chip per kind only when there is more than one kind to tell apart.
    final kinds = [
      for (final k in const ['retail', 'farm', 'association'])
        if ((counts[k] ?? 0) > 0) k,
    ];
    final showChips = kinds.length > 1;
    final showSearch = orgs.length >= OrgPickerScreen.searchFrom;
    final kind = showChips ? _kind : null;
    final query = showSearch ? _fold(_search.text.trim()) : '';
    final shown = [
      for (final o in orgs)
        if ((kind == null || kindOfProfile(o.profile) == kind) &&
            (query.isEmpty ||
                _fold(o.name).contains(query) ||
                _fold(o.ownerName ?? '').contains(query)))
          o,
    ];

    final header = <Widget>[
      if (showSearch)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            key: const Key('picker-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: context.tr('Nom ou propriétaire'),
              border: const OutlineInputBorder(),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.tr('Effacer'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
      if (showChips)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const Key('picker-kind-all'),
                label: Text(context.tr('Toutes')),
                showCheckmark: false,
                selectedColor: maraDeep.withValues(alpha: 0.16),
                side: _chipSide(kind == null, maraDeep),
                selected: kind == null,
                onSelected: (_) => setState(() => _kind = null),
              ),
              for (final k in kinds)
                ChoiceChip(
                  key: Key('picker-kind-$k'),
                  avatar: Icon(iconForProfile(k),
                      size: 18, color: kindColour(k)),
                  label: Text('${kindPlural(context, k)} · ${counts[k]}'),
                  showCheckmark: false,
                  selectedColor: kindColour(k).withValues(alpha: 0.22),
                  side: _chipSide(kind == k, kindColour(k)),
                  selected: kind == k,
                  onSelected: (on) => setState(() => _kind = on ? k : null),
                ),
            ],
          ),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...header,
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              context.tr('Aucune activité ne correspond.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _OrgCard(org: shown[i], onTap: () => widget.onSelected(shown[i])),
        ],
      ],
    );
  }
}

/// One activity: its kind's colour and picture, its name, what it is and
/// your role, and — when the server says — whose it is.
class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org, required this.onTap});

  final OrgSummary org;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = kindOfProfile(org.profile);
    final owner = org.ownerName;
    return KajCard(
      key: Key('picker-org-${org.id}'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The kind's colour down the edge, so a long list reads in
              // colour before a word of it is read.
              Container(width: 6, color: kindColour(kind)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: kindColour(kind),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          iconForProfile(org.profile),
                          size: 28,
                          color: kindInk(kind),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              org.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                localizedProfile(context, org.profile),
                                if (org.roles.isNotEmpty)
                                  labelForRole(org.roles.first),
                              ].join(' · '),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                            if (owner != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.person_outline,
                                      size: 16,
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      owner,
                                      key: Key('picker-owner-${org.id}'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
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

/// A chip's edge: the kind's colour, firm when chosen.
BorderSide? _chipSide(bool selected, Color colour) =>
    selected ? BorderSide(color: colour, width: 1.5) : null;

/// Lowercase without accents, so « eglise » finds « Église ».
String _fold(String text) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

/// The three kinds of business (100): 'church' is the association's older
/// name; anything unknown is 'other'.
String kindOfProfile(String profile) => switch (profile) {
      'church' || 'association' => 'association',
      'farm' => 'farm',
      'retail' => 'retail',
      _ => 'other',
    };

/// Each kind's colour, from the brand palette: caramel for a shop, green for
/// a farm, brown for an association, graphite for anything else.
Color kindColour(String kind) => switch (kindOfProfile(kind)) {
      'retail' => maraCaramel,
      'farm' => maraGreen,
      'association' => maraBrown,
      _ => maraDeep,
    };

/// What is drawn on [kindColour]: ink on caramel, paper on the dark ones.
Color kindInk(String kind) =>
    kindOfProfile(kind) == 'retail' ? maraBlack : maraPaper;

/// The chip's word: the kind, in the plural.
String kindPlural(BuildContext context, String kind) =>
    switch (kindOfProfile(kind)) {
      'retail' => context.tr('Boutiques'),
      'farm' => context.tr('Fermes'),
      'association' => context.tr('Associations'),
      _ => context.tr('Autres'),
    };

/// The loading state, with an escape hatch.
///
/// A resolve that stalls now falls back to the cached list within seconds, so
/// the spinner is normally brief. But no spinner on this app may be a trap:
/// after a short wait this reveals "Réessayer" and "Se déconnecter", so a
/// person whose resolve never returns — a wedged local store, a connection
/// that neither answers nor errors — always has a way out instead of a screen
/// that loads forever.
class _LoadingWithEscape extends StatefulWidget {
  const _LoadingWithEscape({this.onRetry, this.onSignOut});

  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  State<_LoadingWithEscape> createState() => _LoadingWithEscapeState();
}

class _LoadingWithEscapeState extends State<_LoadingWithEscape> {
  bool _stuck = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Long enough that a normal resolve (bounded to ~12s per network step, and
    // usually far quicker) has finished and moved us off this screen; short
    // enough that a person is not left wondering. If we are still here at 10s,
    // something is wrong and they should be offered a way out.
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _stuck = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(context.tr('Chargement de vos entreprises…'),
              style: theme.textTheme.bodyMedium),
          if (_stuck) ...[
            const SizedBox(height: 24),
            Text(
              context.tr('Cela prend plus de temps que prévu.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (widget.onRetry != null)
              FilledButton.icon(
                onPressed: () {
                  setState(() => _stuck = false);
                  _timer?.cancel();
                  _timer = Timer(const Duration(seconds: 10), () {
                    if (mounted) setState(() => _stuck = true);
                  });
                  widget.onRetry!();
                },
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('Réessayer')),
              ),
            if (widget.onSignOut != null)
              TextButton(
                onPressed: widget.onSignOut,
                child: Text(context.tr('Se déconnecter')),
              ),
          ],
        ],
      ),
    );
  }
}

IconData iconForProfile(String profile) {
  switch (profile) {
    case 'church':
    case 'association':
      return Icons.groups_outlined;
    case 'farm':
      return Icons.agriculture_outlined;
    case 'retail':
      return Icons.storefront_outlined;
    default:
      return Icons.business_outlined;
  }
}

/// The localized profile label. The plain [labelForProfile] stays for the
/// screens not yet migrated; new code takes this one.
String localizedProfile(BuildContext context, String profile) {
  final strings = Strings.of(context);
  switch (profile) {
    case 'church':
    case 'association':
      return strings.church;
    case 'farm':
      return strings.farm;
    case 'retail':
      return strings.shop;
    default:
      return strings.business;
  }
}

String labelForProfile(String profile) {
  switch (profile) {
    case 'church':
    case 'association':
      return 'Association';
    case 'farm':
      return 'Ferme';
    case 'retail':
      return 'Commerce';
    default:
      return 'Activité';
  }
}

String labelForRole(String role) {
  switch (role) {
    case 'owner':
      return 'Propriétaire';
    // What my_orgs() says for the platform's own team, who belong to no
    // business and see all of them (010) — shown raw until now.
    case 'platform_admin':
      return 'Plateforme';
    case 'super_admin':
      return 'Super administrateur';
    case 'admin':
      return 'Administrateur';
    case 'manager':
      return 'Gestionnaire';
    case 'supervisor':
      return 'Superviseur';
    case 'employee':
      return 'Employé';
    case 'observer':
      return 'Observateur';
    case 'approver':
      return 'Approbateur';
    default:
      return role;
  }
}

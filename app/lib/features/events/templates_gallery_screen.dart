import 'package:flutter/material.dart';

import '../../core/auth/auth_repository.dart' show AuthRepository;
import '../../core/auth/models.dart' show OrgSummary;
import '../../core/events/events_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/bell_room.dart';
import '../account/pro_sheet.dart';
import 'events_screens.dart';

/// « Modèles » (153, chosen the owner's way in 155b): the designs a card
/// may take, each with its picture — the classic cards and the animated
/// layouts, the Premium films among them. A tap shows the design large
/// ([TemplatePreviewScreen]); from there « Utiliser ce modèle » gives it
/// to a card: the one being made ([draft]), the one it was opened for
/// ([forEvent], « Changer de modèle » on a card's page), or — browsing —
/// one of the business's cards, or a new one.
class TemplatesGalleryScreen extends StatefulWidget {
  const TemplatesGalleryScreen({
    super.key,
    required this.events,
    required this.org,
    this.draft,
    this.forEvent,
    this.now,
    this.embedded = false,
    this.open,
  });

  final EventsRepository events;
  final OrgSummary org;

  /// How a page of the site is opened (« Voir le modèle en vrai »): the
  /// app's way, or a test's stand-in.
  final Future<void> Function(Uri)? open;

  /// The card being made: its name, kind, day and place, waiting for its
  /// design. Chosen, the card is created and handed back.
  final EventDraft? draft;

  /// An existing card changing its design (« Changer de modèle »). Chosen,
  /// the card takes it and true is handed back.
  final EventSummary? forEvent;

  /// The clock, for the tests.
  final DateTime Function()? now;

  /// Drawn inside another page (the home's bar around it): no AppBar.
  final bool embedded;

  @override
  State<TemplatesGalleryScreen> createState() => _TemplatesGalleryScreenState();
}

class _TemplatesGalleryScreenState extends State<TemplatesGalleryScreen> {
  List<EventTemplate> _templates = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.events.templates();
    if (!mounted) return;
    setState(() {
      _templates = list;
      _loading = false;
    });
  }

  /// A tap shows the design large; what the preview hands back comes
  /// back up: the new card (for a draft), or true (for a card changed).
  Future<void> _pick(EventTemplate t) async {
    final result = await Navigator.of(context).push<Object>(MaterialPageRoute<Object>(
      builder: (_) => TemplatePreviewScreen(
        events: widget.events,
        org: widget.org,
        template: t,
        draft: widget.draft,
        forEvent: widget.forEvent,
        now: widget.now,
        open: widget.open,
      ),
    ));
    if (!mounted || result == null) return;
    if (widget.draft != null || widget.forEvent != null) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final forEvent = widget.forEvent;
    final forTitle = draft?.title ?? forEvent?.title;
    final kind = draft?.kind ?? forEvent?.kind;
    final classic = [for (final t in _templates) if (!t.isAnimated) t];
    final animated = [for (final t in _templates) if (t.isAnimated) t];
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : DefaultTabController(
            length: 2,
            // The family of the card's current design opens first.
            initialIndex: forEvent != null && forEvent.card.startsWith('anime_') ? 1 : 0,
            child: Column(children: [
              if (forTitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    context.tr('Le modèle de « {title} »', {'title': forTitle}),
                    key: const Key('gallery-for'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              TabBar(
                key: const Key('gallery-tabs'),
                tabs: [
                  Tab(key: const Key('family-classique'), text: context.tr('Classique')),
                  Tab(key: const Key('family-anime'), text: context.tr('Animé')),
                ],
              ),
              Expanded(
                child: TabBarView(children: [
                  _Grid(templates: classic, kind: kind, current: forEvent?.card, onPick: _pick),
                  _Grid(templates: animated, kind: kind, current: forEvent?.card, onPick: _pick),
                ]),
              ),
            ]),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(forTitle == null
            ? context.tr('Modèles')
            : forEvent != null
                ? context.tr('Changer de modèle')
                : context.tr('Choisir le modèle')),
        actions: const [bellRoom],
      ),
      body: body,
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.templates, required this.kind, required this.current, required this.onPick});

  final List<EventTemplate> templates;
  final String? kind;

  /// The card's design today, marked « Actuel ».
  final String? current;
  final void Function(EventTemplate) onPick;

  @override
  Widget build(BuildContext context) {
    // The designs drawn for this kind of event first, the rest after.
    final k = kind;
    final sorted = k == null
        ? templates
        : [
            for (final t in templates) if (t.kinds.contains(k)) t,
            for (final t in templates) if (!t.kinds.contains(k)) t,
          ];
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.56,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, i) =>
          _Tile(template: sorted[i], current: sorted[i].key == current, onTap: () => onPick(sorted[i])),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.template, required this.current, required this.onTap});

  final EventTemplate template;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: Key('template-${template.key}'),
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              TemplatePicture(template: template),
              if (template.premium || current)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Chip(
                    label: Text(current ? context.tr('Actuel') : context.tr('Premium')),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    backgroundColor: current ? scheme.primaryContainer : scheme.tertiaryContainer,
                    labelStyle: theme.textTheme.labelSmall
                        ?.copyWith(color: current ? scheme.onPrimaryContainer : scheme.onTertiaryContainer),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(template.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (template.line.isNotEmpty)
                Text(template.line, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A design's picture (app/web/cartes/apercu, rendered at a phone's
/// width), from the site; its initial on its family's colour before it
/// arrives, or without it.
class TemplatePicture extends StatelessWidget {
  const TemplatePicture({super.key, required this.template, this.alignment = Alignment.topCenter, this.fit = BoxFit.cover});

  final EventTemplate template;
  final Alignment alignment;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.network(
        '${eventSiteOrigin()}${template.previewPath()}',
        fit: fit,
        alignment: alignment,
        errorBuilder: (_, _, _) => _Blank(template: template),
        loadingBuilder: (context, child, progress) => progress == null ? child : _Blank(template: template),
      );
}

class _Blank extends StatelessWidget {
  const _Blank({required this.template});
  final EventTemplate template;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: template.isAnimated ? scheme.tertiaryContainer : scheme.secondaryContainer,
      child: Center(
        child: Text(
          template.name.isEmpty ? '?' : template.name.substring(0, 1),
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: template.isAnimated ? scheme.onTertiaryContainer : scheme.onSecondaryContainer,
              ),
        ),
      ),
    );
  }
}

/// One design, large (155b): its picture, its name and line, the kinds of
/// event it was drawn for, and « Utiliser ce modèle ». What that does
/// depends on where the gallery was opened from — see
/// [TemplatesGalleryScreen].
class TemplatePreviewScreen extends StatefulWidget {
  const TemplatePreviewScreen({
    super.key,
    required this.events,
    required this.org,
    required this.template,
    this.draft,
    this.forEvent,
    this.now,
    this.open,
  });

  final EventsRepository events;
  final OrgSummary org;
  final EventTemplate template;
  final EventDraft? draft;
  final EventSummary? forEvent;
  final DateTime Function()? now;
  final Future<void> Function(Uri)? open;

  @override
  State<TemplatePreviewScreen> createState() => _TemplatePreviewScreenState();
}

class _TemplatePreviewScreenState extends State<TemplatePreviewScreen> {
  bool _busy = false;

  /// The design as the guests would see it (155c): the site's sample
  /// page, inside the app.
  Future<void> _demo() async {
    final uri = Uri.parse('${eventSiteOrigin()}/modele/${widget.template.key}');
    final open = widget.open;
    if (open != null) return open(uri);
    await openSitePage(uri);
  }

  /// A Premium design for a business that is not Pro (157): the Pro sheet,
  /// as every Pro door opens it; the server refuses the design anyway.
  void _pro() {
    final scope = AppScope.maybeOf(context);
    if (scope == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Ce modèle fait partie de Marakaj Pro. Ouvrez Compte › Marakaj Pro.'))));
      return;
    }
    ProSheet.open(context, org: widget.org, terms: scope.session.planTerms, admin: scope.admin, canRequest: widget.org.isAdmin);
  }

  Future<void> _use() async {
    if (_busy) return;
    final t = widget.template;
    final draft = widget.draft;
    final forEvent = widget.forEvent;
    setState(() => _busy = true);
    try {
      if (draft != null) {
        // The card being made: created with this design, handed back.
        final made = await widget.events.create(
          orgId: widget.org.id,
          title: draft.title,
          kind: draft.kind,
          card: t.key,
          startsAt: draft.startsAt,
          place: draft.place,
        );
        if (!mounted) return;
        Navigator.of(context).pop(made);
        return;
      }
      if (forEvent != null) {
        // The card this was opened for takes the design; its words, day
        // and place stay its own.
        await widget.events.setCard(forEvent.id, t.key);
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      // Browsing: which card? One of the business's, or a new one.
      final cards = await widget.events.list(widget.org.id);
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Object>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (ctx) => _WhichCard(cards: cards, template: t),
      );
      if (!mounted || chosen == null) return;
      if (chosen == _newCard) {
        final made = await startNewCard(context, widget.events, widget.org, now: widget.now, card: t.key);
        if (made != null && mounted) {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => EventScreen(events: widget.events, org: widget.org, eventId: made.id, first: made),
          ));
        }
        return;
      }
      final card = chosen as EventSummary;
      await widget.events.setCard(card.id, t.key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Modèle changé'))));
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EventScreen(events: widget.events, org: widget.org, eventId: card.id),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = widget.template;
    final draft = widget.draft;
    final forEvent = widget.forEvent;
    final current = forEvent != null && forEvent.card == t.key;
    final locked = t.premium && !widget.org.isPro;
    final buttons = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            key: const Key('template-demo'),
            onPressed: _demo,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(context.tr('Voir le modèle en vrai')),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('template-use'),
            onPressed: _busy || current
                ? null
                : locked
                    ? _pro
                    : _use,
            icon: Icon(locked
                ? Icons.lock_outline
                : draft != null
                    ? Icons.check
                    : Icons.auto_awesome_outlined),
            label: Text(current
                ? context.tr('Le modèle actuel de cette carte')
                : locked
                    ? context.tr('Modèle Premium : passer à Marakaj Pro')
                    : draft != null
                    ? context.tr('Créer la carte avec ce modèle')
                    : context.tr('Utiliser ce modèle')),
          ),
        ),
      ]),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.name), actions: const [bellRoom]),
      // The page scrolls above the buttons, which keep the foot of the
      // screen whatever the scroll: the picture is a whole phone tall, and
      // nothing of it hides under them (the owner saw it cut).
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
          // The picture whole, at the proportions it was rendered at (a
          // phone's, 390 × 844): nothing cut.
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 390 / 844,
              child: Stack(fit: StackFit.expand, children: [
                TemplatePicture(template: t, fit: BoxFit.contain),
                if (t.premium)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Chip(
                      label: Text(context.tr('Premium')),
                      backgroundColor: scheme.tertiaryContainer,
                      labelStyle: theme.textTheme.labelMedium?.copyWith(color: scheme.onTertiaryContainer),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Text(t.name, style: theme.textTheme.titleLarge),
          if (t.line.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(t.line, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 6),
          Text(
            t.isAnimated
                ? context.tr('Animé : une page qui bouge, ses couleurs et son écriture au choix.')
                : context.tr('Classique : une carte à faire défiler, ses textes et ses photos au choix.'),
            style: theme.textTheme.bodySmall,
          ),
          if (t.kinds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in t.kinds)
                Chip(label: Text(context.tr(eventKindName(k))), visualDensity: VisualDensity.compact),
            ]),
          ],
          const SizedBox(height: 10),
          Text(
            context.tr('La carte telle que vos invités la verront, avec des mots d’exemple ; elle s’ouvre dans l’application.'),
            style: theme.textTheme.bodySmall,
          ),
          if (locked) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('Ce modèle fait partie de Marakaj Pro : passez à Pro pour l’utiliser. Vous pouvez le voir en vrai.'),
              key: const Key('template-premium-note'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.tertiary),
            ),
          ],
          if (forEvent != null || draft != null) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('Pour « {title} » : ses mots, sa date et son lieu restent les siens.',
                  {'title': forEvent?.title ?? draft!.title}),
              style: theme.textTheme.bodySmall,
            ),
          ],
            ],
          ),
        ),
        SafeArea(top: false, child: buttons),
      ]),
    );
  }
}

/// The sheet's answer for « Nouvelle carte ».
const _newCard = Object();

/// « Pour quelle carte ? » (155b): the business's cards, and a new one.
class _WhichCard extends StatelessWidget {
  const _WhichCard({required this.cards, required this.template});

  final List<EventSummary> cards;
  final EventTemplate template;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(context.tr('Pour quelle carte ?'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(context.tr('Modèle : {name}', {'name': template.name}), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          // Plain cards: KajCard shows itself on scroll, and a sheet does not
          // scroll — the owner saw an empty sheet.
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: const Key('use-new-card'),
              leading: const Icon(Icons.add_circle_outline),
              title: Text(context.tr('Nouvelle carte')),
              subtitle: Text(context.tr('Ses mots, sa date et son lieu, puis la carte.')),
              onTap: () => Navigator.of(context).pop(_newCard),
            ),
          ),
          for (final c in cards)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: Key('use-card-${c.id}'),
                leading: const Icon(Icons.card_giftcard_outlined),
                title: Text(c.title),
                subtitle: Text(
                  '${context.tr(eventKindName(c.kind))} · ${context.tr('modèle')} ${eventCardName(c.card)}',
                ),
                trailing: c.card == template.key ? Text(context.tr('Actuel'), style: theme.textTheme.labelMedium) : null,
                onTap: c.card == template.key ? null : () => Navigator.of(context).pop(c),
              ),
            ),
        ],
      ),
    );
  }
}

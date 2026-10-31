import 'package:flutter/material.dart';

import '../../core/auth/auth_repository.dart' show AuthRepository;
import '../../core/auth/models.dart' show OrgSummary;
import '../../core/events/events_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import 'events_screens.dart';

/// « Modèles » (153): the designs a card may take, each with its picture —
/// the classic cards and the animated layouts, the Premium films among
/// them. Choosing one for a new card ([draft] given) creates the card and
/// hands it back; browsing ([draft] null) opens « Nouvelle carte » with
/// that design chosen.
class TemplatesGalleryScreen extends StatefulWidget {
  const TemplatesGalleryScreen({
    super.key,
    required this.events,
    required this.org,
    this.draft,
    this.now,
    this.embedded = false,
  });

  final EventsRepository events;
  final OrgSummary org;

  /// The card being made: its name, kind, day and place, waiting for its
  /// design.
  final EventDraft? draft;

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
  bool _busy = false;

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

  Future<void> _pick(EventTemplate t) async {
    if (_busy) return;
    final draft = widget.draft;
    if (draft == null) {
      // Browsing: the card's words first, with this design chosen.
      final made = await startNewCard(context, widget.events, widget.org, now: widget.now, card: t.key);
      if (made != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EventScreen(events: widget.events, org: widget.org, eventId: made.id, first: made),
        ));
      }
      return;
    }
    setState(() => _busy = true);
    try {
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthRepository.describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final classic = [for (final t in _templates) if (!t.isAnimated) t];
    final animated = [for (final t in _templates) if (t.isAnimated) t];
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : DefaultTabController(
            length: 2,
            child: Column(children: [
              if (draft != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    context.tr('Le modèle de « {title} »', {'title': draft.title}),
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
                  _Grid(templates: classic, kind: draft?.kind, busy: _busy, onPick: _pick),
                  _Grid(templates: animated, kind: draft?.kind, busy: _busy, onPick: _pick),
                ]),
              ),
            ]),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(draft == null ? context.tr('Modèles') : context.tr('Choisir le modèle')),
        actions: const [bellRoom],
      ),
      body: body,
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.templates, required this.kind, required this.busy, required this.onPick});

  final List<EventTemplate> templates;
  final String? kind;
  final bool busy;
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
      itemBuilder: (context, i) => _Tile(template: sorted[i], busy: busy, onTap: () => onPick(sorted[i])),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.template, required this.busy, required this.onTap});

  final EventTemplate template;
  final bool busy;
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
        onTap: busy ? null : onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Image.network(
                '${eventSiteOrigin()}${template.previewPath()}',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => _Blank(template: template),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _Blank(template: template),
              ),
              if (template.premium)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Chip(
                    label: Text(context.tr('Premium')),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    backgroundColor: scheme.tertiaryContainer,
                    labelStyle: theme.textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer),
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

/// Before the picture arrives, or without it: the design's initial on its
/// family's colour.
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

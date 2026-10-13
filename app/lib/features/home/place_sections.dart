import 'package:flutter/material.dart';

import '../../core/notify/bell_room.dart';
import '../../core/theme/app_bar_title.dart';

/// One section of a place on the bar (134): Catalogue's Articles and
/// Services, Argent's Factures, Dépenses and Crédit, the farm's À vendre,
/// Commandes and Factures.
///
/// A section is one of the screens the business already had — the
/// articles, « Mes services », the invoices, the carnet — drawn inside the
/// place instead of as a page of its own: one tab, one address, a switch
/// at the top.
class PlaceSection {
  const PlaceSection({
    required this.id,
    required this.label,
    required this.build,
    this.count,
  });

  /// Its word in the address (`?partie=factures`).
  final String id;
  final String label;

  /// What waits in it, said beside its word (« Commandes · 2 »); null or 0
  /// says nothing.
  final int? count;

  /// The screen, as it is as a page of its own: inside a [SectionHost] its
  /// bar says the place's name and its body stands under the switch.
  final Widget Function(BuildContext context) build;
}

/// What a screen drawn as a section reads from the place around it (134):
/// the place's name for its bar, what stands above its body (the switch,
/// Argent's four numbers), the place's own actions, and whether the place
/// keeps the « ＋ » (Catalogue's single one asks « un article ou un
/// service ? »), so the screen's own is not drawn twice.
class SectionHost extends InheritedWidget {
  const SectionHost({
    super.key,
    required this.title,
    required this.header,
    this.actions = const [],
    this.ownsAdd = false,
    required super.child,
  });

  final String title;
  final Widget header;
  final List<Widget> actions;
  final bool ownsAdd;

  static SectionHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SectionHost>();

  /// The bar of a screen that may be a section: its own [title] and
  /// [actions] as a page of its own; inside a place, the place's name and
  /// the place's actions before its own.
  static PreferredSizeWidget appBar(
    BuildContext context, {
    required Widget title,
    List<Widget> actions = const [],
    PreferredSizeWidget? bottom,
  }) {
    final host = of(context);
    if (host == null) {
      return AppBar(
        title: title,
        // The screen's own, ending with its bellRoom (115).
        actions: actions,
        bottom: bottom,
      );
    }
    return AppBar(
      title: AppBarTitle(host.title),
      // The place's own first, then the screen's — its bellRoom last.
      actions: [...host.actions, ...actions],
    );
  }

  /// The body of a screen that may be a section: inside a place, the
  /// place's header stands above it.
  static Widget body(BuildContext context, Widget body) {
    final host = of(context);
    if (host == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [host.header, Expanded(child: body)],
    );
  }

  /// Whether the place keeps the « ＋ » (the screen then draws none).
  static bool ownsAddOf(BuildContext context) => of(context)?.ownsAdd ?? false;

  @override
  bool updateShouldNotify(SectionHost oldWidget) =>
      title != oldWidget.title ||
      header != oldWidget.header ||
      actions != oldWidget.actions ||
      ownsAdd != oldWidget.ownsAdd;
}

/// The switch at the top of a place (134): its sections as pills, the one
/// on screen filled — the mockup's « Articles · 42 | Services · 5 ».
class SectionSwitch extends StatelessWidget {
  const SectionSwitch({
    super.key,
    required this.sections,
    required this.current,
    required this.onPick,
  });

  final List<PlaceSection> sections;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final s in sections)
            Expanded(
              child: Semantics(
                selected: s.id == current,
                button: true,
                child: Material(
                  key: Key('section-${s.id}'),
                  color: s.id == current ? scheme.surface : Colors.transparent,
                  elevation: s.id == current ? 1 : 0,
                  borderRadius: BorderRadius.circular(11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => onPick(s.id),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        // One line, smaller when it must: a word cut in two
                        // (« Command|es · 2 » at 320 px, 1.3) reads worse.
                        child: Center(
                          child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            (s.count ?? 0) > 0 ? '${s.label} · ${s.count}' : s.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight:
                                  s.id == current ? FontWeight.w700 : FontWeight.w500,
                              color: s.id == current
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A place made of sections (134): the section on screen, under the
/// place's name and its switch. [initial] is the address's `?partie=`;
/// an unknown or hidden one opens [fallback] (else the first).
///
/// [enter] is asked before a section opens from the switch — Factures'
/// lock (089) lives there, exactly as it did on the bar: closed, the sheet
/// says what it waits for and « lecture seule » still opens it. Opened
/// from the address it is not asked, as the old page's address was not.
class PlaceSections extends StatefulWidget {
  const PlaceSections({
    super.key,
    required this.title,
    required this.sections,
    this.initial,
    this.fallback,
    this.enter,
    this.above,
    this.below,
    this.actions,
    this.ownsAdd = false,
  });

  final String title;
  final List<PlaceSection> sections;
  final String? initial;
  final String? fallback;
  final void Function(BuildContext context, String id, VoidCallback open)? enter;

  /// Above the switch (Argent's four numbers) and below it (the farm's
  /// Crédit), whatever the section.
  final Widget? above;
  final Widget? below;

  /// The place's own actions on the bar; [reload] draws the section on
  /// screen afresh (after the place's « ＋ » saved something).
  final List<Widget> Function(BuildContext context, VoidCallback reload)? actions;
  final bool ownsAdd;

  @override
  State<PlaceSections> createState() => PlaceSectionsState();
}

class PlaceSectionsState extends State<PlaceSections> {
  late String _current = _pick(widget.initial);
  int _round = 0;

  /// The section on screen.
  String get current => _current;

  String _pick(String? wanted) {
    final ids = [for (final s in widget.sections) s.id];
    if (wanted != null && ids.contains(wanted)) return wanted;
    final fb = widget.fallback;
    if (fb != null && ids.contains(fb)) return fb;
    return ids.isEmpty ? '' : ids.first;
  }

  @override
  void didUpdateWidget(PlaceSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new address (a bell opened Argent › Crédit while Argent was on
    // screen): its section.
    if (widget.initial != oldWidget.initial && widget.initial != null) {
      _current = _pick(widget.initial);
    } else if (!widget.sections.any((s) => s.id == _current)) {
      _current = _pick(null);
    }
  }

  /// Draws the section on screen afresh: it reads itself again.
  void reload() => setState(() => _round++);

  void _go(String id) {
    if (id == _current) return;
    final enter = widget.enter;
    void open() {
      if (mounted) setState(() => _current = id);
    }

    if (enter == null) {
      open();
    } else {
      enter(context, id, open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    if (sections.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: AppBarTitle(widget.title), actions: const [bellRoom]),
        body: const SizedBox.shrink(),
      );
    }
    final section = sections.firstWhere((s) => s.id == _current,
        orElse: () => sections.first);
    final header = Padding(
      key: const Key('place-header'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.above != null) ...[widget.above!, const SizedBox(height: 10)],
          if (sections.length > 1)
            SectionSwitch(sections: sections, current: section.id, onPick: _go),
          if (widget.below != null) ...[const SizedBox(height: 8), widget.below!],
        ],
      ),
    );
    return SectionHost(
      title: widget.title,
      header: header,
      actions: widget.actions?.call(context, reload) ?? const [],
      ownsAdd: widget.ownsAdd,
      child: KeyedSubtree(
        key: ValueKey('${section.id}#$_round'),
        child: Builder(builder: section.build),
      ),
    );
  }
}

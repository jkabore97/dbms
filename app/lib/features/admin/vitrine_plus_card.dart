import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/capture/models.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../account/pro_sheet.dart';
import '../storefront/open_badge.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// « Habiller ma vitrine » (093), under « Vitrine avancée ». The basics
/// are every business's: a cover from its own photographs, one of six
/// colours, a tagline and the opening days and hours. The arrangement is
/// Mara Pro (068's vitrine_plus): the shelf's layout, up to six articles
/// à la une, out-of-stock left off, and the live « Ouvert maintenant »
/// banner. A preview at the top draws the window as the street will.
/// The server decides regardless of the drawing.
class VitrinePlusCard extends StatefulWidget {
  const VitrinePlusCard({
    super.key,
    required this.orgId,
    required this.admin,
    this.retail,
    this.capture,
    this.shopName,
  });

  final String orgId;
  final AdminRepository admin;

  /// For the pinned-article picker and the preview; null with no server.
  final RetailRepository? retail;

  /// For the cover picker: the shop's own photographs.
  final CaptureRepository? capture;

  /// The name drawn in the preview.
  final String? shopName;

  /// The palette a shop may pick its button colour from: six that read on
  /// the street's paper, chosen once so no vitrine ends up unreadable. The
  /// server holds the same six (vitrine_free_accents, 093); Mara's vitrine
  /// by default for a kind (107) offers them too.
  static const accents = <Color>[
    Color(0xFFB1541A),
    Color(0xFF2E7D5B),
    Color(0xFF1F5FA8),
    Color(0xFF8E3B6B),
    Color(0xFFB8860B),
    Color(0xFF444444),
  ];

  @override
  State<VitrinePlusCard> createState() => _VitrinePlusCardState();
}

class _VitrinePlusCardState extends State<VitrinePlusCard> {
  static const accents = VitrinePlusCard.accents;

  /// The times offered for opening and closing: every half hour.
  static final times = [
    for (var h = 0; h < 24; h++)
      for (final m in const ['00', '30']) '${h.toString().padLeft(2, '0')}:$m',
  ];

  final _tagline = TextEditingController();
  Color? _accent;
  String? _coverKey;
  List<String> _pinned = const [];
  bool _hideOut = false;
  VitrineLayout _layout = VitrineLayout.grid;
  Set<int> _days = {};
  String _open = '08:00';
  String _close = '19:00';

  /// A line of hours written before 093, kept until days are chosen.
  String? _legacyHours;

  List<CapturedDocument> _photos = const [];
  List<Product> _products = const [];
  bool _loading = true;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tagline.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final style = await widget.admin.storefrontStyle(widget.orgId);
      var photos = const <CapturedDocument>[];
      var products = const <Product>[];
      try {
        photos =
            await widget.capture?.documents(widget.orgId, limit: 40) ??
            const [];
      } catch (_) {}
      try {
        products = await widget.retail?.products(widget.orgId) ?? const [];
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _tagline.text = style.tagline ?? '';
        _accent = style.accent;
        _coverKey = style.coverKey;
        _pinned = style.pinned;
        _hideOut = style.hideOutOfStock;
        _layout = style.layout;
        final schedule = style.schedule;
        if (schedule != null) {
          _days = schedule.days.toSet();
          _open = schedule.open;
          _close = schedule.close;
        } else {
          _legacyHours = style.hours;
        }
        _photos = photos;
        _products = products.where((p) => p.isPublished).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = describeError(error);
      });
    }
  }

  VitrineSchedule? get _schedule {
    if (_days.isEmpty || _open == _close) return null;
    return VitrineSchedule(
      days: _days.toList()..sort(),
      open: _open,
      close: _close,
    );
  }

  bool get _locked {
    final scope = AppScope.maybeOf(context);
    return scope?.session.accessFor(widget.orgId).isProLocked('vitrine_plus') ??
        false;
  }

  /// Vitrine Plus hidden by Mara's switchboard for this business (110): the
  /// basics only — no Pro part drawn, locked or open, and none saved.
  bool get _plusHidden =>
      AppScope.maybeOf(context)?.session.accessFor(widget.orgId).isHidden('vitrine_plus') ??
      false;

  StorefrontStyle _style({required bool plus}) {
    final schedule = _schedule;
    return StorefrontStyle(
      tagline: _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
      // The line the street reads, in French, written from the days; a
      // line from before 093 stays until days are chosen.
      hours: schedule?.label() ?? _legacyHours,
      schedule: schedule,
      accent: _accent,
      coverKey: _coverKey,
      pinned: plus ? _pinned : const [],
      hideOutOfStock: plus && _hideOut,
      layout: plus ? _layout : VitrineLayout.grid,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.admin.setStorefrontStyle(
        widget.orgId,
        _style(plus: !_locked && !_plusHidden),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = context.tr(
          'Vitrine enregistrée. Ouvrez-la pour voir le résultat.',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = describeError(error);
      });
      if (isProRefusal(error)) _openPro();
    }
  }

  void _openPro() {
    final scope = AppScope.maybeOf(context);
    final org = scope?.session.orgById(widget.orgId);
    if (scope == null || org == null) return;
    ProSheet.open(
      context,
      org: org,
      terms: scope.session.planTerms,
      admin: widget.admin,
      canRequest: org.isAdmin,
      feature: 'vitrine_plus',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = _locked;
    final plusHidden = _plusHidden;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lang = context.trLanguage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Habiller ma vitrine'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
            'Choisissez, l\'aperçu montre aussitôt ce que verront vos clients.',
          ),
          style: muted,
        ),
        const SizedBox(height: 12),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else ...[
          VitrinePreview(
            key: const Key('vitrine-preview'),
            name: widget.shopName ?? context.tr('Ma vitrine'),
            style: _style(plus: !locked && !plusHidden).copyWith(
              // The preview shows the Pro layout being tried, even locked:
              // seeing it is how a shop decides it wants it. Hidden by Mara
              // (110), there is nothing to try.
              layout: plusHidden ? VitrineLayout.grid : _layout,
            ),
            openNow: _schedule == null || locked || plusHidden
                ? null
                : _openAt(DateTime.now()),
            items: _products,
            capture: widget.capture,
            lang: lang,
          ),
          const SizedBox(height: 18),
          _SectionTitle(text: context.tr('POUR TOUTES LES VITRINES')),
          const SizedBox(height: 10),
          Text(
            context.tr('Photo de couverture'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          if (_photos.isEmpty)
            Text(
              context.tr(
                'Prenez d\'abord une photo de votre devanture dans Photos ; elle apparaîtra ici.',
              ),
              style: muted,
            )
          else
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CoverChoice(
                    selected: _coverKey == null,
                    onTap: _saving
                        ? null
                        : () => setState(() => _coverKey = null),
                    child: Center(child: Text(context.tr('Aucune'))),
                  ),
                  for (final d in _photos)
                    _CoverChoice(
                      selected: _coverKey == d.key,
                      onTap: _saving
                          ? null
                          : () => setState(() => _coverKey = d.key),
                      child: _Thumb(document: d, capture: widget.capture),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text(
            context.tr('Couleur des boutons'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Swatch(
                colour: null,
                selected: _accent == null,
                onTap: _saving ? null : () => setState(() => _accent = null),
              ),
              for (final c in accents)
                _Swatch(
                  colour: c,
                  selected: _accent == c,
                  onTap: _saving ? null : () => setState(() => _accent = c),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _tagline,
            enabled: !_saving,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.tr('Phrase d\'accroche'),
              hintText: context.tr('Ex. : Pagnes et gâteaux depuis 1998, Le café du coin, Frais et local'),
              hintMaxLines: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('Jours d\'ouverture'),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  key: Key('day-$d'),
                  label: Text(_dayLetter(d, lang)),
                  selected: _days.contains(d),
                  showCheckmark: false,
                  onSelected: _saving
                      ? null
                      : (on) => setState(() {
                          _days = {..._days};
                          on ? _days.add(d) : _days.remove(d);
                        }),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  key: const Key('time-open'),
                  label: context.tr('Ouvre à'),
                  value: _open,
                  times: times,
                  lang: lang,
                  onChanged: _saving ? null : (v) => setState(() => _open = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeField(
                  key: const Key('time-close'),
                  label: context.tr('Ferme à'),
                  value: _close,
                  times: times,
                  lang: lang,
                  onChanged: _saving ? null : (v) => setState(() => _close = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _schedule?.label(lang) ??
                (_legacyHours ?? context.tr('Choisissez au moins un jour.')),
            key: const Key('hours-line'),
            style: muted,
          ),
          const SizedBox(height: 22),
          // Locked: one card that says so plainly — what Pro adds, in three
          // lines, and the layouts to try in the preview above. Not the
          // greyed form: a shop read it as settings it had and could not use.
          if (plusHidden)
            const SizedBox.shrink(key: Key('vitrine-plus-hidden'))
          else if (locked)
            _ProLocked(
              layout: _layout,
              onLayout: _saving ? null : (l) => setState(() => _layout = l),
              onPro: _openPro,
            )
          else ...[
            Row(
              children: [
                _SectionTitle(text: context.tr('AVEC MARA PRO')),
                const SizedBox(width: 8),
                const _ProSeal(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                'La présentation, les articles à la une et « Ouvert maintenant ».',
              ),
              style: muted,
            ),
            const SizedBox(height: 10),
            Text(
              context.tr('Présentation des articles'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final l in VitrineLayout.values) ...[
                  Expanded(
                    child: _LayoutChoice(
                      layout: l,
                      selected: _layout == l,
                      onTap: _saving ? null : () => setState(() => _layout = l),
                    ),
                  ),
                  if (l != VitrineLayout.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Articles en tête ({length}/6)', {
                    'length': _pinned.length,
                  }),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                if (_products.isEmpty)
                  Text(
                    context.tr(
                      'Mettez d\'abord des articles sur la vitrine.',
                    ),
                    style: muted,
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final p in _products)
                        FilterChip(
                          label: Text(p.name),
                          selected: _pinned.contains(p.id),
                          onSelected: _saving
                              ? null
                              : (on) => setState(() {
                                  if (on) {
                                    if (_pinned.length >= 6) return;
                                    _pinned = [..._pinned, p.id];
                                  } else {
                                    _pinned = _pinned
                                        .where((id) => id != p.id)
                                        .toList();
                                  }
                                }),
                        ),
                    ],
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _hideOut,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _hideOut = v),
                  title: Text(
                    context.tr('Ne pas afficher les articles épuisés'),
                  ),
                ),
              ],
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 4),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(
              key: const Key('dressing-save'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.storefront_outlined),
              label: Text(context.tr('Enregistrer la vitrine')),
            ),
          ),
        ],
      ],
    );
  }

  /// Whether the schedule being chosen is open at [at] — for the preview
  /// only; the street asks the server.
  bool? _openAt(DateTime at) {
    final s = _schedule;
    if (s == null) return null;
    final utc = at.toUtc(); // Ouagadougou is UTC all year.
    final day = utc.weekday;
    final prev = day == 1 ? 7 : day - 1;
    final now =
        '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}';
    if (s.close.compareTo(s.open) > 0) {
      return s.days.contains(day) &&
          now.compareTo(s.open) >= 0 &&
          now.compareTo(s.close) < 0;
    }
    return (s.days.contains(day) && now.compareTo(s.open) >= 0) ||
        (s.days.contains(prev) && now.compareTo(s.close) < 0);
  }

  static String _dayLetter(int d, String lang) => lang == 'en'
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]
      : const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][d - 1];
}

/// « Vitrine avancée · Mara Pro », locked: a dark card with the seal, what
/// it adds, the three layouts to try in the preview, and the way to Pro.
class _ProLocked extends StatelessWidget {
  const _ProLocked({
    required this.layout,
    required this.onLayout,
    required this.onPro,
  });

  final VitrineLayout layout;
  final ValueChanged<VitrineLayout>? onLayout;
  final VoidCallback onPro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soft = theme.textTheme.bodyMedium
        ?.copyWith(color: maraPaper.withValues(alpha: 0.85));
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: maraCaramel),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr(text), style: soft)),
            ],
          ),
        );
    return Container(
      key: const Key('dressing-pro'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: maraDeep,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: maraCaramel,
                child: Icon(Icons.lock, size: 17, color: maraDeep),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('Vitrine avancée'),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: maraPaper, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: maraCaramel,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  context.tr('MARA PRO'),
                  style: const TextStyle(
                      color: maraDeep,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('Verrouillé : vos clients ne le voient qu\'avec Mara Pro.'),
            key: const Key('dressing-pro-locked'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: maraPaper.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 14),
          line(Icons.view_list, 'Vos articles en liste ou en menu'),
          line(Icons.push_pin, 'Six articles à la une, en tête'),
          line(Icons.schedule, '« Ouvert maintenant » et les épuisés cachés'),
          const SizedBox(height: 6),
          Text(
            context.tr('Essayez dans l\'aperçu :'),
            style: theme.textTheme.labelLarge?.copyWith(color: maraPaper),
          ),
          const SizedBox(height: 8),
          Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(
                surface: maraPaper,
                onSurface: maraBlack,
              ),
            ),
            child: Row(
              children: [
                for (final l in VitrineLayout.values) ...[
                  Expanded(
                    child: Material(
                      color: maraPaper,
                      borderRadius: BorderRadius.circular(12),
                      child: _LayoutChoice(
                        layout: l,
                        selected: layout == l,
                        onTap: onLayout == null ? null : () => onLayout!(l),
                      ),
                    ),
                  ),
                  if (l != VitrineLayout.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('dressing-pro-go'),
              style: FilledButton.styleFrom(
                  backgroundColor: maraCaramel, foregroundColor: maraDeep),
              onPressed: onPro,
              icon: const Icon(Icons.workspace_premium),
              label: Text(context.tr('Voir Mara Pro')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      letterSpacing: 1.3,
      fontWeight: FontWeight.w800,
    ),
  );
}

/// The small black « PRO » seal the other Pro tools carry.
class _ProSeal extends StatelessWidget {
  const _ProSeal();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFF14161C),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      context.tr('PRO'),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    ),
  );
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    super.key,
    required this.label,
    required this.value,
    required this.times,
    required this.lang,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> times;
  final String lang;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: times.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        isDense: true,
      ),
      items: [
        for (final t in times)
          DropdownMenuItem(
            value: t,
            child: Text(VitrineSchedule.clock(t, lang)),
          ),
      ],
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? value),
    );
  }
}

/// One layout to pick: a little drawing of the shelf and its name.
class _LayoutChoice extends StatelessWidget {
  const _LayoutChoice({
    required this.layout,
    required this.selected,
    this.onTap,
  });

  final VitrineLayout layout;
  final bool selected;
  final VoidCallback? onTap;

  static String label(BuildContext context, VitrineLayout l) => switch (l) {
    VitrineLayout.grid => context.tr('Grille'),
    VitrineLayout.large => context.tr('Grandes photos'),
    VitrineLayout.list => context.tr('Liste'),
    VitrineLayout.menu => context.tr('Menu'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (layout) {
      VitrineLayout.grid => Icons.grid_view_rounded,
      VitrineLayout.large => Icons.crop_portrait_rounded,
      VitrineLayout.list => Icons.view_list_rounded,
      VitrineLayout.menu => Icons.restaurant_menu_rounded,
    };
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: Key('layout-${layout.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 26),
              const SizedBox(height: 4),
              Text(
                label(context, layout),
                maxLines: 2,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The window as the street will draw it, small: the cover, the name, the
/// tagline in the shop's colour, the hours and the banner, then the first
/// articles in the chosen layout.
class VitrinePreview extends StatelessWidget {
  const VitrinePreview({
    super.key,
    required this.name,
    required this.style,
    required this.items,
    this.openNow,
    this.capture,
    this.lang = 'fr',
  });

  final String name;
  final StorefrontStyle style;
  final List<Product> items;
  final bool? openNow;
  final CaptureRepository? capture;
  final String lang;

  static const _ink = Color(0xFF14161C);
  static const _stone = Color(0xFFF6F2EA);
  static const _mist = Color(0xFF6E6E6B);

  @override
  Widget build(BuildContext context) {
    final accent = style.accent ?? _ink;
    final shown = items.isEmpty
        ? [
            for (final n in const [
              'Article 1',
              'Article 2',
              'Article 3',
              'Article 4',
            ])
              (n, 1000.0),
          ]
        : [for (final p in items.take(4)) (p.name, p.salePrice)];
    final hours = style.schedule?.label(lang) ?? style.hours;

    Widget square(String n, {double size = 0}) => Container(
      width: size == 0 ? null : size,
      height: size == 0 ? null : size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        n.isEmpty ? '?' : n.characters.first.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: accent,
          fontSize: 16,
        ),
      ),
    );
    String price(double p) => '${p.toStringAsFixed(0)} F';

    final Widget shelf = switch (style.layout) {
      VitrineLayout.grid => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
        children: [
          for (final (n, p) in shown)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: square(n)),
                const SizedBox(height: 3),
                Text(
                  n,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _ink),
                ),
                Text(
                  price(p),
                  style: const TextStyle(fontSize: 10, color: _mist),
                ),
              ],
            ),
        ],
      ),
      VitrineLayout.large => Column(
        children: [
          for (final (n, p) in shown.take(2)) ...[
            AspectRatio(aspectRatio: 1.6, child: square(n)),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    n,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                ),
                Text(
                  price(p),
                  style: const TextStyle(fontSize: 11, color: _mist),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
      VitrineLayout.list => Column(
        children: [
          for (final (n, p) in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  square(n, size: 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n,
                      style: const TextStyle(fontSize: 12, color: _ink),
                    ),
                  ),
                  Text(
                    price(p),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.add_circle, size: 18, color: accent),
                ],
              ),
            ),
        ],
      ),
      VitrineLayout.menu => Column(
        children: [
          for (final (n, p) in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(n, style: const TextStyle(fontSize: 12, color: _ink)),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '·························································',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(fontSize: 10, color: _mist),
                      ),
                    ),
                  ),
                  Text(
                    price(p),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    };

    return Center(
      child: Container(
        width: 260,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _ink, width: 5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (style.coverKey != null)
              SizedBox(
                key: const Key('preview-cover'),
                height: 70,
                child: _Thumb(
                  key: ValueKey(style.coverKey),
                  document: CapturedDocument(
                    id: style.coverKey!,
                    key: style.coverKey!,
                  ),
                  capture: capture,
                ),
              ),
            Container(
              color: _stone,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  if (style.tagline != null)
                    Text(
                      style.tagline!,
                      key: const Key('preview-tagline'),
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: style.accent ?? _ink,
                      ),
                    ),
                  if (hours != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_outlined,
                          size: 12,
                          color: _mist,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            hours,
                            style: const TextStyle(fontSize: 11, color: _mist),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (openNow != null) ...[
                    const SizedBox(height: 5),
                    OpenBadge(open: openNow!, key: const Key('preview-open')),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.tr('Écrire sur WhatsApp'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.all(10), child: shelf),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour, required this.selected, this.onTap});

  final Color? colour;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: colour == null
          ? context.tr('Couleur par défaut')
          : 'Couleur ${StorefrontStyle.hexOf(colour!)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colour ?? const Color(0xFF1F1F1F),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: colour == null
              ? const Icon(Icons.close, size: 16, color: Colors.white)
              : (selected
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : null),
        ),
      ),
    );
  }
}

class _CoverChoice extends StatelessWidget {
  const _CoverChoice({required this.selected, required this.child, this.onTap});

  final bool selected;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _Thumb extends StatefulWidget {
  const _Thumb({super.key, required this.document, required this.capture});

  final CapturedDocument document;
  final CaptureRepository? capture;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final Future<Uint8List>? _bytes = widget.capture?.objectBytes(
    widget.document.key,
  );

  @override
  Widget build(BuildContext context) {
    final future = _bytes;
    if (future == null) return const Icon(Icons.image_outlined);
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: Icon(Icons.image_outlined));
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          semanticLabel: widget.document.caption ?? context.tr('Photo'),
        );
      },
    );
  }
}

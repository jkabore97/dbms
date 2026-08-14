import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/theme/kaj_theme.dart';

/// Choosing the colours everybody in this business will see.
///
/// The design decision worth naming is that this previews rather than
/// describes. A list of colour names — "Océan", "Prune" — asks somebody to
/// imagine what their app will look like, and people choose badly from
/// imagination: they pick the prettiest swatch and then discover their own
/// home screen is unreadable in the sun. So every option here is drawn as a
/// small, real home screen — app bar, hero card with a figure on it, tinted
/// tiles — in that palette. What you tap is what you get.
///
/// There is no custom colour picker, and that is deliberate rather than
/// unfinished. Every palette in this list is measured against WCAG contrast
/// in `theme_render_test.dart`; a free colour wheel would let an owner pick
/// pale yellow text on white and make their own books unreadable, and they
/// would not find out until somebody tried to count money in daylight. The
/// choice offered is real, and every branch of it is legible.
class OrgColoursScreen extends StatefulWidget {
  const OrgColoursScreen({
    super.key,
    required this.admin,
    required this.orgId,
    required this.profile,
    this.current,
    this.onSaved,
  });

  final AdminRepository admin;
  final String orgId;

  /// What this business would look like if it never chose: the default option
  /// is drawn in the profile's own palette rather than a grey placeholder.
  final String profile;

  /// The palette already chosen, or null for the profile's own.
  final String? current;

  /// Lets whoever opened this refresh the org list — the colour is carried by
  /// `my_orgs()`, so the app bar and every home screen repaint from there.
  final VoidCallback? onSaved;

  @override
  State<OrgColoursScreen> createState() => _OrgColoursScreenState();
}

class _OrgColoursScreenState extends State<OrgColoursScreen> {
  /// The name being previewed. Null is "the profile's own colour", which is a
  /// real choice here and not merely the absence of one.
  String? _selected;

  /// What was last saved, so the screen can tell a pending change from a
  /// settled one without asking the server again.
  String? _saved;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _saved = widget.current;
  }

  bool get _dirty => _selected != _saved;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.admin.setOrgTheme(orgId: widget.orgId, theme: _selected);
      widget.onSaved?.call();
      if (!mounted) return;
      setState(() {
        _saved = _selected;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couleurs enregistrées')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The whole screen sits in the palette being previewed, so the app bar and
    // the buttons move with the choice too — the preview cards alone would
    // show a colour while the frame around them said something else.
    final previewed = paletteFor(widget.profile, theme: _selected);

    return Theme(
      data: kajTheme(previewed),
      child: Builder(builder: (context) {
        final previewTheme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Couleurs')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(
                'Ces couleurs sont celles de votre activité : toute votre '
                'équipe les verra.',
                style: previewTheme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // The default first, because it is what the business already
              // looks like and the most likely thing somebody wants back.
              _PaletteCard(
                palette: paletteFor(widget.profile),
                title: 'Couleur par défaut',
                subtitle: _profileLabel(widget.profile),
                selected: _selected == null,
                onTap: _saving ? null : () => setState(() => _selected = null),
              ),
              const SizedBox(height: 20),
              Text('Autres couleurs',
                  style: previewTheme.textTheme.titleSmall),
              const SizedBox(height: 12),

              for (final palette in allPalettes) ...[
                _PaletteCard(
                  palette: palette,
                  title: palette.label,
                  selected: _selected == palette.name,
                  onTap: _saving
                      ? null
                      : () => setState(() => _selected = palette.name),
                ),
                const SizedBox(height: 12),
              ],

              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style:
                        TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ],
          ),

          // Anchored rather than at the bottom of a long scroll: the list is
          // taller than a phone, and a save button below eight preview cards
          // is a save button nobody finds.
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: (!_dirty || _saving) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _dirty ? 'Enregistrer' : 'Enregistré',
                        style: const TextStyle(fontSize: 17),
                      ),
              ),
            ),
          ),
        );
      }),
    );
  }

  static String _profileLabel(String profile) => switch (profile) {
        'farm' => 'La couleur des fermes',
        'church' => 'La couleur des églises',
        'retail' => 'La couleur des boutiques',
        _ => "La couleur de l'application",
      };
}

/// One choosable palette, drawn as the thing it actually produces.
class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
    required this.palette,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final KajPalette palette;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              // The selected card is bordered in its own ink, not in the
              // app's accent: two different colours saying "this one" is how
              // a picker ends up looking broken.
              color: selected ? palette.ink : theme.colorScheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MiniHome(palette: palette),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: palette.ink)
                    else
                      Icon(Icons.circle_outlined,
                          color: theme.colorScheme.outlineVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A home screen at a glance: the gradient with a figure on it, and a row of
/// tinted tiles. Small enough that eight of them fit in a scroll, faithful
/// enough that what somebody picks is what they get.
class _MiniHome extends StatelessWidget {
  const _MiniHome({required this.palette});

  final KajPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      decoration: BoxDecoration(gradient: kajGradient(palette)),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stands in for the app bar title and the day's figure — the two
          // places the ink has to be read against the wash.
          Text(
            "Aujourd'hui",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '12 500 F',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: palette.ink,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    // Exactly how a tile paints its chip: the tint at low
                    // opacity, with the icon in the tint itself.
                    color: palette.tint(i).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.circle,
                      size: 12, color: palette.tint(i)),
                ),
                if (i < 4) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

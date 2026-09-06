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
import '../account/pro_sheet.dart';

/// The Pro dressing of the vitrine (068), under the vitrine switch on the
/// business settings: a cover from the shop's own photographs, a tagline,
/// opening hours, the buttons' colour, up to six pinned articles and the
/// out-of-stock switch. On a Free business it is drawn with the badge and
/// opens the door to pay; the server refuses it regardless of the drawing.
class VitrinePlusCard extends StatefulWidget {
  const VitrinePlusCard({
    super.key,
    required this.orgId,
    required this.admin,
    this.retail,
    this.capture,
  });

  final String orgId;
  final AdminRepository admin;

  /// For the pinned-article picker; null in a build with no server.
  final RetailRepository? retail;

  /// For the cover picker: the shop's own photographs.
  final CaptureRepository? capture;

  @override
  State<VitrinePlusCard> createState() => _VitrinePlusCardState();
}

class _VitrinePlusCardState extends State<VitrinePlusCard> {
  /// The palette a shop may pick its button colour from: six that read on
  /// the street's paper, chosen once so no vitrine ends up unreadable.
  static const accents = <Color>[
    Color(0xFFB1541A),
    Color(0xFF2E7D5B),
    Color(0xFF1F5FA8),
    Color(0xFF8E3B6B),
    Color(0xFFB8860B),
    Color(0xFF444444),
  ];

  final _tagline = TextEditingController();
  final _hours = TextEditingController();
  Color? _accent;
  String? _coverKey;
  List<String> _pinned = const [];
  bool _hideOut = false;

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
    _hours.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final style = await widget.admin.storefrontStyle(widget.orgId);
      var photos = const <CapturedDocument>[];
      var products = const <Product>[];
      try {
        photos = await widget.capture?.documents(widget.orgId, limit: 40) ??
            const [];
      } catch (_) {}
      try {
        products = await widget.retail?.products(widget.orgId) ?? const [];
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _tagline.text = style.tagline ?? '';
        _hours.text = style.hours ?? '';
        _accent = style.accent;
        _coverKey = style.coverKey;
        _pinned = style.pinned;
        _hideOut = style.hideOutOfStock;
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

  StorefrontStyle get _style => StorefrontStyle(
        tagline: _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
        hours: _hours.text.trim().isEmpty ? null : _hours.text.trim(),
        accent: _accent,
        coverKey: _coverKey,
        pinned: _pinned,
        hideOutOfStock: _hideOut,
      );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.admin.setStorefrontStyle(widget.orgId, _style);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Vitrine enregistrée. Ouvrez-la pour voir le résultat.';
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AppScope.maybeOf(context);
    final locked = scope?.session
            .accessFor(widget.orgId)
            .isProLocked('vitrine_plus') ??
        false;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Vitrine personnalisée', style: theme.textTheme.titleSmall),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('Pro',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Une photo de couverture, une phrase, vos horaires, la couleur '
          'de vos boutons et jusqu\'à six articles en tête de la vitrine.',
          style: muted,
        ),
        const SizedBox(height: 10),
        if (locked)
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Réservé à Kaj Pro'),
              subtitle: const Text(
                  'Passez à Kaj Pro pour habiller votre vitrine.'),
              trailing: FilledButton.tonal(
                onPressed: _openPro,
                child: const Text('Voir'),
              ),
            ),
          )
        else if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else ...[
          TextField(
            controller: _tagline,
            enabled: !_saving,
            maxLength: 80,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Phrase d\'accroche',
              hintText: 'Pagnes et gâteaux depuis 1998',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hours,
            enabled: !_saving,
            maxLength: 120,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Horaires',
              hintText: 'Lun–Sam 8h–19h',
            ),
          ),
          const SizedBox(height: 6),
          Text('Couleur des boutons', style: theme.textTheme.labelLarge),
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
          Text('Photo de couverture', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (_photos.isEmpty)
            Text(
              'Prenez d\'abord une photo de votre devanture dans Photos ; '
              'elle apparaîtra ici.',
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
                    child: const Center(child: Text('Aucune')),
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
          Text('Articles en tête (${_pinned.length}/6)',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (_products.isEmpty)
            Text('Mettez d\'abord des articles sur la vitrine.', style: muted)
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
                                _pinned =
                                    _pinned.where((id) => id != p.id).toList();
                              }
                            }),
                  ),
              ],
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hideOut,
            onChanged: _saving ? null : (v) => setState(() => _hideOut = v),
            title: const Text('Ne pas afficher les articles épuisés'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 4),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.storefront_outlined),
              label: const Text('Enregistrer la vitrine'),
            ),
          ),
        ],
      ],
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
          ? 'Couleur par défaut'
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
  const _CoverChoice(
      {required this.selected, required this.child, this.onTap});

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
  const _Thumb({required this.document, required this.capture});

  final CapturedDocument document;
  final CaptureRepository? capture;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  late final Future<Uint8List>? _bytes =
      widget.capture?.objectBytes(widget.document.key);

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
        return Image.memory(bytes,
            fit: BoxFit.cover,
            semanticLabel: widget.document.caption ?? 'Photo');
      },
    );
  }
}

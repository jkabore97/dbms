import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';

import '../../core/admin/admin_repository.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// Making a new business — the one screen only Kaj-consulting sees.
///
/// Every other org in the app arrives by invitation. This is where the first
/// one comes from, and it is reachable only for a profile carrying
/// `is_platform_admin`. The flag is checked again inside `create_org`, so
/// reaching this screen by any other route still fails at the server.
///
/// The profile choice is the consequential field and cannot be changed
/// afterwards from a phone — it decides which home screen every member of the
/// business lands on, and `org_settings_screen.dart` deliberately omits it. So
/// it is a visible list of options here rather than a dropdown default nobody
/// reads.
///
/// Everybody else creates their own business in CreateMyBusinessScreen
/// (111), which reaches the same server path (org_create_core).
class CreateBusinessScreen extends StatefulWidget {
  const CreateBusinessScreen({super.key, required this.admin});

  final AdminRepository admin;

  /// Lowercases, strips accents, and hyphenates — the name as typed turned
  /// into something that can live in a hostname.
  ///
  /// Kept static and pure so the rules are testable without a server: this
  /// becomes a live subdomain, and "Église d'Israël" has to survive the trip.
  static String slugify(String name) {
    const accents = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
    const plain = 'aaaaaaceeeeiiiinooooouuuuyy';

    final buffer = StringBuffer();
    for (final rune in name.toLowerCase().trim().runes) {
      final ch = String.fromCharCode(rune);
      final i = accents.indexOf(ch);
      buffer.write(i >= 0 ? plain[i] : ch);
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Null when the slug is usable, otherwise why it is not.
  static String? slugProblem(String slug) {
    if (slug.length < 3) return 'Au moins 3 caractères.';
    if (slug.length > 40) return 'Au plus 40 caractères.';
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      return 'Lettres sans accent, chiffres et tirets uniquement.';
    }
    if (slug.startsWith('-') || slug.endsWith('-')) {
      return 'Ne peut pas commencer ni finir par un tiret.';
    }
    return null;
  }

  @override
  State<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

/// The profiles a business can be created as — each one the app has a real
/// home screen for. 'generic' ("Autre") is deliberately absent: it made an
/// empty business with no dedicated module, which was more confusing than
/// useful to offer. Existing generic businesses keep working (the server still
/// accepts the value and their home screen still renders); it is simply no
/// longer something new businesses are created as.
const _profiles =
    <({String value, String label, String detail, IconData icon})>[
  (
    value: 'association',
    label: 'Association',
    detail: 'Membres, cotisations, dépenses, résumé',
    icon: Icons.groups_outlined,
  ),
  (
    value: 'farm',
    label: 'Ferme',
    detail: 'Stock, troupeaux, production, factures',
    icon: Icons.agriculture_outlined,
  ),
  (
    value: 'retail',
    label: 'Commerce',
    detail: 'Ventes et dépenses',
    icon: Icons.storefront_outlined,
  ),
];

class _CreateBusinessScreenState extends State<CreateBusinessScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _currencyController = TextEditingController(text: 'XOF');

  String _profile = 'association';

  /// True once the slug has been edited by hand, after which typing the name
  /// stops overwriting it — otherwise a deliberate slug is silently undone by
  /// the next keystroke in the field above.
  bool _slugTouched = false;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _slugController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!_slugTouched) {
      _slugController.text = CreateBusinessScreen.slugify(_nameController.text);
    }
    // Rebuilds so the Create button follows what has been typed. The button is
    // a pure function of the fields; without this it never wakes up.
    setState(() {});
  }

  String get _name => _nameController.text.trim();
  String get _slug => _slugController.text.trim();
  String get _currency => _currencyController.text.trim().toUpperCase();

  bool get _ready =>
      _name.isNotEmpty &&
      CreateBusinessScreen.slugProblem(_slug) == null &&
      _currency.length == 3;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final orgId = await widget.admin.createOrg(
        name: _name,
        slug: _slug,
        profile: _profile,
        currency: _currency,
      );
      if (mounted) Navigator.of(context).pop(orgId);
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The two failures worth naming. A duplicate slug is the one a person can
  /// actually fix, and the raw Postgres text for it names a constraint rather
  /// than the field they typed in.
  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('orgs_slug_key') || text.contains('duplicate key')) {
      return context.tr('L\'adresse « {_slug} » est déjà utilisée par une autre activité.', {'_slug': _slug});
    }
    if (text.contains('Only a platform admin')) {
      return context.tr('Ce compte n\'a pas le droit de créer une activité.');
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slugProblem =
        _slug.isEmpty ? null : CreateBusinessScreen.slugProblem(_slug);

    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Nouvelle activité'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _nameController,
              enabled: !_busy,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('Nom de l\'activité'),
                hintText: context.tr('Ex. : Association Bethel, Café Lumière, Green Market'),
                hintMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _slugController,
              enabled: !_busy,
              onChanged: (_) => setState(() => _slugTouched = true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
              ],
              decoration: InputDecoration(
                labelText: context.tr('Adresse'),
                helperText: slugProblem == null ? 'marakaj.com/s/$_slug' : null,
                errorText: slugProblem,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            Text(context.tr('Type'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // Cards rather than a radio group: four options each needing a
            // line of explanation do not fit a SegmentedButton, and this is
            // the choice that cannot be undone from a phone afterwards.
            ..._profiles.map((p) {
              final selected = p.value == _profile;
              return KajCard(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: Icon(p.icon, color: theme.colorScheme.primary),
                  title: Text(p.label),
                  subtitle: Text(p.detail, style: theme.textTheme.bodySmall),
                  trailing: selected
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary)
                      : null,
                  onTap:
                      _busy ? null : () => setState(() => _profile = p.value),
                ),
              );
            }),
            const SizedBox(height: 8),

            SizedBox(
              width: 160,
              child: TextField(
                controller: _currencyController,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(3),
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr('Monnaie'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _ready && !_busy ? _create : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        context.tr('Créer l\'activité'),
                        style: const TextStyle(fontSize: 17),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('Vous en serez le propriétaire. Un plan comptable de départ est créé automatiquement.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

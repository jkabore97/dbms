import 'package:flutter/material.dart';

import '../../../core/console/command_center.dart';
import '../../../core/console/fiche_repository.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/theme/mara_mark.dart';
import '../create_business_screen.dart';
import 'fiche_widgets.dart';

/// Identité: the business's name, kind, address (its vitrine's link),
/// money, phone and street address, and — for an association — Mara's
/// verification (088). Changed by the platform only (106's
/// platform_update_org_identity); each save is one journal line with its
/// « Annuler », and the owner is told « Mara a modifié … ». The kind moves
/// every member to another home: it changes only with the business's name
/// typed back.
class FicheIdentityTab extends StatefulWidget {
  const FicheIdentityTab({
    super.key,
    required this.overview,
    required this.fiche,
    required this.center,
    required this.onChanged,
  });

  final OrgOverview overview;
  final FicheRepository fiche;
  final CommandCenterRepository center;
  final VoidCallback onChanged;

  static const currencies = ['XOF', 'XAF', 'EUR', 'USD', 'GHS', 'NGN'];

  @override
  State<FicheIdentityTab> createState() => _FicheIdentityTabState();
}

class _FicheIdentityTabState extends State<FicheIdentityTab> {
  late final _name = TextEditingController(text: widget.overview.name);
  late final _slug = TextEditingController(text: widget.overview.slug);
  late final _phone = TextEditingController(text: widget.overview.phone ?? '');
  late final _address = TextEditingController(text: widget.overview.address ?? '');
  late String _kind = _kindOf(widget.overview.profile);
  late String _currency = widget.overview.currency;
  late bool _verified = widget.overview.verifiedAt != null;
  bool _saving = false;
  String? _error;

  static String _kindOf(String profile) =>
      profile == 'church' ? 'association' : profile;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _slug, _phone, _address]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _slug, _phone, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  OrgOverview get _o => widget.overview;

  bool get _kindChanged => _kind != _kindOf(_o.profile);

  String? get _slugProblem {
    final s = _slug.text.trim();
    if (s == _o.slug) return null;
    return CreateBusinessScreen.slugProblem(s);
  }

  bool get _dirty =>
      _name.text.trim() != _o.name ||
      _slug.text.trim() != _o.slug ||
      _kindChanged ||
      _currency != _o.currency ||
      _phone.text.trim() != (_o.phone ?? '') ||
      _address.text.trim() != (_o.address ?? '') ||
      (_o.isAssociation && _verified != (_o.verifiedAt != null));

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = context.tr('Le nom de l\'activité ne peut pas être vide.'));
      return;
    }
    String? confirm;
    if (_kindChanged) {
      confirm = await showDialog<String>(
        context: context,
        builder: (_) => _TypeTheName(name: _o.name),
      );
      if (confirm == null || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? changed(String now, String? was) => now == (was ?? '') ? null : now;
      final id = await widget.fiche.updateIdentity(
        _o.id,
        name: changed(_name.text.trim(), _o.name),
        slug: changed(_slug.text.trim().toLowerCase(), _o.slug),
        profile: _kindChanged ? _kind : null,
        currency: changed(_currency, _o.currency),
        phone: changed(_phone.text.trim(), _o.phone),
        address: changed(_address.text.trim(), _o.address),
        verified: _o.isAssociation && _verified != (_o.verifiedAt != null) ? _verified : null,
        confirm: confirm,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      final who = _o.owner?.name;
      showUndoBar(
        context,
        center: widget.center,
        actionId: id,
        done: who == null
            ? context.tr('Identité enregistrée.')
            : context.tr('Identité enregistrée. {who} est prévenu(e).', {'who': who}),
        onUndone: widget.onChanged,
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    InputDecoration field(String label, {String? helper, String? error, String? prefix}) =>
        InputDecoration(
          labelText: label,
          helperText: helper,
          errorText: error,
          prefixText: prefix,
          border: const OutlineInputBorder(),
        );
    final currencies = {...FicheIdentityTab.currencies, _o.currency}.toList();
    // On a phone the three kinds keep their words, not their pictures.
    final icons = MediaQuery.sizeOf(context).width >= 520;
    return ListView(
      key: const Key('fiche-identity'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        FicheWidth(
          max: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MaraAsBanner(
                title: context.tr('Vous modifiez l\'identité de {name} en tant que Mara',
                    {'name': _o.name}),
                line: context.tr('Le propriétaire est prévenu. Chaque changement va au journal, avec « Annuler ».'),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('identity-name'),
                controller: _name,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                decoration: field(context.tr('Nom')),
              ),
              const SizedBox(height: 16),
              Text(context.tr('Type d\'activité'), style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                key: const Key('identity-kind'),
                segments: [
                  ButtonSegment(
                      value: 'retail',
                      icon: icons ? const Icon(Icons.storefront_outlined) : null,
                      label: Text(context.tr('Boutique'))),
                  ButtonSegment(
                      value: 'farm',
                      icon: icons ? const Icon(Icons.agriculture_outlined) : null,
                      label: Text(context.tr('Ferme'))),
                  ButtonSegment(
                      value: 'association',
                      icon: icons ? const Icon(Icons.groups_outlined) : null,
                      label: Text(context.tr('Association'))),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged:
                    _saving ? null : (s) => setState(() => _kind = s.first),
              ),
              if (_kindChanged) ...[
                const SizedBox(height: 8),
                Row(
                  key: const Key('identity-kind-warning'),
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFA96A0B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.tr('Chaque membre ouvrira un autre accueil. Il faudra taper le nom de l\'activité pour confirmer.'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const Key('identity-slug'),
                controller: _slug,
                enabled: !_saving,
                decoration: field(
                  context.tr('Adresse web'),
                  prefix: 'marakaj.com/s/',
                  helper: _slugProblem == null && _slug.text.trim() != _o.slug
                      ? context.tr('L\'ancien lien de la vitrine ne marchera plus.')
                      : null,
                  error: _slugProblem == null ? null : context.tr(_slugProblem!),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('identity-currency'),
                initialValue: _currency,
                decoration: field(context.tr('Monnaie')),
                items: [
                  for (final c in currencies) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: _saving ? null : (v) => setState(() => _currency = v ?? _currency),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('identity-phone'),
                controller: _phone,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                decoration: field(context.tr('Téléphone'),
                    helper: context.tr('Sur la vitrine et les factures.')),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('identity-address'),
                controller: _address,
                enabled: !_saving,
                decoration: field(context.tr('Adresse'),
                    helper: context.tr('Sur la vitrine et les factures.')),
              ),
              if (_o.isAssociation) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('identity-verified'),
                  contentPadding: EdgeInsets.zero,
                  value: _verified,
                  onChanged: _saving ? null : (v) => setState(() => _verified = v),
                  secondary: const Icon(Icons.verified_user_outlined, color: maraBrown),
                  title: Text(context.tr('Vérifiée par Mara')),
                  subtitle: Text(context.tr('Le sceau de confiance de l\'association, sur sa vitrine.')),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('identity-save'),
                  onPressed: _saving || !_dirty || _slugProblem != null ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(context.tr('Enregistrer'), style: const TextStyle(fontSize: 17)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The kind changes only with the name typed back — read, then typed.
class _TypeTheName extends StatefulWidget {
  const _TypeTheName({required this.name});

  final String name;

  @override
  State<_TypeTheName> createState() => _TypeTheNameState();
}

class _TypeTheNameState extends State<_TypeTheName> {
  final _typed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _matches =>
      _typed.text.trim().toLowerCase() == widget.name.trim().toLowerCase();

  @override
  Widget build(BuildContext context) => AlertDialog(
    // The keyboard up on a small phone: the dialog scrolls (A6).
    scrollable: true,
        title: Text(context.tr('Changer le type d\'activité ?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Chaque membre ouvrira un autre accueil dès demain matin. Tapez « {name} » pour confirmer.',
                {'name': widget.name})),
            const SizedBox(height: 12),
            TextField(
              key: const Key('identity-confirm-name'),
              controller: _typed,
              autofocus: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: widget.name,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            key: const Key('identity-confirm-go'),
            onPressed: _matches ? () => Navigator.of(context).pop(_typed.text) : null,
            child: Text(context.tr('Changer le type')),
          ),
        ],
      );
}

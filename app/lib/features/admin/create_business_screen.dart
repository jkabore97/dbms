import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart' show describeError;
import '../../core/terms/terms.dart';
import '../account/terms_gate.dart' show SellerCommitmentsCard;
import '../../core/format/currencies.dart';
import '../../core/nav/app_scope.dart';
import '../../core/onboarding/business_creation.dart' show currencyOfCountry, townCountry;
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import 'package:kaj_app/core/nav/parent_route.dart';

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
  const CreateBusinessScreen({super.key, required this.admin, this.terms});

  final AdminRepository admin;

  /// The seller's commitments (142): the app's unless a test gives one.
  final TermsController? terms;

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
    if (slug.length < 3) return translate(trCurrent, 'Au moins 3 caractères.');
    if (slug.length > 40) return translate(trCurrent, 'Au plus 40 caractères.');
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      return translate(trCurrent, 'Lettres sans accent, chiffres et tirets uniquement.');
    }
    if (slug.startsWith('-') || slug.endsWith('-')) {
      return translate(trCurrent, 'Ne peut pas commencer ni finir par un tiret.');
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

  /// The money picked by hand (144); null follows [_countryCurrency].
  String? _pickedCurrency;

  /// The money of the country this is created from — the platform admin's
  /// own phone's (or the device's region): a business starts in its
  /// country's money, never in francs CFA by accident. Read once.
  String? _countryCurrency;

  String _profile = 'association';

  /// True once the slug has been edited by hand, after which typing the name
  /// stops overwriting it — otherwise a deliberate slug is silently undone by
  /// the next keystroke in the field above.
  bool _slugTouched = false;

  bool _busy = false;
  String? _error;

  /// « J'accepte les engagements du vendeur » (142): the platform admin who
  /// creates a business here is its owner, and create_org asks them too.
  bool _seller = false;

  bool get _asksSeller =>
      (widget.terms ?? TermsScope.maybeOf(context))?.needs(TermsDoc.seller) ?? false;

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
  String get _currency => _pickedCurrency ?? _countryCurrency ?? 'XOF';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _countryCurrency ??= currencyOfCountry(
        townCountry(AppScope.read(context)?.session.identity?.phone));
  }

  bool get _ready =>
      _name.isNotEmpty &&
      CreateBusinessScreen.slugProblem(_slug) == null &&
      _currency.length == 3 &&
      (!_asksSeller || _seller);

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_asksSeller) {
        await (widget.terms ?? TermsScope.read(context))?.accept(const [TermsDoc.seller]);
      }
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
    // Anything else in the person's words, never PostgREST's raw text
    // (147: the seller's commitments refused, said and translated).
    return describeError(error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slugProblem =
        _slug.isEmpty ? null : CreateBusinessScreen.slugProblem(_slug);

    return Scaffold(
      appBar: AppBar(
          // Opened with `go` too: back to its parent (132).
          leading: parentBack(context),
          actions: const [bellRoom],
          title: Text(context.tr('Nouvelle activité'))),
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
                  title: Text(context.tr(p.label)),
                  subtitle: Text(context.tr(p.detail), style: theme.textTheme.bodySmall),
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

            // The same picker as « Créer mon activité » and the settings
            // (144): every money by name, the country's first.
            DropdownButtonFormField<String>(
              key: const Key('create-business-currency'),
              initialValue: _currency,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.tr('Monnaie'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in currencyChoices(_currency))
                  DropdownMenuItem(
                      value: c,
                      child: Text('$c — ${currencyName(c, context.trLanguage)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _busy ? null : (c) => setState(() => _pickedCurrency = c),
            ),

            if (_asksSeller) ...[
              const SizedBox(height: 20),
              SellerCommitmentsCard(
                checked: _seller,
                onChanged: _busy ? null : (v) => setState(() => _seller = v),
              ),
            ],

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

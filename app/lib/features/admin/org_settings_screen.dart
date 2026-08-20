import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/rates/currency_rates.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/nav/router.dart';

/// The business's own details.
///
/// Only two fields are editable, and the ones that are missing matter more
/// than the ones that are here:
///
///  * `slug` is a live subdomain. Changing it breaks every link anyone has.
///  * `profile` decides which home screen every member of the org opens on.
///    Changing it from a settings form would move a whole congregation to a
///    farm screen because somebody was curious.
///
/// Both are shown, read-only, so an admin can see what they are and quote them
/// when asking for a change.
class OrgSettingsScreen extends StatefulWidget {
  const OrgSettingsScreen({
    super.key,
    required this.admin,
    required this.orgId,
    this.onSaved,
    this.canSuspend = false,
    this.suspended = false,
  });

  final AdminRepository admin;
  final String orgId;

  /// Lets whoever opened this refresh the org list — the name shown in the app
  /// bar and the picker comes from `my_orgs()`, not from this screen.
  final VoidCallback? onSaved;

  /// Whether to show the platform's freeze control (049). True only for a
  /// platform admin; the server refuses `set_org_suspended` to anyone else
  /// regardless of what the client draws.
  final bool canSuspend;

  /// Whether this business is currently frozen, as the org list last reported.
  final bool suspended;

  @override
  State<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends State<OrgSettingsScreen> {
  final _nameController = TextEditingController();
  final _waveController = TextEditingController();

  String _currency = 'XOF';
  List<CurrencyRate> _rates = const [];
  String _slug = '';
  String _profile = '';
  String? _theme;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  late bool _suspended = widget.suspended;
  bool _togglingSuspend = false;

  static const _currencies = ['XOF', 'XAF', 'EUR', 'USD', 'GHS', 'NGN'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final org = await widget.admin.fetchOrg(widget.orgId);
      final wave = await widget.admin.waveMerchant(widget.orgId);
      final rates = await widget.admin.currencyRates(widget.orgId);
      if (!mounted) return;
      setState(() {
        _nameController.text = (org['name'] as String?) ?? '';
        _waveController.text = wave ?? '';
        _rates = rates;
        final currency = (org['default_currency'] as String?) ?? 'XOF';
        _currency = _currencies.contains(currency) ? currency : 'XOF';
        _slug = (org['slug'] as String?) ?? '';
        _profile = (org['profile'] as String?) ?? 'generic';
        _theme = org['theme'] as String?;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = "Le nom de l'activité ne peut pas être vide.");
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.admin.updateOrg(
        orgId: widget.orgId,
        name: name,
        currency: _currency,
      );
      final wave = _waveController.text.trim();
      await widget.admin.setWaveMerchant(widget.orgId, wave.isEmpty ? null : wave);
      widget.onSaved?.call();
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enregistré')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _saving = false;
      });
    }
  }

  /// Add a currency, or (with [existing]) change its rate. Each is one
  /// immediate write and a reload, so the list always agrees with the server.
  Future<void> _editRate([CurrencyRate? existing]) async {
    final result = await showDialog<(String, double)>(
      context: context,
      builder: (_) => RateDialog(
        homeCurrency: _currency,
        taken: [for (final r in _rates) r.currency],
        existing: existing,
      ),
    );
    if (result == null) return;
    try {
      await widget.admin.setCurrencyRate(widget.orgId, result.$1, result.$2);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AuthRepository.describeError(error))));
      }
    }
  }

  Future<void> _removeRate(CurrencyRate rate) async {
    try {
      await widget.admin.removeCurrencyRate(widget.orgId, rate.currency);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AuthRepository.describeError(error))));
      }
    }
  }

  /// Freeze the business, or thaw it. Suspending is guarded by a confirmation
  /// because it stops a real shop trading; lifting it is not. Either way the
  /// org list is refreshed so the read-only banner appears or clears at once.
  Future<void> _toggleSuspend() async {
    final freezing = !_suspended;
    if (freezing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Suspendre cette entreprise ?'),
          content: const Text(
            'Ses membres pourront encore tout consulter, mais ne pourront '
            'plus rien enregistrer — ni vente, ni dépense, ni stock — '
            "jusqu'à la réactivation. Les données ne sont pas supprimées.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Suspendre'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _togglingSuspend = true;
      _error = null;
    });
    try {
      await widget.admin.setOrgSuspended(widget.orgId, freezing);
      // The banner in the shell reads `org.suspended`, which comes from the
      // cached org list — refresh it so the freeze takes visible effect now.
      widget.onSaved?.call();
      if (!mounted) return;
      setState(() {
        _suspended = freezing;
        _togglingSuspend = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(freezing
              ? 'Entreprise suspendue'
              : 'Entreprise réactivée'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _togglingSuspend = false;
      });
    }
  }

  Future<void> _openColours() async {
    await context.push(
        Routes.inside(widget.orgId, 'administration/parametres/couleurs'));
    // Re-read rather than trusting what was passed back: the colour screen
    // saves on its own, and this row has to agree with the server whether it
    // saved once, three times, or not at all.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Paramètres de l'activité")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Nom', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Monnaie', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged:
                      _saving ? null : (v) => setState(() => _currency = v!),
                ),
                const SizedBox(height: 24),
                Text('Paiement Wave', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _waveController,
                  enabled: !_saving,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '+226 70 00 00 00',
                    prefixIcon: Icon(Icons.qr_code_2),
                    helperText: 'Le numéro Wave du commerce. Laissez vide pour '
                        'ne pas proposer Wave à la vente.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 24),
                Text('Taux de change', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'Pour encaisser une vente dans une autre monnaie. Les '
                  'livres restent en ${_currency == 'XOF' ? 'FCFA' : _currency}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                for (final r in _rates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.currency_exchange),
                    title: Text(rateLabel(r.currency, r.rate, _currency)),
                    subtitle: Text(knownCurrencies[r.currency] ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Retirer',
                      onPressed: _saving ? null : () => _removeRate(r),
                    ),
                    onTap: _saving ? null : () => _editRate(r),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _editRate(),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une monnaie'),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Couleurs', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                _ColourRow(
                  palette: paletteFor(_profile, theme: _theme),
                  label: paletteNamed(_theme)?.label ?? 'Couleur par défaut',
                  onTap: _saving ? null : _openColours,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Enregistrer',
                            style: TextStyle(fontSize: 17),
                          ),
                  ),
                ),
                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Non modifiable ici',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  "L'adresse web et le type d'activité changent ce que voient "
                  'tous les membres. Contactez Kaj-consulting pour les '
                  'modifier.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _ReadOnlyRow(label: 'Adresse web', value: '$_slug.kajapp.com'),
                _ReadOnlyRow(label: "Type d'activité", value: _profile),
                if (widget.canSuspend) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text('Modération de la plateforme',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    _suspended
                        ? 'Cette entreprise est suspendue : ses membres peuvent '
                            'consulter mais rien enregistrer. Réactivez-la pour '
                            'rétablir les opérations.'
                        : 'Suspendre gèle toutes les écritures sans rien '
                            'supprimer. À utiliser pour un impayé, un litige ou '
                            'un abus, le temps de le régler.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _togglingSuspend ? null : _toggleSuspend,
                      icon: _togglingSuspend
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(_suspended
                              ? Icons.lock_open_outlined
                              : Icons.lock_outline),
                      label: Text(
                        _suspended ? 'Réactiver' : 'Suspendre',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: _suspended
                          ? null
                          : OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                              side: BorderSide(color: theme.colorScheme.error),
                            ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The current palette, shown as itself rather than named.
///
/// A row reading "Océan" tells somebody nothing about what their staff are
/// looking at; a strip of the actual gradient does.
class _ColourRow extends StatelessWidget {
  const _ColourRow({
    required this.palette,
    required this.label,
    required this.onTap,
  });

  final KajPalette palette;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 40,
              decoration: BoxDecoration(
                gradient: kajGradient(palette),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(Icons.circle, size: 14, color: palette.ink),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// Adding or editing one exchange rate: pick the currency, type the rate the
/// business actually gets. Editing pins the currency and only the rate moves.
///
/// When a XOF business adds EUR, the field pre-fills the CFA franc's fixed
/// peg (655,957) — the one rate that is law rather than market. The owner may
/// still overwrite it with their bank's effective rate.
class RateDialog extends StatefulWidget {
  const RateDialog({
    super.key,
    required this.homeCurrency,
    required this.taken,
    this.existing,
  });

  final String homeCurrency;

  /// Currencies that already have a rate, kept out of the picker so the same
  /// code cannot be added twice.
  final List<String> taken;

  final CurrencyRate? existing;

  @override
  State<RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<RateDialog> {
  late final _rateController = TextEditingController(
      text: widget.existing == null ? '' : '${widget.existing!.rate}');
  late String? _code = widget.existing?.currency;

  List<String> get _choices => [
        for (final code in knownCurrencies.keys)
          if (code != widget.homeCurrency && !widget.taken.contains(code))
            code,
      ];

  double? get _rate =>
      double.tryParse(_rateController.text.trim().replaceAll(',', '.'));

  bool get _canSave => _code != null && (_rate ?? 0) > 0;

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  void _pick(String? code) {
    setState(() {
      _code = code;
      // The peg, offered not imposed: only into an empty field.
      if (code == 'EUR' &&
          widget.homeCurrency == 'XOF' &&
          _rateController.text.trim().isEmpty) {
        _rateController.text = '$eurXofPeg';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.homeCurrency == 'XOF' ? 'FCFA' : widget.homeCurrency;
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Ajouter une monnaie'
          : 'Modifier le taux'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.existing == null)
            DropdownButtonFormField<String>(
              initialValue: _code,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Monnaie',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final code in _choices)
                  DropdownMenuItem(
                    value: code,
                    child: Text('$code — ${knownCurrencies[code]}'),
                  ),
              ],
              onChanged: _pick,
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.existing!.currency} — '
                '${knownCurrencies[widget.existing!.currency] ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _rateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Taux',
              prefixText: _code == null ? null : '1 $_code = ',
              suffixText: home,
              helperText: _code == 'EUR' && widget.homeCurrency == 'XOF'
                  ? 'Taux fixe officiel : 655,957'
                  : 'Le taux que vous obtenez réellement.',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed:
              _canSave ? () => Navigator.of(context).pop((_code!, _rate!)) : null,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

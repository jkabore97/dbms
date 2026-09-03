import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/rates/currency_rates.dart';
import '../../core/storefront/storefront_repository.dart';
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

  bool _storefrontEnabled = false;
  final _blurbController = TextEditingController();

  /// Where the shop is on the vitrine map (053). Text, not doubles, so the
  /// field can be typed into, pasted from a Google Maps link, or filled from
  /// the phone's own position — and cleared to lift the pin.
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  bool _locating = false;

  /// The vitrine's address: on the web, this very site; elsewhere, the site
  /// the shop is known at. What the shop pastes into a WhatsApp status.
  String get _storefrontUrl {
    final origin = Uri.base.scheme.startsWith('http')
        ? Uri.base.origin
        : 'https://dbms.kabore-boss.workers.dev';
    return '$origin/s/$_slug';
  }

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
    _blurbController.dispose();
    _latController.dispose();
    _lngController.dispose();
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
      final storefront = await widget.admin.storefront(widget.orgId);
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
        _storefrontEnabled = storefront.enabled;
        _blurbController.text = storefront.blurb ?? '';
        _latController.text = storefront.lat?.toString() ?? '';
        _lngController.text = storefront.lng?.toString() ?? '';
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

    // The pin is both numbers or neither — half a position is no position,
    // and the database refuses it too (053).
    final latText = _latController.text.trim().replaceAll(',', '.');
    final lngText = _lngController.text.trim().replaceAll(',', '.');
    double? lat;
    double? lng;
    if (latText.isNotEmpty || lngText.isNotEmpty) {
      lat = double.tryParse(latText);
      lng = double.tryParse(lngText);
      if (lat == null ||
          lng == null ||
          lat < -90 ||
          lat > 90 ||
          lng < -180 ||
          lng > 180) {
        setState(() => _error =
            'Indiquez la latitude et la longitude, ou aucune des deux.');
        return;
      }
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
      await widget.admin.setStorefront(
        widget.orgId,
        enabled: _storefrontEnabled,
        blurb: _blurbController.text.trim(),
      );
      await widget.admin.setStorefrontLocation(widget.orgId, lat: lat, lng: lng);
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

  /// Fill the pin from where the phone is right now — the shopkeeper is
  /// standing in the shop, which is the one place the position is certain.
  /// Nothing is saved until "Enregistrer": the numbers can still be edited.
  Future<void> _useMyPosition() async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Sans autorisation, tapez la position ou collez '
              'un lien Google Maps.'),
        ));
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latController.text = position.latitude.toStringAsFixed(6);
        _lngController.text = position.longitude.toStringAsFixed(6);
      });
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Position introuvable. Vérifiez que le GPS est activé.'),
      ));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// A shop already on Google Maps pastes its own link; the numbers come
  /// out of it. Short links carry none, and the dialog says what to do then.
  Future<void> _pasteMapsLink() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lien Google Maps'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'https://www.google.com/maps/place/...@12.37,-1.52,17z',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Utiliser'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    final position = parseGoogleMapsLink(text);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ce lien ne contient pas de position. Ouvrez-le dans '
            "Google Maps et copiez l'adresse complète."),
      ));
      return;
    }
    setState(() {
      _latController.text = position.lat.toString();
      _lngController.text = position.lng.toString();
    });
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
                const SizedBox(height: 24),
                Text('Vitrine en ligne', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'Une page publique de la boutique, avec les articles que vous '
                  "choisissez d'afficher — photo et prix — à partager sur "
                  "WhatsApp. Rien ne s'y vend : le client vous contacte.",
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _storefrontEnabled,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _storefrontEnabled = v),
                  title: const Text('Ouvrir la vitrine'),
                ),
                if (_storefrontEnabled) ...[
                  TextField(
                    controller: _blurbController,
                    enabled: !_saving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Quelques mots sur la boutique (facultatif)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LinkRow(url: _storefrontUrl),
                  const SizedBox(height: 16),
                  Text('Position sur la carte',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    "Pour que les clients vous trouvent dans l'annuaire, "
                    '« près de moi » et sur la carte. Facultatif.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latController,
                          enabled: !_saving && !_locating,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Latitude',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _lngController,
                          enabled: !_saving && !_locating,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Longitude',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            (_saving || _locating) ? null : _useMyPosition,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('Utiliser ma position'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            (_saving || _locating) ? null : _pasteMapsLink,
                        icon: const Icon(Icons.link),
                        label: const Text('Coller un lien Google Maps'),
                      ),
                    ],
                  ),
                ],
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

/// The vitrine's address with a copy button — what the shop pastes into a
/// WhatsApp status. Selectable too, for the person who would rather long-press.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(url, style: theme.textTheme.bodySmall),
          ),
          IconButton(
            tooltip: 'Copier le lien',
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lien copié')),
                );
              }
            },
          ),
        ],
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

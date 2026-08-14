import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/phone/country_codes.dart';
import '../common/phone_field.dart';
import '../../core/errors.dart';

/// What goes at the top of every invoice this business issues.
///
/// `orgs` held a name and nothing else, which is enough to run the app and not
/// enough to send anybody a bill. An invoice without an address and a tax
/// number is not a document a customer's own accountant can file — in Burkina
/// Faso that number is the IFU — so the business either does not get paid or
/// writes the invoice again by hand, which is the thing this app exists to
/// stop.
///
/// Administrator only, and enforced by `set_org_billing()` rather than by
/// hiding this screen: what is written here is what the business claims about
/// itself to a customer and to a tax office, and that is not the vendeuse's to
/// change on a busy afternoon.
class BillingDetailsScreen extends StatefulWidget {
  const BillingDetailsScreen({
    super.key,
    required this.org,
    required this.invoicing,
  });

  final OrgSummary org;
  final InvoicingRepository invoicing;

  @override
  State<BillingDetailsScreen> createState() => _BillingDetailsScreenState();
}

class _BillingDetailsScreenState extends State<BillingDetailsScreen> {
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _taxId = TextEditingController();
  final _footer = TextEditingController();

  CountryCode _country = defaultCountry;

  /// IFU here, NIF in several neighbours, VAT number in Europe. Offered as a
  /// choice rather than hardcoded, because what the number is called is what
  /// gets printed and a wrong label on a right number still fails an audit.
  String _taxLabel = 'IFU';
  static const _taxLabels = ['IFU', 'RCCM', 'NIF', 'TVA', 'N° fiscal'];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_address, _phone, _email, _taxId, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final billing = await widget.invoicing.billingDetails(widget.org.id);
      if (!mounted) return;
      setState(() {
        _address.text = billing.address ?? '';
        _email.text = billing.email ?? '';
        _taxId.text = billing.taxId ?? '';
        _footer.text = billing.footer ?? '';
        final label = (billing.taxLabel ?? '').trim();
        if (label.isNotEmpty && _taxLabels.contains(label)) _taxLabel = label;

        // Stored as E.164; shown split, so the picker does not read as the
        // country code printed twice.
        final stored = countryOfNumber(billing.phone ?? '');
        if (stored != null) _country = stored;
        _phone.text = stored == null
            ? (billing.phone ?? '')
            : stored.localPart(billing.phone!);

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.invoicing.saveBillingDetails(
        orgId: widget.org.id,
        address: _address.text.trim(),
        phone: _phone.text.trim().isEmpty ? '' : _country.toE164(_phone.text),
        email: _email.text.trim(),
        taxId: _taxId.text.trim(),
        taxLabel: _taxId.text.trim().isEmpty ? '' : _taxLabel,
        footer: _footer.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
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

    return Scaffold(
      appBar: AppBar(title: const Text('En-tête de facture')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Text(
                  'Ces informations apparaissent en haut de chaque facture '
                  'que vous envoyez.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.org.name,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _address,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Adresse',
                    hintText: 'Rue 14.28, secteur 15, Ouagadougou',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                PhoneField(
                  controller: _phone,
                  country: _country,
                  onCountry: (c) => setState(() => _country = c),
                  labelText: 'Téléphone',
                  hintText: '70 12 34 56',
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail (facultatif)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Numéro fiscal', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  "Sans lui, votre client ne peut pas passer votre facture "
                  'dans ses propres comptes.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<String>(
                        initialValue: _taxLabel,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final label in _taxLabels)
                            DropdownMenuItem(value: label, child: Text(label)),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _taxLabel = v ?? _taxLabel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _taxId,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Numéro',
                          hintText: '00012345A',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _footer,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Bas de page',
                    helperText: 'Conditions de paiement, numéro Orange Money, '
                        'remerciements…',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!),
                  ),
                ],
              ],
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
    );
  }
}

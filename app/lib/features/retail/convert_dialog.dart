import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/rates/currency_rates.dart';
import '../../core/retail/retail_repository.dart';

/// "I paid for this in cedis — what did it cost in francs?"
///
/// The little converter behind the exchange icon on a cost field: pick the
/// currency the goods were actually bought in, type the amount, read the
/// home-currency figure, and both numbers are on screen before anything is
/// filled in. It returns the converted amount and nothing else — the books
/// only ever receive home currency, which is the whole design.
///
/// Loads the owner's rates itself so any cost field can offer it by holding a
/// repository and an org id. No rates set → a short explanation instead of a
/// broken form.
class CurrencyConvertDialog extends StatefulWidget {
  const CurrencyConvertDialog({
    super.key,
    required this.retail,
    required this.orgId,
    required this.homeCurrency,
  });

  final RetailRepository retail;
  final String orgId;
  final String homeCurrency;

  /// Opens the converter; resolves to the home-currency amount, or null when
  /// dismissed.
  static Future<double?> open(
    BuildContext context, {
    required RetailRepository retail,
    required String orgId,
    required String homeCurrency,
  }) {
    return showDialog<double>(
      context: context,
      builder: (_) => CurrencyConvertDialog(
        retail: retail,
        orgId: orgId,
        homeCurrency: homeCurrency,
      ),
    );
  }

  @override
  State<CurrencyConvertDialog> createState() => _CurrencyConvertDialogState();
}

class _CurrencyConvertDialogState extends State<CurrencyConvertDialog> {
  final _amountController = TextEditingController();
  bool _loading = true;
  List<CurrencyRate> _rates = const [];
  CurrencyRate? _picked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rates = await widget.retail.currencyRates(widget.orgId);
      if (!mounted) return;
      setState(() {
        _rates =
            rates.where((r) => r.currency != widget.homeCurrency).toList();
        _picked = _rates.isEmpty ? null : _rates.first;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '.'));

  double? get _converted {
    final picked = _picked;
    final amount = _amount;
    if (picked == null || amount == null || amount <= 0) return null;
    return picked.toHome(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.homeCurrency);
    final converted = _converted;

    return AlertDialog(
      title: const Text('Convertir un montant'),
      content: _loading
          ? const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()))
          : _rates.isEmpty
              ? const Text(
                  'Aucun taux de change défini. Ajoutez vos monnaies dans '
                  'Administration › Paramètres › Taux de change.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<CurrencyRate>(
                      initialValue: _picked,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Monnaie payée',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final r in _rates)
                          DropdownMenuItem(
                            value: r,
                            child: Text(
                                '${r.currency} — ${knownCurrencies[r.currency] ?? ''}'),
                          ),
                      ],
                      onChanged: (r) => setState(() => _picked = r),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Montant',
                        suffixText: _picked?.currency,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (converted != null && _picked != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        money.format(converted),
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        rateLabel(_picked!.currency, _picked!.rate,
                            widget.homeCurrency),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        if (!_loading && _rates.isNotEmpty)
          FilledButton(
            onPressed: converted == null
                ? null
                : () => Navigator.of(context).pop(converted),
            child: const Text('Utiliser'),
          ),
      ],
    );
  }
}

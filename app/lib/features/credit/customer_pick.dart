import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';

/// « Pour qui ? » in the step flows (115): the customer's name typed, with
/// the business's known customers offered as big chips under it — the ones
/// that match what is typed, at most eight. Tapping one fills the name.
///
/// The server matches a customer by name (create_invoice, record_credit_sale:
/// trimmed, case-insensitive), so a chip and the same name typed are the
/// same customer.
class CustomerPick extends StatelessWidget {
  const CustomerPick({
    super.key,
    required this.controller,
    required this.known,
    required this.onChanged,
    this.hint,
  });

  final TextEditingController controller;

  /// Names the business already has, most useful first.
  final List<String> known;
  final VoidCallback onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final typed = controller.text.trim().toLowerCase();
    final offered = [
      for (final n in known)
        if (typed.isEmpty ||
            (n.toLowerCase().contains(typed) && n.toLowerCase() != typed))
          n,
    ].take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('customer-name'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: context.tr('Nom du client'),
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        if (offered.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(context.tr('Vos clients'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in offered)
                ActionChip(
                  key: Key('customer-known-$n'),
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(n, style: const TextStyle(fontSize: 16)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  onPressed: () {
                    controller.text = n;
                    controller.selection =
                        TextSelection.collapsed(offset: n.length);
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

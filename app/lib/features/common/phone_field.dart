import 'package:flutter/material.dart';

import '../../core/phone/country_codes.dart';

/// A phone field whose country code is chosen rather than assumed.
///
/// Every phone field in the app used to be a plain `TextField` with
/// `prefixText: '+226  '` painted in front of it. That prefix was decoration:
/// it was not part of the value, it could not be changed, and the code that
/// turned the text into E.164 pasted `+226` on regardless. So a number from
/// Abidjan typed into it did not merely look wrong, it *became* a Burkinabè
/// number — a real one, belonging to somebody else, and the confirmation SMS
/// went there.
///
/// Here the prefix is a button. What it shows is what [country] is, and what
/// [country] is decides the code the caller normalises with. The two cannot
/// drift apart, because there is only one of them.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountry,
    required this.labelText,
    this.enabled = true,
    this.hintText,
    this.helperText,
    this.errorText,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.large = false,
  });

  final TextEditingController controller;
  final CountryCode country;
  final ValueChanged<CountryCode> onCountry;
  final String labelText;
  final bool enabled;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Sign-up and sign-in set this: the number is the single thing on the
  /// screen and is read back aloud off it.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      autofillHints: autofillHints,
      style: large ? const TextStyle(fontSize: 20, letterSpacing: 1.2) : null,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        helperText: helperText,
        errorText: errorText,
        border: const OutlineInputBorder(),
        // A prefixIcon rather than prefixText: only the former can be tapped.
        // The tight constraints stop Material's 48px minimum from pushing the
        // number itself off to the right.
        prefixIcon: _CountryButton(
          country: country,
          enabled: enabled,
          onPressed: () => _pick(context),
          style: theme.textTheme.bodyLarge,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final chosen = await showModalBottomSheet<CountryCode>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CountrySheet(selected: country),
    );
    if (chosen != null) onCountry(chosen);
  }
}

class _CountryButton extends StatelessWidget {
  const _CountryButton({
    required this.country,
    required this.enabled,
    required this.onPressed,
    this.style,
  });

  final CountryCode country;
  final bool enabled;
  final VoidCallback onPressed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              country.iso,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(country.dial, style: style),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The list itself: West Africa at the top, a search box for everything else.
///
/// The search matches the dialling code as well as the name, because somebody
/// who knows their own country only as "+225" should not have to remember how
/// France spells it.
class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.selected});

  final CountryCode selected;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final near = westAfrica.where((c) => countryMatches(c, _query)).toList();
    final far = otherCountries.where((c) => countryMatches(c, _query)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Indicatif du pays', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Pays ou indicatif',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: near.isEmpty && far.isEmpty
                  ? const Center(child: Text('Aucun pays trouvé.'))
                  : ListView(
                      children: [
                        if (near.isNotEmpty) ...[
                          _heading(theme, 'Afrique de l’Ouest'),
                          for (final c in near) _tile(c),
                        ],
                        if (far.isNotEmpty) ...[
                          _heading(theme, 'Autres pays'),
                          for (final c in far) _tile(c),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(
          text,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.primary),
        ),
      );

  Widget _tile(CountryCode country) {
    final chosen = country.iso == widget.selected.iso;
    return ListTile(
      dense: true,
      leading: Text(
        country.iso,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      title: Text(country.name),
      trailing: Text(
        country.dial,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      selected: chosen,
      onTap: () => Navigator.pop(context, country),
    );
  }
}

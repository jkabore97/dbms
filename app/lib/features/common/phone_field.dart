import 'package:flutter/material.dart';

import '../../core/phone/country_codes.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';

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
    final chosen = await showMaraSheet<CountryCode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
                  Text(context.tr('Indicatif du pays'), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: context.tr('Pays ou indicatif'),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: near.isEmpty && far.isEmpty
                  ? Center(child: Text(context.tr('Aucun pays trouvé.')))
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
      title: Text(context.tr(country.name)),
      trailing: Text(
        country.dial,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      selected: chosen,
      onTap: () => Navigator.pop(context, country),
    );
  }
}

/// A [PhoneField] that keeps its own country (178): the screen's
/// [controller] always holds the whole number, `+22670000000` — what the
/// screen already saved and reads — while the person picks a country and
/// types only the rest. A number already in [controller] (loaded, or set
/// later) opens under its own country. Empty stays empty.
class PhoneInput extends StatefulWidget {
  const PhoneInput({
    super.key,
    required this.controller,
    required this.labelText,
    this.enabled = true,
    this.hintText,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.country = defaultCountry,
  });

  /// Holds the whole number (E.164), read and written by the screen.
  final TextEditingController controller;
  final String labelText;
  final bool enabled;
  final String? hintText;
  final String? helperText;

  /// The screen's own words; else the length the chosen country expects.
  final String? errorText;

  /// The whole number, each time it changes.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// The country shown first when the field is empty.
  final CountryCode country;

  @override
  State<PhoneInput> createState() => _PhoneInputState();
}

class _PhoneInputState extends State<PhoneInput> {
  late CountryCode _country = widget.country;
  final _local = TextEditingController();
  String _written = '';

  @override
  void initState() {
    super.initState();
    _read();
    widget.controller.addListener(_outside);
  }

  @override
  void didUpdateWidget(PhoneInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_outside);
      widget.controller.addListener(_outside);
      _read();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_outside);
    _local.dispose();
    super.dispose();
  }

  /// The screen's number, split into its country and the rest.
  void _read() {
    final whole = widget.controller.text.trim();
    _written = whole;
    if (whole.isEmpty) {
      _local.text = '';
      return;
    }
    final e164 = whole.startsWith('00') ? '+${whole.substring(2)}' : whole;
    final found = countryOfNumber(e164.replaceAll(RegExp(r'[\s\-().]'), ''));
    if (found != null) {
      _country = found;
      _local.text = found.localPart(e164.replaceAll(RegExp(r'[\s\-().]'), ''));
    } else {
      _local.text = whole;
    }
  }

  /// The screen set its number itself (a load): shown again.
  void _outside() {
    if (widget.controller.text == _written) return;
    setState(_read);
  }

  void _write() {
    final typed = _local.text.trim();
    final whole = typed.isEmpty ? '' : _country.toE164(typed);
    _written = whole;
    if (widget.controller.text != whole) widget.controller.text = whole;
    widget.onChanged?.call(whole);
  }

  @override
  Widget build(BuildContext context) {
    return PhoneField(
      controller: _local,
      country: _country,
      enabled: widget.enabled,
      labelText: widget.labelText,
      hintText: widget.hintText,
      helperText: widget.helperText,
      errorText: widget.errorText ?? (_local.text.trim().isEmpty ? null : _country.lengthProblem(_local.text)),
      onCountry: (c) {
        setState(() => _country = c);
        _write();
      },
      onChanged: (_) {
        setState(() {});
        _write();
      },
      onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(widget.controller.text),
    );
  }
}

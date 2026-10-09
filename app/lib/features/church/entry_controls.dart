import 'package:flutter/material.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The controls the recording sheet that remains (the transfer) and the
/// farm's stock threshold are built from.
///
/// They live here rather than in any one sheet because recording money must
/// feel like the same machine: the same keypad in the same place, the same
/// chips behaving the same way. A second, subtly different keypad is how a
/// person who has learned one screen gets slower on the other.

/// A row of mutually exclusive chips over `{value: label}`.
///
/// Wraps rather than scrolls when [wrap] is set. Horizontal scrolling hides
/// options past the right edge, which is survivable for three payment methods
/// and not for seven expense categories — an option nobody scrolls to is an
/// option that gets miscategorised into whichever one was visible.
class ChoiceChipRow extends StatelessWidget {
  const ChoiceChipRow({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelect,
    this.wrap = false,
  });

  final Map<String, String> values;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = values.entries
        .map((e) => ChoiceChip(
              label: Text(e.value),
              selected: selected == e.key,
              onSelected: (_) => onSelect(e.key),
            ))
        .toList();

    if (wrap) {
      return Wrap(spacing: 8, runSpacing: 8, children: chips);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        ],
      ),
    );
  }
}

/// Asks for one short line of text — the farm's stock threshold, and
/// anything else that is one line.
///
/// Returns null when cancelled and never returns an empty string, so the
/// caller can treat "" and "nothing" as the same non-answer.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String initial = '',
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _NamePrompt(
      title: title,
      label: label,
      hint: hint,
      initial: initial,
    ),
  );
  return (result == null || result.isEmpty) ? null : result;
}

/// The dialog owns its controller, rather than the function that shows it.
///
/// `showDialog`'s future completes the moment the route is popped, but the
/// route keeps building its content for the length of the exit animation. A
/// controller disposed as soon as the future returns is therefore disposed
/// while a live TextField still holds it, which throws "A TextEditingController
/// was used after being disposed" on the next frame. Letting the widget own it
/// ties the lifetime to the thing that is actually using it.
class _NamePrompt extends StatefulWidget {
  const _NamePrompt({
    required this.title,
    required this.label,
    this.hint,
    this.initial = '',
  });

  final String title;
  final String label;
  final String? hint;
  final String initial;

  @override
  State<_NamePrompt> createState() => _NamePromptState();
}

class _NamePromptState extends State<_NamePrompt> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // The keyboard up on a small phone: the dialog scrolls (A6).
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.tr('Valider')),
        ),
      ],
    );
  }
}

/// The drawn numeric keypad.
///
/// Drawn rather than borrowed from the OS for the same reason as the PIN pad:
/// the targets are always large, they never cover the amount they are
/// entering, and they do not change shape between phones. `000` is there
/// because these are CFA francs and most amounts end in three zeros.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '000',
      '0',
      '<',
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.0,
      children: keys.map((k) {
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => k == '<' ? onBackspace() : onDigit(k),
          child: Center(
            child: k == '<'
                ? const Icon(Icons.backspace_outlined, size: 24)
                : Text(
                    k,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }
}

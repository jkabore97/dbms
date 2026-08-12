import 'package:flutter/material.dart';

/// The two controls both recording sheets are built from.
///
/// They live here rather than in either sheet because money in and money out
/// must feel like the same machine: the same keypad in the same place, the
/// same chips behaving the same way. A second, subtly different keypad is how
/// a person who has learned one screen gets slower on the other.

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
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '000', '0', '<',
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

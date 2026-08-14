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

/// The categories on offer, plus the one that is not on offer yet.
///
/// The old expense sheet had seven categories compiled into the app and no way
/// to add an eighth. It was defended as protecting the books from seven
/// spellings of "Loyer", and that danger is real — but a list nobody can add
/// to does not produce clean books, it produces books where "Fournitures"
/// means eleven different things and no report can separate them.
///
/// So both things are true at once here. The chips are the names already in
/// the chart of accounts, offered first because most entries repeat and
/// choosing one posts the exact name the books already hold. "Autre…" is a
/// text field, and what someone types there becomes a real account the first
/// time and a chip every time after.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.onAddNew,
    this.labelFor,
  });

  /// The names as the books hold them. What gets posted.
  final List<String> categories;

  final String? selected;
  final ValueChanged<String> onSelect;

  /// Opens whatever asks for a new name. Separate from [onSelect] because
  /// adding one is a different act from picking one and can be cancelled.
  final VoidCallback onAddNew;

  /// How to display a stored name. The seeded chart is in English and the
  /// screens are in French; anything typed by a person is shown verbatim.
  final String Function(String)? labelFor;

  @override
  Widget build(BuildContext context) {
    String show(String name) => labelFor?.call(name) ?? name;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in categories)
          ChoiceChip(
            label: Text(show(name)),
            selected: selected == name,
            onSelected: (_) => onSelect(name),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('Autre…'),
          onPressed: onAddNew,
        ),
      ],
    );
  }
}

/// One typed characteristic: a name and a value, both free text.
typedef Characteristic = ({String name, String value});

/// Whatever else the entry needs that nobody predicted — a supplier, an
/// invoice number, a beneficiary, a quantity, the road that was repaired.
///
/// Both halves are typed, which is the point. A fixed set of extra fields
/// would be the same mistake as a fixed set of categories, one level down; the
/// schema stores these as jsonb precisely so nobody has to have guessed the
/// key. They are never totalled and never reported on — this is a place to
/// record what happened, and anything that earns a report earns a column.
class CharacteristicsEditor extends StatelessWidget {
  const CharacteristicsEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  final List<Characteristic> values;
  final ValueChanged<List<Characteristic>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    initialValue: values[i].name,
                    enabled: enabled,
                    style: theme.textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      labelText: 'Quoi',
                      hintText: 'Fournisseur',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) =>
                        _replace(i, (name: v, value: values[i].value)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    initialValue: values[i].value,
                    enabled: enabled,
                    style: theme.textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      labelText: 'Détail',
                      hintText: 'Kaboré',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) =>
                        _replace(i, (name: values[i].name, value: v)),
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: enabled
                      ? () => onChanged([...values]..removeAt(i))
                      : null,
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled
                ? () => onChanged([...values, (name: '', value: '')])
                : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajouter une caractéristique'),
          ),
        ),
      ],
    );
  }

  void _replace(int index, Characteristic value) {
    final next = [...values];
    next[index] = value;
    onChanged(next);
  }
}

/// Asks for a name. Used for a new category, a new stock item, and anything
/// else that is one short line of text.
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
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Valider'),
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

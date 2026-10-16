import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/money/money_types.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/mara_sheet.dart';
import '../common/keyboard_sheet.dart';
import 'money_steps.dart' show headingIcon;

/// « Ajouter un type de recette / de dépense » and « Gérer » (149): the
/// types a business adds itself, on Recette's and Dépense's first step.
///
/// A type is an account of the chart (core/money/money_types.dart), so
/// hiding one keeps it and every entry on it, and a type renamed after
/// entries were posted to it keeps its name in the books and changes only
/// its card.

/// The picture on a type's card, read off its words.
IconData typeIcon(MoneyType t) => headingIcon(t.display);

/// « Recette » or « Dépense » words, by direction.
String _addTitle(BuildContext context, String direction) => direction == 'in'
    ? context.tr('Ajouter un type de recette')
    : context.tr('Ajouter un type de dépense');

/// The short form: a name (required), a short description. Refuses a name
/// already used (an account of the same kind, accents and case aside, or a
/// built-in card). The new type, or null when closed.
Future<MoneyType?> showAddTypeSheet(
  BuildContext context, {
  required MoneyTypesBook book,
  required String orgId,
  required MoneyTypesList current,
  required String direction,
}) => showMaraSheet<MoneyType>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _TypeSheet(
    book: book,
    orgId: orgId,
    current: current,
    direction: direction,
  ),
);

class _TypeSheet extends StatefulWidget {
  const _TypeSheet({
    required this.book,
    required this.orgId,
    required this.current,
    required this.direction,
    this.editing,
  });

  final MoneyTypesBook book;
  final String orgId;
  final MoneyTypesList current;
  final String direction;

  /// Renaming this one, rather than adding.
  final MoneyType? editing;

  @override
  State<_TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends State<_TypeSheet> {
  late final _name = TextEditingController(text: widget.editing?.display ?? '');
  late final _desc = TextEditingController(
    text: widget.editing?.description ?? '',
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  String get _clean => _name.text.trim();

  bool get _duplicate {
    final e = widget.editing;
    if (e != null && typeKey(_clean) == typeKey(e.display)) return false;
    return widget.current.taken(widget.direction, _clean, except: e?.id);
  }

  Future<void> _save() async {
    if (_clean.isEmpty || _busy) return;
    if (_duplicate) {
      setState(() => _error = DuplicateTypeException(_clean).toString());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final e = widget.editing;
      if (e == null) {
        final added = await widget.book.add(
          widget.orgId,
          widget.current,
          direction: widget.direction,
          name: _clean,
          description: _desc.text,
        );
        nav.pop(added);
      } else {
        await widget.book.update(
          widget.orgId,
          widget.current,
          e,
          name: _clean == e.display ? null : _clean,
          description: _desc.text.trim() == (e.description ?? '')
              ? null
              : _desc.text.trim(),
        );
        nav.pop(e);
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.editing;
    final inBooks = e != null && e.entryCount > 0;
    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('type-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const Key('type-save'),
              onPressed: _clean.isEmpty || _busy ? null : _save,
              child: Text(
                e == null ? context.tr('Ajouter') : context.tr('Enregistrer'),
              ),
            ),
          ),
        ],
      ),
      children: [
        Text(
          e == null
              ? _addTitle(context, widget.direction)
              : context.tr('Modifier le type'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          widget.direction == 'in'
              ? context.tr(
                  'Il aura sa carte à la première étape et son compte dans les livres.',
                )
              : context.tr(
                  'Il aura sa tuile à la première étape et son compte dans les livres.',
                ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('type-name'),
          controller: _name,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: context.tr('Nom'),
            hintText: widget.direction == 'in'
                ? context.tr('Ex. : kermesse annuelle')
                : context.tr('Réparation du toit'),
            border: const OutlineInputBorder(),
            errorText: _clean.isNotEmpty && _duplicate
                ? context.tr('Ce nom est déjà pris.')
                : null,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('type-description'),
          controller: _desc,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.tr('Description courte (facultatif)'),
            hintText: widget.direction == 'in'
                ? context.tr('Chaque premier samedi du mois')
                : context.tr('Pompe, tuyaux, main-d\'œuvre'),
            border: const OutlineInputBorder(),
          ),
        ),
        if (inBooks) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
              '{n} écriture(s) portent ce nom dans les livres : elles le gardent, seule la carte change.',
              {'n': e.entryCount},
            ),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// « Gérer les types »: every type of the direction — renamed, described,
/// put in order, hidden from the first step or shown again. Hiding keeps
/// the account and its entries. Changes need the network; the list reads
/// with none.
class ManageTypesScreen extends StatefulWidget {
  const ManageTypesScreen({
    super.key,
    required this.book,
    required this.orgId,
    required this.direction,
    this.canEdit = true,
  });

  final MoneyTypesBook book;
  final String orgId;
  final String direction;
  final bool canEdit;

  @override
  State<ManageTypesScreen> createState() => _ManageTypesScreenState();
}

class _ManageTypesScreenState extends State<ManageTypesScreen> {
  MoneyTypesList? _list;
  List<MoneyType> _types = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.book.load(widget.orgId);
    if (!mounted) return;
    setState(() {
      _list = list;
      _types = list.manageable(widget.direction);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      await _load();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
      await _load();
    }
  }

  Future<void> _add() async {
    final list = _list;
    if (list == null) return;
    final added = await showAddTypeSheet(
      context,
      book: widget.book,
      orgId: widget.orgId,
      current: list,
      direction: widget.direction,
    );
    if (added != null) await _load();
  }

  Future<void> _edit(MoneyType t) async {
    final list = _list;
    if (list == null) return;
    final done = await showMaraSheet<MoneyType>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TypeSheet(
        book: widget.book,
        orgId: widget.orgId,
        current: list,
        direction: widget.direction,
        editing: t,
      ),
    );
    if (done != null) await _load();
  }

  void _reorder(int from, int to) {
    final next = [..._types];
    final moved = next.removeAt(from);
    next.insert(to, moved);
    setState(() => _types = next);
    _run(() => widget.book.reorder(widget.orgId, widget.direction, next));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _list;
    final title = widget.direction == 'in'
        ? context.tr('Types de recette')
        : context.tr('Types de dépense');
    return Scaffold(
        appBar: AppBar(title: Text(title), actions: const [bellRoom]),
        floatingActionButton: widget.canEdit
            ? FloatingActionButton.extended(
                key: const Key('types-add'),
                heroTag: 'types-add',
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(context.tr('Ajouter')),
              )
            : null,
        body: list == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      context.tr(
                        'Glissez pour changer l\'ordre. Masquer retire la carte de la première étape : le compte et ses écritures restent.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (list.fromPhone || !list.serverReady)
                    Container(
                      key: const Key('types-offline'),
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              !list.serverReady
                                  ? context.tr(
                                      'Vous pouvez ajouter des types. Renommer, masquer et ranger arrivent avec la prochaine mise à jour du serveur.',
                                    )
                                  : context.tr(
                                      'Sans réseau : la liste est celle du téléphone. Les ajouts partiront au retour du réseau ; renommer, masquer et ranger attendent le réseau.',
                                    ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _types.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                context.tr('Aucun type ajouté pour le moment.'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.only(bottom: 96, top: 8),
                            buildDefaultDragHandles: false,
                            itemCount: _types.length,
                            onReorderItem: widget.canEdit
                                ? _reorder
                                : (_, _) {},
                            itemBuilder: (context, i) =>
                                _row(context, i, _types[i]),
                          ),
                  ),
                ],
              ),
    );
  }

  Widget _row(BuildContext context, int i, MoneyType t) {
    final theme = Theme.of(context);
    final faded = !t.active;
    final sub = [
      if (t.description != null) t.description!,
      if (t.pending) context.tr('pas encore envoyé'),
      if (t.entryCount > 0) context.tr('{n} écriture(s)', {'n': t.entryCount}),
      if (faded) context.tr('masqué'),
    ].join(' · ');
    return Material(
      key: ValueKey(t.id),
      color: Colors.transparent,
      child: ListTile(
        key: Key('type-row-${t.name}'),
        contentPadding: const EdgeInsets.only(left: 4, right: 4),
        leading: widget.canEdit
            ? ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_indicator),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(typeIcon(t)),
              ),
        title: Text(
          t.display,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: faded ? theme.colorScheme.onSurfaceVariant : null,
            fontStyle: faded ? FontStyle.italic : null,
          ),
        ),
        subtitle: sub.isEmpty
            ? null
            : Text(sub, maxLines: 3, overflow: TextOverflow.ellipsis),
        onTap: widget.canEdit ? () => _edit(t) : null,
        trailing: widget.canEdit
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('type-edit-${t.name}'),
                    tooltip: context.tr('Renommer'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(t),
                  ),
                  Switch(
                    key: Key('type-shown-${t.name}'),
                    value: t.active,
                    onChanged: (v) => _run(
                      () => widget.book.update(
                        widget.orgId,
                        _list!,
                        t,
                        active: v,
                      ),
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

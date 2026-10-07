import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/access/plan_terms.dart';
import '../../../core/console/command_center.dart';
import '../../../core/console/models.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart' show parseAmount;
import '../../../core/l10n/tr.dart';
import '../../../core/theme/mara_mark.dart';
import 'todo_section.dart' show featureName;

/// What several ticked businesses can be given at once (105's
/// platform_bulk).
enum BulkAction { cauris, unlock, message, archive }

/// One act for every ticked business: the form, then what was done and,
/// business by business, what was refused and why. Returns the result, or
/// null when nothing was sent.
Future<BulkResult?> showBulkSheet(
  BuildContext context, {
  required BulkAction action,
  required List<OrgRow> orgs,
  required CommandCenterRepository center,
  List<String> tools = const [],
}) async {
  final result = await showModalBottomSheet<BulkResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BulkSheet(action: action, orgs: orgs, center: center, tools: tools),
  );
  if (result != null && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('bulk-result'),
        title: Text(context.tr('Fait pour {n} entreprise(s)', {'n': result.done})),
        content: result.failed.isEmpty
            ? Text(context.tr('Chaque action est dans le Journal, avec son « Annuler » quand elle peut être reprise.'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('Pas fait pour :'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final f in result.failed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${f.name ?? f.orgId} — ${translate(context.trLanguage, f.error)}'),
                    ),
                ],
              ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(context.tr('Compris')),
          ),
        ],
      ),
    );
  }
  return result;
}

class BulkSheet extends StatefulWidget {
  const BulkSheet({
    super.key,
    required this.action,
    required this.orgs,
    required this.center,
    this.tools = const [],
  });

  final BulkAction action;
  final List<OrgRow> orgs;
  final CommandCenterRepository center;

  /// The tools that can be opened (cauris_costs, photo slot aside).
  final List<String> tools;

  /// Above this many cauris in all, the center asks once more.
  static const confirmAbove = 2000;

  @override
  State<BulkSheet> createState() => _BulkSheetState();
}

class _BulkSheetState extends State<BulkSheet> {
  final _points = TextEditingController();
  final _note = TextEditingController();
  final _message = TextEditingController();
  bool _promo = false;
  late DateTime _until = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 30));
  String? _tool;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _points.dispose();
    _note.dispose();
    _message.dispose();
    super.dispose();
  }

  /// Only the tools every ticked business has (an association has no
  /// analyses, no delivery — 099).
  List<String> get _tools => [
        for (final t in widget.tools)
          if (widget.orgs.every((o) => PlanTerms.fits(t, o.profile))) t,
      ];

  static String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = widget.action == BulkAction.cauris ? today.add(const Duration(days: 1)) : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _until.isBefore(first) ? first : _until,
      firstDate: first,
      lastDate: today.add(const Duration(days: 366)),
    );
    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _send() async {
    final n = widget.orgs.length;
    Map<String, Object?> args;
    String action;
    switch (widget.action) {
      case BulkAction.cauris:
        final points = parseAmount(_points.text)?.round();
        if (points == null || points <= 0) {
          setState(() => _error = context.tr('Combien de cauris ?'));
          return;
        }
        if (points * n > BulkSheet.confirmAbove) {
          final sure = await _confirm(context.tr('Offrir {n} cauris à {count} entreprises ?',
              {'n': points, 'count': n}));
          if (!sure) return;
        }
        action = 'cauris';
        args = {
          'points': points,
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
          if (_promo) 'expires_on': _day(_until),
        };
      case BulkAction.unlock:
        if (_tool == null) {
          setState(() => _error = context.tr('Quel outil ?'));
          return;
        }
        action = 'unlock';
        args = {
          'feature': _tool,
          'until': _day(_until),
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        };
      case BulkAction.message:
        final text = _message.text.trim();
        if (text.isEmpty) {
          setState(() => _error = context.tr('Le message est vide'));
          return;
        }
        action = 'message';
        args = {'message': text};
      case BulkAction.archive:
        action = 'archive';
        args = const {};
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.center.bulk(action, [for (final o in widget.orgs) o.id], args);
      if (mounted) Navigator.of(context).pop(r);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  Future<bool> _confirm(String question) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.tr('Retour')),
          ),
          FilledButton(
            key: const Key('bulk-confirm'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.tr('Oui')),
          ),
        ],
      ),
    );
    return sure == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.orgs.length;
    final names = widget.orgs.take(3).map((o) => o.name).join(', ') +
        (n > 3 ? context.tr(' et {n} autres', {'n': n - 3}) : '');
    final (title, cta) = switch (widget.action) {
      BulkAction.cauris => (context.tr('Offrir des cauris'), context.tr('Offrir')),
      BulkAction.unlock => (context.tr('Ouvrir un outil jusqu\'à une date'), context.tr('Ouvrir')),
      BulkAction.message => (context.tr('Envoyer un message'), context.tr('Envoyer')),
      BulkAction.archive => (context.tr('Archiver'), context.tr('Archiver')),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          key: const Key('bulk-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(context.tr('{n} entreprise(s) : {names}', {'n': n, 'names': names}),
                style: theme.textTheme.bodyMedium?.copyWith(color: maraBrown)),
            const SizedBox(height: 16),
            if (widget.action == BulkAction.cauris) ...[
              TextField(
                key: const Key('bulk-points'),
                controller: _points,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: theme.textTheme.headlineSmall,
                decoration: InputDecoration(
                  labelText: context.tr('Cauris pour chacune'),
                  border: const OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _promo,
                onChanged: _busy ? null : (v) => setState(() => _promo = v),
                title: Text(context.tr('À utiliser avant une date')),
                subtitle: Text(context.tr('Dépensés en premier ; ce qui reste disparaît ce jour-là.')),
              ),
            ],
            if (widget.action == BulkAction.unlock)
              DropdownButtonFormField<String>(
                key: const Key('bulk-tool'),
                initialValue: _tool,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Outil'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final t in _tools)
                    DropdownMenuItem(value: t, child: Text(featureName(context, t))),
                ],
                onChanged: _busy ? null : (v) => setState(() => _tool = v),
              ),
            if (widget.action == BulkAction.unlock ||
                (widget.action == BulkAction.cauris && _promo)) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('bulk-date'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : _pickDate,
                icon: const Icon(Icons.event),
                label: Text(widget.action == BulkAction.cauris
                    ? context.tr('À utiliser avant le {date}',
                        {'date': DateFormat('dd/MM/yyyy').format(_until)})
                    : context.tr('Ouvert jusqu\'au {date} inclus',
                        {'date': DateFormat('dd/MM/yyyy').format(_until)})),
              ),
            ],
            if (widget.action == BulkAction.cauris || widget.action == BulkAction.unlock) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('bulk-note'),
                controller: _note,
                enabled: !_busy,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: context.tr('Un mot pour eux (facultatif)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (widget.action == BulkAction.message)
              TextField(
                key: const Key('bulk-message-text'),
                controller: _message,
                enabled: !_busy,
                autofocus: true,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: context.tr('Il arrive dans la cloche de leurs propriétaires et administrateurs.'),
                ),
              ),
            if (widget.action == BulkAction.archive)
              Text(context.tr('Elles disparaissent de l\'accueil de leurs membres ; rien n\'est effacé. Le Journal les restaure d\'un « Annuler ».')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('bulk-send'),
                style: widget.action == BulkAction.archive
                    ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
                    : null,
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr('{action} ({n})', {'action': cta, 'n': n}),
                        style: const TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/console/command_center.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/router.dart';
import '../../../core/storefront/storefront_repository.dart' show whatsappUrl;
import '../../../core/theme/mara_mark.dart';
import '../../shopper/report_sheet.dart' show reportTopicLabel;

/// À faire › « Signalements » (113): what shoppers reported, the oldest
/// open first. Each says who, how to answer them (their WhatsApp or their
/// e-mail), the vitrine it names; « Traité », with a line the person reads
/// in their notifications, closes it — journaled, with « Annuler ».
Future<void> showReportsSheet(BuildContext context, {required CommandCenterRepository center}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReportsSheet(center: center, outer: context),
    );

class ReportsSheet extends StatefulWidget {
  const ReportsSheet({super.key, required this.center, required this.outer});

  final CommandCenterRepository center;

  /// The page under the sheet: a vitrine's fiche opens there.
  final BuildContext outer;

  @override
  State<ReportsSheet> createState() => _ReportsSheetState();
}

class _ReportsSheetState extends State<ReportsSheet> {
  bool _handled = false;
  List<ProblemReport>? _rows;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.center.reports(handled: _handled);
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _close(ProblemReport r) async {
    final messenger = ScaffoldMessenger.of(widget.outer);
    final answer = await showDialog<String>(
      context: context,
      builder: (_) => const _AnswerDialog(),
    );
    if (answer == null || !mounted) return;
    final done = context.tr('Signalement traité : la personne est prévenue.');
    final undoLabel = context.tr('Annuler');
    setState(() => _busy = r.id);
    try {
      final id = await widget.center.handleReport(r.id, answer: answer.isEmpty ? null : answer);
      await _load();
      messenger.showSnackBar(SnackBar(
        content: Text(done),
        action: id == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () async {
                  try {
                    await widget.center.undo(id);
                    if (mounted) await _load();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
                  }
                },
              ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _reach(String contact) async {
    final url = contact.contains('@')
        ? 'mailto:$contact'
        : whatsappUrl(contact, text: context.tr('Bonjour, c\'est Mara, à propos de votre signalement.'));
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    final day = DateFormat('dd/MM HH:mm');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(context.tr('Signalements'),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  SegmentedButton<bool>(
                    key: const Key('reports-filter'),
                    segments: [
                      ButtonSegment(value: false, label: Text(context.tr('À lire'))),
                      ButtonSegment(value: true, label: Text(context.tr('Traités'))),
                    ],
                    selected: {_handled},
                    onSelectionChanged: (s) {
                      setState(() {
                        _handled = s.first;
                        _rows = null;
                      });
                      _load();
                    },
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              )
            else if (rows == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(context.tr('Plus rien ici.')),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return Container(
                      key: Key('report-${r.id}'),
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                      decoration: BoxDecoration(
                        color: r.handled ? theme.colorScheme.surfaceContainerLow : maraPaper,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: r.handled ? theme.colorScheme.outlineVariant : maraCaramel),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.flag_outlined, size: 18, color: maraBrown),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  [
                                    reportTopicLabel(context, r.topic),
                                    if (r.at != null) day.format(r.at!),
                                  ].join(' · '),
                                  style: theme.textTheme.labelLarge?.copyWith(color: maraBrown),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(r.message, style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(r.reporter ?? context.tr('Un client'),
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (r.contact != null)
                                TextButton.icon(
                                  onPressed: () => _reach(r.contact!),
                                  icon: Icon(r.contact!.contains('@') ? Icons.mail_outline : Icons.chat_outlined,
                                      size: 16),
                                  label: Text(r.contact!),
                                ),
                              if (r.orgId != null)
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    widget.outer.push(Routes.consoleOrg(r.orgId!));
                                  },
                                  icon: const Icon(Icons.storefront_outlined, size: 16),
                                  label: Text(r.orgName ?? r.slug ?? ''),
                                ),
                            ],
                          ),
                          if (r.handled)
                            Text(
                              r.answer == null
                                  ? context.tr('Traité.')
                                  : context.tr('Traité : {answer}', {'answer': r.answer}),
                              style: theme.textTheme.bodySmall,
                            )
                          else
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonal(
                                key: Key('report-close-${r.id}'),
                                onPressed: _busy != null ? null : () => _close(r),
                                child: Text(context.tr('Traité')),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The line the person reads in their notifications — optional.
class _AnswerDialog extends StatefulWidget {
  const _AnswerDialog();

  @override
  State<_AnswerDialog> createState() => _AnswerDialogState();
}

class _AnswerDialogState extends State<_AnswerDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Signalement traité')),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('report-answer'),
          controller: _text,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: context.tr('Un mot pour la personne (facultatif)'),
            hintText: context.tr('Remboursé par la boutique, merci !'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          key: const Key('report-answer-send'),
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: Text(context.tr('Traité')),
        ),
      ],
    );
  }
}

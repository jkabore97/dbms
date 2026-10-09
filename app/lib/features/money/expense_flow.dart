import 'package:flutter/material.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/reports/models.dart' show accountLabel;
import '../capture/capture_action.dart';
import '../common/step_flow.dart';
import 'money_steps.dart';

/// « Dépense », one entry at a time (115) — for a shop, a farm and an
/// association alike.
///
/// The heading (big tiles: the business's own expense accounts, « Autre »
/// to name a new one) → the amount → how it was paid → a word about it
/// (optional) → the receipt's photo (optional: taken, chosen in the
/// phone, or « Choisir dans Photos », 114) → the summary → « Enregistrer » → « C'est fait ».
///
/// Written exactly as the association's recording sheet wrote it, which
/// this replaces: LocalDb.recordEntry — the outbox row and the day's entry
/// in one transaction, no network, record_entry() (007) when the signal
/// comes. The photo goes through the capture queue (kind 'receipt',
/// captioned with the expense), which also works offline. A shop and a
/// farm had no way to record an expense before; their homes now open this.
class ExpenseFlow extends StatefulWidget {
  const ExpenseFlow({
    super.key,
    required this.db,
    required this.orgId,
    required this.profile,
    this.currency = 'XOF',
    this.capture,
    this.store,
  });

  final LocalDb db;
  final String orgId;

  /// 'retail' | 'farm' | 'association' | 'church' — which headings to
  /// offer before the chart has reached this phone.
  final String profile;
  final String currency;

  /// Null (or not configured): no photo step.
  final CaptureRepository? capture;
  final FlowStore? store;

  @override
  State<ExpenseFlow> createState() => _ExpenseFlowState();
}

class _ExpenseFlowState extends State<ExpenseFlow> {
  final _flow = StepFlowController();
  final _otherName = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  /// The memo (optional), apart from the word the entry is called by: what
  /// the old recording sheet's « Note » kept (batch 115).
  final _memo = TextEditingController();
  String? _heading;
  String _method = 'cash';
  List<String> _headings = const [];

  PickedPhoto? _photo;

  /// After saving: whether the photo left at once, waits for the network,
  /// or could not be kept (said on « C'est fait », never a failure of the
  /// expense itself, which is already written).
  String? _photoNote;

  NumberFormat get _money => moneyFormat(widget.currency);
  double get _value => parseAmount(_amount.text) ?? 0;
  bool get _photos => widget.capture?.isConfigured ?? false;

  @override
  void initState() {
    super.initState();
    _loadHeadings();
  }

  @override
  void dispose() {
    _otherName.dispose();
    _amount.dispose();
    _note.dispose();
    _memo.dispose();
    super.dispose();
  }

  /// The business's expense accounts as this phone last heard them — the
  /// same source the sheet used — or, before the chart ever arrived, a few
  /// usual headings for its kind (typed names: record_entry opens the
  /// account the first time).
  Future<void> _loadHeadings() async {
    var names = await widget.db.categoriesFor(widget.orgId, 'out');
    if (names.isEmpty) {
      names = switch (widget.profile) {
        'farm' => const ['Aliment', 'Vétérinaire', 'Main-d\'œuvre', 'Semences', 'Transport'],
        'retail' => const ['Loyer', 'Transport', 'Salaires', 'Eau et électricité'],
        _ => const ['Loyer', 'Eau et électricité', 'Entretien', 'Fournitures'],
      };
    }
    if (mounted) setState(() => _headings = names);
  }

  /// What the expense is filed under, as the books hold it.
  String get _category =>
      _heading == otherHeading ? _otherName.text.trim() : (_heading ?? '');

  /// What the entry is called: the word typed, else the heading.
  String get _label {
    final note = _note.text.trim();
    if (note.isNotEmpty) return note;
    return _heading == otherHeading ? _category : accountLabel(_category);
  }

  Map<String, Object?> _save() => {
        'heading': _heading,
        'other': _otherName.text,
        'amount': _amount.text,
        'method': _method,
        'note': _note.text,
        'memo': _memo.text,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _heading = a['heading'] as String?;
        _otherName.text = (a['other'] as String?) ?? '';
        _amount.text = (a['amount'] as String?) ?? '';
        _method = (a['method'] as String?) ?? 'cash';
        _note.text = (a['note'] as String?) ?? '';
        _memo.text = (a['memo'] as String?) ?? '';
        _photo = null;
      });

  Future<void> _pickPhoto() async {
    final picked = await CaptureAction.pick(context,
        orgId: widget.orgId, photos: widget.capture);
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  Future<bool> _record() async {
    final label = _label;
    final amount = _value;
    await widget.db.recordEntry(
      orgId: widget.orgId,
      amount: amount,
      direction: 'out',
      label: label,
      category: _category,
      method: _method,
      memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
    );
    _photoNote = null;
    final photo = _photo;
    final capture = widget.capture;
    if (photo != null && capture != null) {
      final caption = '$label — ${_money.format(amount)}';
      try {
        final id = await _keepPhoto(capture, photo, caption);
        if (mounted) {
          _photoNote = id == null
              ? context.tr('Photo gardée. Elle partira dès qu’il y a du réseau.')
              : context.tr('Photo du reçu enregistrée.');
        }
      } catch (error) {
        // The expense is written: the photo alone could not be kept.
        if (mounted) {
          _photoNote = context.tr('La dépense est enregistrée, mais pas la photo : {error}',
              {'error': error is CaptureException ? error.message : '$error'});
        }
      }
    }
    return true;
  }

  /// A photo chosen in « Photos » (114) that is about nothing yet becomes
  /// the receipt as it is — no second copy; any other is sent as a new one.
  Future<String?> _keepPhoto(
      CaptureRepository capture, PickedPhoto photo, String caption) async {
    final from = photo.from;
    if (from != null && from.productId == null && from.entryId == null) {
      try {
        await capture.file(documentId: from.id, kind: 'receipt', caption: caption);
        return from.id;
      } catch (_) {
        // No signal: the bytes are on the phone, sent as a new one.
      }
    }
    return capture.capture(
      orgId: widget.orgId,
      bytes: photo.bytes,
      contentType: photo.contentType,
      kind: 'receipt',
      caption: caption,
    );
  }

  void _another() {
    _restore(const {});
    _flow.restart();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.orange.shade800;
    return StepFlow(
      title: context.tr('Dépense'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
          key: 'expense:${widget.orgId}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'heading',
          title: context.tr('Pour quoi ?'),
          isValid: () => _heading != null,
          builder: (_) => HeadingTiles(
            headings: _headings,
            selected: _heading,
            labelFor: accountLabel,
            onSelect: (h) => setState(() => _heading = h),
          ),
        ),
        FlowStep(
          id: 'other',
          title: context.tr('Quel nom pour cette dépense ?'),
          help: context.tr('Il servira la prochaine fois.'),
          shown: () => _heading == otherHeading,
          isValid: () => _otherName.text.trim().isNotEmpty,
          builder: (_) => TextField(
            key: const Key('expense-other'),
            controller: _otherName,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr('Réparation du toit'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        FlowStep(
          id: 'amount',
          title: context.tr('Combien ?'),
          isValid: () => _value > 0,
          builder: (_) => FlowNumberField(
            key: const Key('expense-amount'),
            controller: _amount,
            suffix: widget.currency == 'XOF' ? 'FCFA' : widget.currency,
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'method',
          title: context.tr('Payée comment ?'),
          builder: (_) => FlowChoice<String>(
            options: moneyMethods(context),
            value: _method,
            onChanged: (v) => setState(() => _method = v),
          ),
        ),
        FlowStep(
          id: 'note',
          title: context.tr('Un mot sur cette dépense ?'),
          optional: true,
          builder: (_) => TextField(
            key: const Key('expense-note'),
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr('Réparation du toit'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        FlowStep(
          id: 'memo',
          title: context.tr('Une note ?'),
          help: context.tr('Ce qui aidera à s\'en souvenir : le fournisseur, le numéro du reçu…'),
          optional: true,
          builder: (_) => TextField(
            key: const Key('expense-memo'),
            controller: _memo,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        FlowStep(
          id: 'photo',
          title: context.tr('La photo du reçu ?'),
          optional: true,
          shown: () => _photos,
          builder: (_) => _photo == null
              ? FlowChoice<String>(
                  options: [
                    FlowOption('photo', context.tr('Prendre ou choisir une photo'),
                        icon: Icons.photo_camera_outlined,
                        detail: context.tr('L\'appareil photo, le téléphone ou vos Photos')),
                  ],
                  value: null,
                  onChanged: (_) => _pickPhoto(),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_photo!.bytes,
                          height: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                              height: 80,
                              child: Icon(Icons.receipt_long, size: 48))),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('expense-photo-remove'),
                      onPressed: () => setState(() => _photo = null),
                      icon: const Icon(Icons.close),
                      label: Text(context.tr('Retirer la photo')),
                    ),
                  ],
                ),
        ),
      ],
      summary: (_) => FlowSummary(rows: [
        FlowSummaryRow(context.tr('Pour'),
            _heading == otherHeading ? _category : accountLabel(_category),
            step: _heading == otherHeading ? 'other' : 'heading'),
        FlowSummaryRow(context.tr('Montant'), _money.format(_value),
            step: 'amount', bold: true),
        FlowSummaryRow(context.tr('Payée'), moneyMethodLabel(context, _method),
            step: 'method'),
        if (_note.text.trim().isNotEmpty)
          FlowSummaryRow(context.tr('Libellé'), _note.text.trim(), step: 'note'),
        if (_memo.text.trim().isNotEmpty)
          FlowSummaryRow(context.tr('Note'), _memo.text.trim(), step: 'memo'),
        if (_photos)
          FlowSummaryRow(context.tr('Reçu'),
              _photo == null ? context.tr('Pas de photo') : context.tr('Photo jointe'),
              step: 'photo'),
      ], footer: Row(
        children: [
          Icon(Icons.arrow_upward, color: accent, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(context.tr('Argent qui sort. Fonctionne sans connexion.'),
                style: TextStyle(color: accent)),
          ),
        ],
      )),
      saveLabel: context.tr('Enregistrer la dépense'),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{label} : {amount} dépensé',
            {'label': _label, 'amount': _money.format(_value)}),
        details: _photoNote == null
            ? null
            : Text(_photoNote!, textAlign: TextAlign.center),
        actions: [
          FlowAction(
            key: const Key('expense-another'),
            label: context.tr('Nouvelle dépense'),
            icon: Icons.add,
            onPressed: _another,
          ),
        ],
      ),
    );
  }
}

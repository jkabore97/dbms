import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/courier/courier_dossier.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart' show Routes;
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_mark.dart';
import '../courier/courier_words.dart';

/// « Livreurs à valider » › one dossier (112): the selfie beside the
/// identity document, the vehicle, the quartiers and the hours, the number
/// and whether WhatsApp proved it, the charter, the history — and the
/// three answers: « Approuver », « Refuser » with a ready reason (the step
/// to redo reopens for the applicant, the rest is kept), « Demander une
/// nouvelle photo ». Each is journaled with its « Annuler » and rings the
/// applicant.
///
/// The photos come from the uploads Worker's courier route, which asks
/// Postgres whether this person is a platform admin before every byte;
/// they are held by this page only while it is open.
class CourierReviewScreen extends StatefulWidget {
  const CourierReviewScreen({
    super.key,
    required this.userId,
    required this.dossier,
    required this.files,
  });

  final String userId;
  final CourierDossierRepository dossier;
  final CourierFiles files;

  @override
  State<CourierReviewScreen> createState() => _CourierReviewScreenState();
}

/// The ready reasons, and the steps each one reopens by default.
const _reasons = <String, List<String>>{
  'blurry': ['selfie'],
  'unreadable': ['id'],
  'face': ['selfie', 'id'],
  'missing': [],
  'other': [],
};

/// The steps the platform may send back (the charter is never redone).
const _fixable = ['zone', 'hours', 'vehicle', 'selfie', 'id', 'phone'];

class _CourierReviewScreenState extends State<CourierReviewScreen> {
  CourierDossier? _d;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.dossier.dossier(widget.userId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _decide(String decision, {String? reason, List<String>? steps, String? note}) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('Décision enregistrée. Le livreur est prévenu.');
    final undoLabel = context.tr('Annuler');
    final undone = context.tr('Décision annulée.');
    setState(() => _busy = true);
    try {
      final id = await widget.dossier.decide(widget.userId, decision, reason: reason, steps: steps, note: note);
      await _load();
      messenger.showSnackBar(SnackBar(
        content: Text(done),
        action: id == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () async {
                  try {
                    await widget.dossier.undo(id);
                    messenger.showSnackBar(SnackBar(content: Text(undone)));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
                  }
                  if (mounted) await _load();
                },
              ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refuse() async {
    final answer = await showModalBottomSheet<(String, List<String>, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RefuseSheet(),
    );
    if (answer == null) return;
    await _decide('refuse', reason: answer.$1, steps: answer.$2, note: answer.$3);
  }

  Future<void> _askPhoto() async {
    final which = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(context.tr('Quelle photo refaire ?'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              key: const Key('review-photo-selfie'),
              leading: const Icon(Icons.face_outlined),
              title: Text(context.tr('Le selfie')),
              onTap: () => Navigator.of(sheet).pop('selfie'),
            ),
            ListTile(
              key: const Key('review-photo-id'),
              leading: const Icon(Icons.credit_card_outlined),
              title: Text(context.tr('La pièce d\'identité')),
              onTap: () => Navigator.of(sheet).pop('id'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (which == null) return;
    await _decide('new_photo', reason: which);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // Opened from a link (a bell, a bookmark), nothing is under it: the
        // arrow goes to the couriers. Pushed from the list, the usual back.
        leading: GoRouter.maybeOf(context)?.canPop() ?? true
            ? null
            : IconButton(
                key: const Key('review-back'),
                tooltip: context.tr('Livreurs'),
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(Routes.consoleCouriers),
              ),
        title: Text(d?.name ?? context.tr('Dossier livreur')),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: d != null && d.status == 'pending' && !d.isApprovedCourier
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                key: const Key('review-refuse'),
                                onPressed: _busy ? null : _refuse,
                                child: Text(context.tr('Refuser')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                key: const Key('review-approve'),
                                onPressed: _busy ? null : () => _decide('approve'),
                                child: Text(context.tr('Approuver')),
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          key: const Key('review-new-photo'),
                          onPressed: _busy ? null : _askPhoto,
                          child: Text(context.tr('Demander une nouvelle photo')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                ]),
              ),
            )
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, box) {
                    final wide = box.maxWidth >= 900;
                    final parts = [
                      'selfie',
                      'id_front',
                      'id_back',
                      if (d.photos['licence'] != null || d.asksLicence) 'licence',
                    ];
                    final across = wide ? parts.length : 2;
                    final tile = (box.maxWidth.clamp(0, 1100) - 32 - (across - 1) * 12) / across;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        _StatusLine(d: d),
                        const SizedBox(height: 12),
                        // The selfie beside the document: the comparison the
                        // platform makes before anything else.
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final part in parts)
                              SizedBox(
                                width: tile,
                                child: _PrivatePhoto(
                                  key: Key('review-photo-$part'),
                                  label: courierPartLabel(context, part),
                                  photoKey: d.photos[part],
                                  files: widget.files,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        KajCard(
                          child: Column(
                            children: [
                              _Fact(Icons.badge_outlined, courierStepLabel(context, 'id'),
                                  courierIdLabel(context, d.idKind)),
                              _Fact(courierVehicleIcon(d.vehicle), courierStepLabel(context, 'vehicle'),
                                  courierVehicleLine(context, d)),
                              _Fact(Icons.place_outlined, courierStepLabel(context, 'zone'),
                                  '${d.city ?? '—'} · ${d.zones.join(', ')}'),
                              _Fact(Icons.schedule, courierStepLabel(context, 'hours'),
                                  courierHoursLine(context, d)),
                              _Fact(
                                d.phoneVerified ? Icons.verified_outlined : Icons.phone_outlined,
                                courierStepLabel(context, 'phone'),
                                '${d.phone ?? '—'} · ${d.phoneVerified ? context.tr('vérifié sur WhatsApp') : context.tr('non vérifié')}',
                              ),
                              if (d.payoutNumber != null)
                                _Fact(Icons.account_balance_wallet_outlined, context.tr('Mobile Money'),
                                    d.payoutNumber!),
                              _Fact(
                                Icons.handshake_outlined,
                                courierStepLabel(context, 'charter'),
                                d.charterAt == null
                                    ? '—'
                                    : context.tr('Acceptée (version {v}) le {date}', {
                                        'v': d.charterVersion,
                                        'date': courierDate(context, d.charterAt!),
                                      }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(context.tr('Historique'),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        CourierTimeline(
                          events: d.timeline,
                          now: d.status == 'pending' ? context.tr('En cours d\'examen') : null,
                          ink: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr('Ces photos sont privées : seule la plateforme les voit. Après un refus que le livreur ne renvoie pas, elles ne sont plus jamais montrées au bout de 30 jours, et sont effacées la fois suivante où la liste des livreurs est ouverte.'),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.d});

  final CourierDossier d;

  @override
  Widget build(BuildContext context) {
    final (text, color) = d.isSuspended
        ? (context.tr('Suspendu'), maraBrown)
        : d.isApprovedCourier
            ? (context.tr('Approuvé : livreur Mara'), maraGreen)
            : switch (d.status) {
                'pending' => (context.tr('À valider'), maraCaramel),
                'refused' => (
                    context.tr('À corriger par le livreur : {reason}',
                        {'reason': courierReasonLabel(context, d.refusal?.reason)}),
                    maraBrown
                  ),
                _ => (context.tr('Brouillon'), maraGrey),
              };
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [text, if (d.sentAt != null) context.tr('envoyée le {date}', {'date': courierDate(context, d.sentAt!)})]
                .join(' · '),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      subtitle: Text(value, style: theme.textTheme.bodyLarge),
    );
  }
}

/// A dossier photo, fetched for this page only; a tap opens it large.
class _PrivatePhoto extends StatefulWidget {
  const _PrivatePhoto({super.key, required this.label, required this.photoKey, required this.files});

  final String label;
  final String? photoKey;
  final CourierFiles files;

  @override
  State<_PrivatePhoto> createState() => _PrivatePhotoState();
}

class _PrivatePhotoState extends State<_PrivatePhoto> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final key = widget.photoKey;
    if (key == null) return;
    try {
      final bytes = await widget.files.photo(key);
      if (mounted) setState(() => _bytes = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = e is CourierFileException ? context.tr(e.message) : describeError(e));
    }
  }

  void _open() {
    final bytes = _bytes;
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (dialog) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
                child: InteractiveViewer(
                    maxScale: 6,
                    child: Center(
                        child: Image.memory(bytes,
                            errorBuilder: (_, _, _) => Text(context.tr('Aperçu impossible ici'),
                                style: const TextStyle(color: Colors.white)))))),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: context.tr('Fermer'),
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(dialog).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _bytes == null ? null : _open,
              child: widget.photoKey == null
                  ? Center(child: Text(context.tr('Aucune photo'), textAlign: TextAlign.center))
                  : _bytes != null
                      ? Image.memory(_bytes!,
                          fit: BoxFit.cover,
                          // A format this browser cannot draw (a HEIC on the
                          // web): said, never a crash.
                          errorBuilder: (_, _, _) => Center(
                              child: Text(context.tr('Aperçu impossible ici'), textAlign: TextAlign.center)))
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                              ),
                            )
                          : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(widget.label, style: theme.textTheme.labelLarge),
      ],
    );
  }
}

/// « Refuser »: a ready reason, the steps to redo (preset by the reason),
/// a word if needed.
class _RefuseSheet extends StatefulWidget {
  const _RefuseSheet();

  @override
  State<_RefuseSheet> createState() => _RefuseSheetState();
}

class _RefuseSheetState extends State<_RefuseSheet> {
  String? _reason;
  final _steps = <String>{};
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _ready =>
      _reason != null && _steps.isNotEmpty && (_reason != 'other' || _note.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('Pourquoi refuser ?'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _reasons.keys)
                    ChoiceChip(
                      key: Key('refuse-$r'),
                      label: Text(courierReasonLabel(context, r)),
                      selectedColor: maraDeep,
                      checkmarkColor: maraPaper,
                      labelStyle: TextStyle(color: _reason == r ? maraPaper : null),
                      selected: _reason == r,
                      onSelected: (_) => setState(() {
                        _reason = r;
                        _steps
                          ..clear()
                          ..addAll(_reasons[r]!);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(context.tr('À refaire par le livreur'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _fixable)
                    FilterChip(
                      key: Key('refuse-step-$s'),
                      label: Text(courierStepLabel(context, s)),
                      selectedColor: maraDeep,
                      checkmarkColor: maraPaper,
                      labelStyle: TextStyle(color: _steps.contains(s) ? maraPaper : null),
                      selected: _steps.contains(s),
                      onSelected: (on) => setState(() => on ? _steps.add(s) : _steps.remove(s)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('refuse-note'),
                controller: _note,
                maxLength: 300,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _reason == 'other'
                      ? context.tr('Ce qui ne va pas')
                      : context.tr('Un mot pour le livreur (facultatif)'),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('refuse-send'),
                  onPressed: _ready
                      ? () => Navigator.of(context).pop((
                            _reason!,
                            [..._steps],
                            _note.text.trim().isEmpty ? null : _note.text.trim(),
                          ))
                      : null,
                  child: Text(context.tr('Renvoyer au livreur')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

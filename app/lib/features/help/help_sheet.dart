import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/errors.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/mara_sheet.dart';
import '../../core/update/update_check.dart' show buildSha, installStore;
import '../capture/capture_action.dart';
import '../common/keyboard_sheet.dart';
import 'help_words.dart';

/// « Un formateur vous aide » (mockup 2): what it is about (seven chips,
/// the kind's own), a few words (optional), a photo (optional, the app's
/// own picker), how to be helped (WhatsApp, a call, « Venir me voir »).
/// Sent, the request is the business's one active request; the trainers
/// are rung by the server (133). Out of the hours it is kept, and the
/// sheet says when somebody will answer.
Future<HelpRequest?> showHelpSheet(
  BuildContext context, {
  required OrgSummary org,
  required HelpState state,
  required HelpRepository help,
  String? screen,
  CaptureRepository? capture,
}) => showMaraSheet<HelpRequest>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => HelpRequestSheet(
    org: org,
    state: state,
    help: help,
    screen: screen,
    capture: capture ?? AppScope.maybeOf(context)?.capture,
    phone: AppScope.maybeOf(context)?.session.identity?.phone,
  ),
);

class HelpRequestSheet extends StatefulWidget {
  const HelpRequestSheet({
    super.key,
    required this.org,
    required this.state,
    required this.help,
    this.screen,
    this.capture,
    this.phone,
  });

  final OrgSummary org;
  final HelpState state;
  final HelpRepository help;
  final String? screen;
  final CaptureRepository? capture;

  /// The account's number, when it has one: asked for otherwise.
  final String? phone;

  @override
  State<HelpRequestSheet> createState() => _HelpRequestSheetState();
}

class _HelpRequestSheetState extends State<HelpRequestSheet> {
  String? _subject;
  String _contact = 'whatsapp';
  final _message = TextEditingController();
  final _phone = TextEditingController();
  PickedPhoto? _photo;
  bool _askPhone = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.phone?.trim() ?? '';
    _askPhone = p.isEmpty;
    _phone.text = p;
  }

  @override
  void dispose() {
    _message.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await CaptureAction.pick(
      context,
      orgId: widget.org.id,
      photos: widget.capture,
    );
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  /// The photo as a document of the business: one chosen in « Photos » is
  /// itself; a new one is sent now (no signal: the request goes without).
  Future<String?> _photoId() async {
    final photo = _photo;
    final capture = widget.capture;
    if (photo == null || capture == null) return null;
    final from = photo.from;
    if (from != null) return from.id;
    return capture.capture(
      orgId: widget.org.id,
      bytes: photo.bytes,
      contentType: photo.contentType,
      kind: 'help',
      caption: context.tr('Demande d\'aide'),
    );
  }

  Future<void> _send() async {
    final subject = _subject;
    if (subject == null) {
      setState(() => _error = context.tr('Choisissez de quoi il s\'agit.'));
      return;
    }
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8 || digits.length > 15) {
      setState(() {
        _askPhone = true;
        _error = context.tr(
          'Un numéro où vous joindre, avec l\'indicatif (par exemple 22670000000).',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      String? photoId;
      try {
        photoId = await _photoId();
      } catch (_) {
        photoId = null; // The request matters more than its picture.
      }
      final r = await widget.help.create(
        orgId: widget.org.id,
        subject: subject,
        contact: _contact,
        message: _message.text.trim().isEmpty ? null : _message.text.trim(),
        phone: digits,
        photoDocumentId: photoId,
        context: {
          if (widget.screen != null) 'screen': widget.screen!,
          'version': buildSha.isEmpty
              ? 'dev'
              : buildSha.substring(0, buildSha.length.clamp(0, 12)),
          'platform': kIsWeb
              ? 'web'
              : installStore.isNotEmpty
              ? '${defaultTargetPlatform.name} $installStore'
              : defaultTargetPlatform.name,
        },
      );
      if (mounted) nav.pop(r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.state;
    final hours = helpHoursText(s.hours.open, s.hours.close);
    final out = !s.hours.inHours && s.hours.nextOpen != null;
    final none = s.left <= 0;
    final label = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
    );

    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null || none)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error ??
                  context.tr(
                    'Vous avez fait toutes vos demandes pour aujourd\'hui. Réessayez demain, ou écrivez à Mara.',
                  ),
              key: const Key('help-sheet-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        SizedBox(
          height: 52,
          child: FilledButton(
            key: const Key('help-send'),
            style: FilledButton.styleFrom(
              backgroundColor: maraCaramel,
              foregroundColor: helpCaramelInk,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
            onPressed: _busy || none ? null : _send,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.tr('Envoyer la demande'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'Mara joint l\'écran, l\'entreprise et la version de l\'app.',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return KeyboardSheet(
      footer: footer,
      children: [
        Text(
          context.tr('Un formateur vous aide'),
          key: const Key('help-sheet-title'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          out
              ? '${helpWhenAnswered(context, s.hours.nextOpen!)}. '
                    '${context.tr('Votre demande est gardée.')}'
              : context.tr('Réponse en quelques minutes, {hours}', {
                  'hours': hours,
                }),
          key: const Key('help-sheet-when'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(context.tr('C\'est à propos de…'), style: label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final subject in helpSubjectsFor(widget.org.profile))
              ChoiceChip(
                key: Key('help-subject-$subject'),
                label: Text(helpSubjectLabel(context, subject)),
                selected: _subject == subject,
                showCheckmark: false,
                // The mockup's: the chosen one black, its words white.
                selectedColor: maraBlack,
                labelStyle: TextStyle(
                  color: _subject == subject ? Colors.white : null,
                  fontWeight: _subject == subject ? FontWeight.w700 : null,
                ),
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _subject = subject),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('help-message'),
          controller: _message,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.tr(
              '« Je n\'arrive pas à annuler une vente… » (facultatif)',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (widget.capture != null && widget.capture!.isConfigured)
          Align(
            alignment: Alignment.centerLeft,
            child: _photo == null
                ? TextButton.icon(
                    key: const Key('help-photo'),
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(context.tr('Ajouter une photo (facultatif)')),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _photo!.bytes,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(context.tr('Photo jointe')),
                      IconButton(
                        tooltip: context.tr('Retirer la photo'),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _photo = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
          ),
        const SizedBox(height: 10),
        Text(context.tr('On vous contacte par'), style: label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in helpContacts)
              ChoiceChip(
                key: Key('help-contact-$c'),
                avatar: Icon(
                  helpContactIcon(c),
                  size: 18,
                  color: _contact == c ? Colors.white : null,
                ),
                label: Text(helpContactLabel(context, c)),
                selected: _contact == c,
                showCheckmark: false,
                selectedColor: maraBlack,
                labelStyle: TextStyle(
                  color: _contact == c ? Colors.white : null,
                  fontWeight: _contact == c ? FontWeight.w700 : null,
                ),
                onSelected: _busy ? null : (_) => setState(() => _contact = c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_askPhone)
          TextField(
            key: const Key('help-phone'),
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: context.tr('Votre numéro (avec l\'indicatif)'),
              hintText: '226 70 00 00 00',
              border: const OutlineInputBorder(),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('On vous joint au {phone}', {
                    'phone': _phone.text,
                  }),
                  key: const Key('help-phone-known'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _askPhone = true),
                child: Text(context.tr('Changer')),
              ),
            ],
          ),
      ],
    );
  }
}

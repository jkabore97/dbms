import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/phone/country_codes.dart' show displayPhone;
import '../../core/update/update_check.dart' show buildSha, installStore;
import '../capture/capture_action.dart';
import '../common/step_flow.dart';
import 'help_words.dart';

/// « Demander un formateur » (143): Mara Pro's request, one question at a
/// time on the app's StepFlow (115) — the same for a shop, a farm and an
/// association, only the subjects their own:
///
///   1. « C'est à propos de quoi ? » — the kind's subjects (helpSubjectsFor);
///   2. « Décrivez ce qu'il vous faut » — a few words (500 at most) and,
///      if wanted, a photo or a screenshot through the app's picker,
///      uploaded as a document of the business (133's photo_document_id);
///   3. « Comment vous aider ? » — WhatsApp, a call or a visit, and the
///      number to reach (the account's, or asked);
///   4. « Quand ? » — now, or a day and an hour chosen (Ouagadougou's
///      clock), in the next week;
///   5. the summary, « Envoyer la demande ».
///
/// Several requests may be open at once (138); the day's limit is the
/// server's. On a database before 138 a subject it does not know and the
/// chosen time go in the words (HelpRepository.create).
class HelpRequestFlow extends StatefulWidget {
  const HelpRequestFlow({
    super.key,
    required this.org,
    required this.state,
    required this.help,
    this.screen,
    this.capture,
    this.phone,
    this.store,
    this.now,
  });

  final OrgSummary org;
  final HelpState state;
  final HelpRepository help;
  final String? screen;
  final CaptureRepository? capture;

  /// The account's number, when it has one: asked for otherwise.
  final String? phone;

  /// Where the draft is kept (tests).
  final FlowStore? store;

  /// The clock (tests).
  final DateTime Function()? now;

  /// Opens the flow over the pages; true once a request was sent.
  static Future<bool?> open(
    BuildContext context, {
    required OrgSummary org,
    required HelpState state,
    required HelpRepository help,
    String? screen,
    CaptureRepository? capture,
    FlowStore? store,
  }) {
    final scope = AppScope.maybeOf(context);
    return StepFlow.push(
      context,
      HelpRequestFlow(
        org: org,
        state: state,
        help: help,
        screen: screen,
        capture: capture ?? scope?.capture,
        phone: scope?.session.identity?.phone,
        store: store,
      ),
    );
  }

  @override
  State<HelpRequestFlow> createState() => _HelpRequestFlowState();
}

class _HelpRequestFlowState extends State<HelpRequestFlow> {
  String? _subject;
  final _message = TextEditingController();
  PickedPhoto? _photo;
  String _contact = 'whatsapp';
  final _phone = TextEditingController();
  bool _askPhone = false;

  /// « Maintenant » (false) or a time chosen (true).
  bool _later = false;

  /// The day chosen, 0 today … 6, and the hour, on Ouagadougou's clock.
  int _day = 0;
  int? _hour;

  HelpRequest? _sent;
  final _flow = StepFlowController();

  static const _maxWords = 500;

  DateTime _now() => (widget.now ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    final p = widget.phone?.replaceAll(RegExp(r'\D'), '') ?? '';
    _askPhone = p.length < 8;
    _phone.text = p;
  }

  @override
  void dispose() {
    _message.dispose();
    _phone.dispose();
    super.dispose();
  }

  Map<String, Object?> _save() => {
    'subject': _subject,
    'message': _message.text,
    'contact': _contact,
    'later': _later,
    'day': _day,
    'hour': _hour,
  };

  void _restore(Map<String, Object?> a) {
    setState(() {
      final s = a['subject'];
      _subject = s is String && helpSubjectsFor(widget.org.profile).contains(s)
          ? s
          : null;
      _message.text = '${a['message'] ?? ''}';
      final c = a['contact'];
      _contact = c is String && helpContacts.contains(c) ? c : 'whatsapp';
      _later = a['later'] == true;
      final d = a['day'];
      _day = d is int && d >= 0 && d <= 6 ? d : 0;
      final h = a['hour'];
      _hour = h is int ? h : null;
    });
  }

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  bool get _phoneOk => _digits.length >= 8 && _digits.length <= 15;

  /// The hours that may still be chosen on day [_day]: 7:00 to 20:00 —
  /// within the help hours when they are narrower (a time outside them
  /// would only wait for the opening) — and today only those to come.
  List<int> _hoursFor(int day) {
    final now = _now();
    final hours = widget.state.hours;
    var first = hours.open > 7 ? hours.open : 7;
    var last = hours.close - 1 < 20 ? hours.close - 1 : 20;
    if (first > last) (first, last) = (7, 20);
    return [
      for (var h = first; h <= last; h++)
        if (day > 0 || h > now.hour) h,
    ];
  }

  /// The day [d] from today, on Ouagadougou's clock (UTC all year).
  DateTime _dayAt(int d) {
    final n = _now();
    return DateTime.utc(n.year, n.month, n.day + d);
  }

  DateTime? get _when {
    if (!_later || _hour == null) return null;
    final d = _dayAt(_day);
    return DateTime.utc(d.year, d.month, d.day, _hour!);
  }

  bool get _whenOk => !_later || (_hour != null && _hoursFor(_day).contains(_hour));

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

  bool _photoLost = false;

  Future<bool> _send() async {
    final subject = _subject!;
    String? photoId;
    _photoLost = false;
    try {
      photoId = await _photoId();
    } catch (_) {
      // The request matters more than its picture.
      photoId = null;
      _photoLost = _photo != null;
    }
    if (!mounted) return false;
    final when = _when;
    final r = await widget.help.create(
      orgId: widget.org.id,
      subject: subject,
      contact: _contact,
      message: _message.text.trim().isEmpty ? null : _message.text.trim(),
      phone: _digits,
      photoDocumentId: photoId,
      preferredAt: when,
      subjectWords: helpSubjectLabel(context, subject, profile: widget.org.profile),
      whenWords: when == null ? null : context.tr('Souhaité {when}', {'when': helpWhen(context, when, now: _now())}),
      server: widget.state.version,
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
    _sent = r;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.org.profile;
    final none = widget.state.left <= 0 && widget.state.installed;
    return StepFlow(
      title: context.tr('Demander un formateur'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
        key: 'help:${widget.org.id}',
        save: _save,
        restore: _restore,
      ),
      summaryTitle: context.tr('Vérifiez et envoyez'),
      saveLabel: context.tr('Envoyer la demande'),
      steps: [
        FlowStep(
          id: 'subject',
          title: context.tr('C\'est à propos de quoi ?'),
          isValid: () => _subject != null,
          builder: (_) => FlowChoice<String>(
            options: [
              for (final s in helpSubjectsFor(profile))
                FlowOption(
                  s,
                  helpSubjectLabel(context, s, profile: profile),
                  icon: helpSubjectIcon(s),
                ),
            ],
            value: _subject,
            onChanged: (v) {
              setState(() => _subject = v);
              _flow.keep();
            },
          ),
        ),
        FlowStep(
          id: 'describe',
          title: context.tr('Décrivez ce qu\'il vous faut'),
          help: context.tr(
            'Quelques mots suffisent. Une photo ou une capture d\'écran aide aussi.',
          ),
          isValid: () =>
              (_message.text.trim().isNotEmpty || _photo != null) &&
              _message.text.runes.length <= _maxWords,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('help-message'),
                controller: _message,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: _maxWords,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.tr(
                    '« Je n\'arrive pas à annuler une vente… »',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.capture != null && widget.capture!.isConfigured)
                _photo == null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('help-photo'),
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(
                            context.tr('Ajouter une photo ou une capture'),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _photo!.bytes,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(context.tr('Photo jointe'))),
                          IconButton(
                            key: const Key('help-photo-remove'),
                            tooltip: context.tr('Retirer la photo'),
                            onPressed: () => setState(() => _photo = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
            ],
          ),
        ),
        FlowStep(
          id: 'how',
          title: context.tr('Comment vous aider ?'),
          isValid: () => _phoneOk,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  FlowOption(
                    'whatsapp',
                    context.tr('Sur WhatsApp'),
                    icon: helpContactIcon('whatsapp'),
                    detail: context.tr('Le formateur vous écrit'),
                  ),
                  FlowOption(
                    'call',
                    context.tr('Par un appel'),
                    icon: helpContactIcon('call'),
                    detail: context.tr('Le formateur vous appelle'),
                  ),
                  FlowOption(
                    'visit',
                    context.tr('Par une visite'),
                    icon: helpContactIcon('visit'),
                    detail: context.tr('Le formateur vient vous voir'),
                  ),
                ],
                value: _contact,
                onChanged: (v) {
                  setState(() => _contact = v);
                  _flow.keep();
                },
              ),
              if (_askPhone)
                TextField(
                  key: const Key('help-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr('Votre numéro (avec l\'indicatif)'),
                    hintText: '+226 70 00 00 00',
                    border: const OutlineInputBorder(),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('On vous joint au {phone}', {
                          'phone': displayPhone(_phone.text),
                        }),
                        key: const Key('help-phone-known'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _askPhone = true),
                      child: Text(context.tr('Changer')),
                    ),
                  ],
                ),
            ],
          ),
        ),
        FlowStep(
          id: 'when',
          title: context.tr('Quand ?'),
          help: context.tr('Heure de Ouagadougou.'),
          isValid: () => _whenOk,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<bool>(
                options: [
                  FlowOption(
                    false,
                    context.tr('Maintenant'),
                    icon: Icons.bolt_outlined,
                    detail: context.tr('Dès qu\'un formateur est libre'),
                  ),
                  FlowOption(
                    true,
                    context.tr('À un moment choisi'),
                    icon: Icons.event_outlined,
                  ),
                ],
                value: _later,
                onChanged: (v) {
                  setState(() {
                    _later = v;
                    if (v && _hoursFor(_day).isEmpty) _day = 1;
                  });
                  _flow.keep();
                },
              ),
              if (_later) ...[
                Text(
                  context.tr('Le jour'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var d = 0; d <= 6; d++)
                      if (_hoursFor(d).isNotEmpty)
                        ChoiceChip(
                          key: Key('help-day-$d'),
                          label: Text(_dayLabel(context, d)),
                          selected: _day == d,
                          onSelected: (_) {
                            setState(() {
                              _day = d;
                              if (_hour != null && !_hoursFor(d).contains(_hour)) {
                                _hour = null;
                              }
                            });
                            _flow.keep();
                          },
                        ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  context.tr('L\'heure'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final h in _hoursFor(_day))
                      ChoiceChip(
                        key: Key('help-hour-$h'),
                        label: Text('${h.toString().padLeft(2, '0')}:00'),
                        selected: _hour == h,
                        onSelected: (_) {
                          setState(() => _hour = h);
                          _flow.keep();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(
            context.tr('À propos de'),
            _subject == null
                ? '—'
                : helpSubjectLabel(context, _subject!, profile: profile),
            step: 'subject',
            bold: true,
          ),
          FlowSummaryRow(
            context.tr('Ce qu\'il vous faut'),
            _message.text.trim().isEmpty ? '—' : _message.text.trim(),
            step: 'describe',
          ),
          if (_photo != null)
            FlowSummaryRow(context.tr('Photo'), context.tr('Oui'), step: 'describe'),
          FlowSummaryRow(
            context.tr('Comment'),
            helpContactLabel(context, _contact),
            step: 'how',
          ),
          // Its own line: a number is never cut in two.
          FlowSummaryRow(context.tr('Numéro'), displayPhone(_digits), step: 'how'),
          FlowSummaryRow(
            context.tr('Quand'),
            _when == null
                ? context.tr('Maintenant')
                : helpWhen(context, _when!, now: _now()),
            step: 'when',
          ),
        ],
        footer: Text(
          none
              ? context.tr(
                  'Vous avez fait toutes vos demandes pour aujourd\'hui. Réessayez demain, ou écrivez à Marakaj.',
                )
              : context.tr(
                  'Marakaj joint l\'écran, l\'entreprise et la version de l\'app.',
                ),
          key: const Key('help-flow-footer'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: none ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      onSave: _send,
      done: (_) {
        final r = _sent;
        final queued = r != null && r.waitingForHours;
        return FlowDone(
          message: context.tr('Demande d\'aide envoyée'),
          details: Text(
            [
              if (r?.preferredAt != null)
                context.tr('Un formateur vous contactera {when}.', {
                  'when': helpWhen(context, r!.preferredAt!, now: _now()),
                })
              else if (queued)
                '${helpWhenAnswered(context, r.routedAt!, now: _now())}.'
              else
                context.tr('Un formateur va prendre votre demande.'),
              if (_photoLost)
                context.tr('La photo n\'a pas pu être envoyée ; la demande est partie sans elle.'),
            ].join('\n'),
            key: const Key('help-flow-done-when'),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  String _dayLabel(BuildContext context, int d) {
    if (d == 0) return context.tr('Aujourd\'hui');
    if (d == 1) return context.tr('Demain');
    final day = _dayAt(d);
    final names = [
      context.tr('lun.'),
      context.tr('mar.'),
      context.tr('mer.'),
      context.tr('jeu.'),
      context.tr('ven.'),
      context.tr('sam.'),
      context.tr('dim.'),
    ];
    return '${names[day.weekday - 1]} ${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/mara_mark.dart';
import 'help_words.dart';

/// `/formateur` (batch 136, mockup 5): « Demandes d'aide », the trainer's
/// inbox — on their account, wherever they are: Compte, the bar of a
/// business they help, the bell and the WhatsApp alert's « Ouvrir dans
/// Mara » all lead here.
///
///   * the open requests, oldest first: « Je m'en occupe » — the first
///     trainer wins, the others are told (133's help_take);
///   * their own in progress: WhatsApp, a call, « Marquer résolue » with a
///     note; for a visit, « Accepter la visite » or « Proposer un appel »;
///     once the owner allowed it, « Ouvrir l'activité (lecture seule) »;
///   * the last week's done, in grey;
///   * « En service » / « Hors service » — off duty, no ring for new ones.
///
/// [focus] (the bell's `?demande=`) is drawn first, outlined.
class TrainerInboxScreen extends StatefulWidget {
  const TrainerInboxScreen({super.key, this.help, this.focus});

  final HelpRepository? help;
  final String? focus;

  @override
  State<TrainerInboxScreen> createState() => _TrainerInboxScreenState();
}

class _TrainerInboxScreenState extends State<TrainerInboxScreen> {
  late HelpRepository _help;
  HelpInbox? _inbox;
  String? _error;
  final _busy = <String>{};
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _help =
          widget.help ?? HelpRepository(AppScope.maybeOf(context)?.auth.client);
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!_help.isConfigured) {
      setState(() => _inbox = HelpInbox.none);
      return;
    }
    try {
      final i = await _help.inbox();
      if (mounted) {
        setState(() {
          _inbox = i;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _act(
    String id,
    Future<void> Function() f, {
    String? done,
  }) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await f();
      if (done != null) messenger?.showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(describeError(e))));
      await _load();
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<String?> _note(String title, String hint, String action) =>
      showDialog<String>(
        context: context,
        builder: (d) {
          final c = TextEditingController();
          return AlertDialog(
            title: Text(title),
            content: TextField(
              key: const Key('help-note'),
              controller: c,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d),
                child: Text(d.tr('Annuler')),
              ),
              FilledButton(
                key: const Key('help-note-ok'),
                onPressed: () => Navigator.pop(d, c.text.trim()),
                child: Text(action),
              ),
            ],
          );
        },
      );

  Future<void> _resolve(InboxRequest r) async {
    final note = await _note(
      context.tr('Marquer résolue'),
      context.tr('Ce qui a été fait (facultatif)'),
      context.tr('Marquer résolue'),
    );
    if (note == null || !mounted) return;
    await _act(
      r.id,
      () => _help.resolve(r.id, note: note.isEmpty ? null : note),
      done: context.tr('Demande marquée résolue : l\'entreprise confirme.'),
    );
  }

  Future<void> _visit(InboxRequest r, String answer) async {
    final note = await _note(
      answer == 'accepted'
          ? context.tr('Accepter la visite')
          : context.tr('Proposer un appel'),
      answer == 'accepted'
          ? context.tr('Quand passez-vous ? (facultatif)')
          : context.tr('Quand appelez-vous ? (facultatif)'),
      context.tr('Envoyer'),
    );
    if (note == null || !mounted) return;
    await _act(
      r.id,
      () => _help.answerVisit(r.id, answer, note: note.isEmpty ? null : note),
    );
  }

  Future<void> _openActivity(InboxRequest r) async {
    final scope = AppScope.maybeOf(context);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final orgId = await _help.openAccess(r.id);
      await scope?.session.refresh(force: true);
      router.go(Routes.org(orgId));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(describeError(e))));
      await _load();
    }
  }

  Future<void> _launch(Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = context.tr('Impossible d\'ouvrir ce lien sur cet appareil.');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inbox = _inbox;
    final rows = [...?inbox?.requests];
    final focus = widget.focus;
    if (focus != null) {
      final i = rows.indexWhere((r) => r.id == focus);
      if (i > 0) rows.insert(0, rows.removeAt(i));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Demandes d\'aide')),
        actions: [
          if (inbox != null && inbox.trainer && !inbox.admin)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                key: const Key('help-duty'),
                onPressed: () =>
                    _act('duty', () => _help.setOnDuty(!inbox.onDuty)),
                icon: Icon(
                  Icons.circle,
                  size: 10,
                  color: inbox.onDuty ? helpGreen : maraGrey,
                ),
                label: Text(
                  inbox.onDuty
                      ? context.tr('En service')
                      : context.tr('Hors service'),
                  style: TextStyle(
                    color: inbox.onDuty
                        ? helpGreen
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          bellRoom,
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (inbox == null && _error == null)
              const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: Text(context.tr('Réessayer')),
                  ),
                ),
              ),
            if (inbox != null && !inbox.trainer)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  context.tr('Réservé à l\'équipe de formation de Mara.'),
                  key: const Key('help-inbox-not-trainer'),
                  textAlign: TextAlign.center,
                ),
              ),
            if (inbox != null && inbox.trainer && !inbox.inHours)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  context.tr(
                    'Hors des heures d\'aide ({hours}) : les nouvelles demandes arrivent à l\'ouverture.',
                    {
                      'hours': helpHoursText(
                        inbox.hours.open,
                        inbox.hours.close,
                      ),
                    },
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (inbox != null && inbox.trainer && rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  context.tr('Aucune demande pour l\'instant.'),
                  key: const Key('help-inbox-empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            for (final r in rows)
              _RequestCard(
                key: Key('help-inbox-${r.id}'),
                r: r,
                focused: r.id == focus,
                busy: _busy.contains(r.id),
                onTake: () => _act(
                  r.id,
                  () => _help.take(r.id),
                  done: context.tr(
                    'C\'est à vous : l\'entreprise est prévenue.',
                  ),
                ),
                onResolve: () => _resolve(r),
                onVisit: (a) => _visit(r, a),
                onWhatsApp: r.phone == null
                    ? null
                    : () => _launch(Uri.parse('https://wa.me/${r.phone}')),
                onCall: r.phone == null
                    ? null
                    : () => _launch(Uri(scheme: 'tel', path: '+${r.phone}')),
                onOpen: () => _openActivity(r),
              ),
            if (inbox != null && inbox.trainer)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  context.tr(
                    'Accès en lecture seule à l\'entreprise le temps de la demande (48 h au plus), quand son propriétaire l\'autorise.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    super.key,
    required this.r,
    required this.focused,
    required this.busy,
    required this.onTake,
    required this.onResolve,
    required this.onVisit,
    required this.onOpen,
    this.onWhatsApp,
    this.onCall,
  });

  final InboxRequest r;
  final bool focused;
  final bool busy;
  final VoidCallback onTake;
  final VoidCallback onResolve;
  final void Function(String answer) onVisit;
  final VoidCallback onOpen;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = r.done;
    final (String badge, Color fg, Color bg) = r.open
        ? (
            r.escalated && !r.assigned
                ? context.tr('REMONTÉE · {age}', {
                    'age': helpAge(context, r.createdAt),
                  })
                : context.tr('NOUVELLE · {age}', {
                    'age': helpAge(context, r.createdAt),
                  }),
            helpRed,
            helpRedSoft,
          )
        : r.inProgress
        ? (context.tr('MOI · en cours'), helpGreen, helpGreenSoft)
        : r.status == 'taken'
        ? (
            context.tr('{name} · en cours', {'name': r.takenBy ?? ''}),
            maraDeep,
            theme.colorScheme.surfaceContainerHighest,
          )
        : (
            r.status == 'resolved'
                ? context.tr('Résolue, à confirmer')
                : context.tr('Fermée'),
            theme.colorScheme.onSurfaceVariant,
            theme.colorScheme.surfaceContainerHighest,
          );
    final ink = done ? theme.colorScheme.onSurfaceVariant : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused ? maraCaramel : theme.colorScheme.outlineVariant,
          width: focused ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Tag(badge, fg, bg),
              _Tag(
                helpSubjectLabel(context, r.subject, profile: r.profile),
                theme.colorScheme.onSurface,
                theme.colorScheme.surfaceContainerHighest,
              ),
              if (r.contact == 'visit')
                _Tag(
                  context.tr('Visite'),
                  maraBrown,
                  maraCaramel.withValues(alpha: 0.2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.city == null ? r.org : '${r.org} · ${r.city}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          Text(
            [
              helpKindLabel(context, r.profile),
              if (r.requester != null) r.requester!,
              if (r.screen != null)
                context.tr('écran {screen}', {'screen': r.screen!}),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (r.message != null) ...[
            const SizedBox(height: 6),
            Text(
              '« ${r.message} »',
              style: theme.textTheme.bodyMedium?.copyWith(color: ink),
            ),
          ],
          // 143: the time the business chose (« Quand ? »).
          if (r.preferredAt != null) ...[
            const SizedBox(height: 6),
            Text(
              context.tr('Souhaité {when}', {
                'when': helpWhen(context, r.preferredAt!),
              }),
              key: Key('help-inbox-when-${r.id}'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ],
          if (done && r.rating != null) ...[
            const SizedBox(height: 6),
            Icon(
              r.rating! > 0
                  ? Icons.thumb_up_outlined
                  : Icons.thumb_down_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
          if (r.open) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: Key('help-take-${r.id}'),
                style: FilledButton.styleFrom(
                  backgroundColor: maraBlack,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onPressed: busy ? null : onTake,
                child: Text(
                  context.tr('Je m\'en occupe'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
          if (r.inProgress) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onWhatsApp != null)
                  FilledButton.tonalIcon(
                    key: Key('help-wa-${r.id}'),
                    style: FilledButton.styleFrom(
                      backgroundColor: helpGreenSoft,
                      foregroundColor: helpGreen,
                    ),
                    onPressed: onWhatsApp,
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: Text(context.tr('WhatsApp')),
                  ),
                if (onCall != null)
                  FilledButton.tonalIcon(
                    key: Key('help-tel-${r.id}'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: Text(context.tr('Appeler')),
                  ),
                OutlinedButton.icon(
                  key: Key('help-resolve-${r.id}'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: busy ? null : onResolve,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(context.tr('Marquer résolue')),
                ),
              ],
            ),
            if (r.contact == 'visit' && r.visitAnswer == null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: Key('help-visit-yes-${r.id}'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: busy ? null : () => onVisit('accepted'),
                    icon: const Icon(Icons.directions_walk_outlined, size: 18),
                    label: Text(context.tr('Accepter la visite')),
                  ),
                  OutlinedButton.icon(
                    key: Key('help-visit-call-${r.id}'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: busy ? null : () => onVisit('call_instead'),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: Text(context.tr('Proposer un appel')),
                  ),
                ],
              ),
            ] else if (r.visitAnswer != null) ...[
              const SizedBox(height: 6),
              Text(
                r.visitAnswer == 'accepted'
                    ? context.tr('Visite acceptée')
                    : context.tr('Appel proposé à la place de la visite'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            if (r.accessUntil != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: Key('help-open-${r.id}'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(context.tr('Ouvrir l\'activité (lecture seule)')),
                ),
              )
            else if (!r.member)
              Text(
                context.tr(
                  'Pour voir l\'activité, son propriétaire vous ouvre un accès en lecture seule depuis sa demande.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.fg, this.bg);

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12),
    ),
  );
}

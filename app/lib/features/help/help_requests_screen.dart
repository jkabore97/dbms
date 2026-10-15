import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/mara_mark.dart';
import 'help_button.dart';
import 'help_request_flow.dart';
import 'help_words.dart';

/// `/o/<id>/aide/demandes` — « Mes demandes » (143): every request of the
/// business with where it is (reçue → prise en charge par … → résolue),
/// the active ones first, and « Nouvelle demande » — several may be open
/// at once (138), up to the day's limit. A row opens its status page
/// ([HelpRequestScreen]); `?demande=<id>` (a bell) opens that one at once.
/// The same for a shop, a farm and an association.
class HelpRequestsScreen extends StatefulWidget {
  const HelpRequestsScreen({
    super.key,
    required this.org,
    this.help,
    this.focus,
  });

  final OrgSummary org;
  final HelpRepository? help;

  /// A request to open at once (a bell's).
  final String? focus;

  @override
  State<HelpRequestsScreen> createState() => _HelpRequestsScreenState();
}

class _HelpRequestsScreenState extends State<HelpRequestsScreen> {
  late HelpRepository _help;
  HelpState? _state;
  String? _error;
  late String? _focus = widget.focus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null && _error == null) {
      _help =
          widget.help ?? HelpRepository(AppScope.maybeOf(context)?.auth.client);
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!_help.isConfigured) {
      setState(() => _state = HelpState.missing);
      return;
    }
    try {
      final s = await _help.state(widget.org.id);
      if (!mounted) return;
      setState(() {
        _state = s;
        _error = null;
      });
      final f = _focus;
      _focus = null;
      if (f != null) {
        for (final r in s.requests) {
          if (r.id == f) {
            await _openRequest(r);
            break;
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _openRequest(HelpRequest r) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HelpRequestScreen(
          org: widget.org,
          help: _help,
          request: r,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _new() async {
    final s = _state;
    if (s == null) return;
    final sent = await HelpRequestFlow.open(
      context,
      org: widget.org,
      state: s,
      help: _help,
      screen: context.tr('Mes demandes'),
    );
    if (sent == true) HelpButton.changed.value++;
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _state;
    final none = s != null && s.installed && s.left <= 0;
    // A server before 138 holds one active request per business (133's
    // index): a second would only be refused.
    final oneOnly = s != null && s.version < 138 && s.active.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Mes demandes')),
        actions: const [bellRoom],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (s == null && _error == null)
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
            if (s != null && s.trainers) ...[
              FilledButton.icon(
                key: const Key('help-new-request'),
                style: FilledButton.styleFrom(
                  backgroundColor: maraCaramel,
                  foregroundColor: helpCaramelInk,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: none || oneOnly ? null : _new,
                icon: const Icon(Icons.add),
                label: Text(
                  context.tr('Nouvelle demande'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (oneOnly && !none)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(
                      'Une demande d\'aide est déjà en cours pour cette entreprise.',
                    ),
                    key: const Key('help-one-active'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (none)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(
                      'Vous avez fait toutes vos demandes pour aujourd\'hui. Réessayez demain, ou écrivez à Marakaj.',
                    ),
                    key: const Key('help-none-left'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            if (s != null && s.requests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  context.tr('Aucune demande pour l\'instant.'),
                  key: const Key('help-requests-empty'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            if (s != null)
              for (final r in s.requests)
                _RequestRow(
                  key: Key('help-request-${r.id}'),
                  request: r,
                  profile: widget.org.profile,
                  onTap: () => _openRequest(r),
                ),
          ],
        ),
      ),
    );
  }
}

/// Where a request is, in a few words: « Reçue », « Prise en charge par
/// … », « Résolue », « Fermée ».
String helpStatusText(BuildContext context, HelpRequest r) => switch (r.status) {
  'taken' => context.tr('Prise en charge par {name}', {
    'name': r.trainer?.firstName ?? 'Marakaj',
  }),
  'resolved' => context.tr('Résolue'),
  'closed' => context.tr('Fermée'),
  _ =>
    r.waitingForHours && r.routedAt != null
        ? context.tr('Reçue · {when}', {
            'when': helpWhenAnswered(context, r.routedAt!),
          })
        : context.tr('Reçue'),
};

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    super.key,
    required this.request,
    required this.profile,
    required this.onTap,
  });

  final HelpRequest request;
  final String profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final (Color dot, Color soft) = switch (r.status) {
      'taken' => (helpGreen, helpGreenSoft),
      'resolved' => (helpGreen, helpGreenSoft),
      'closed' => (
        theme.colorScheme.outline,
        theme.colorScheme.surfaceContainerHighest,
      ),
      _ => (helpRed, helpRedSoft),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Chip(helpSubjectLabel(context, r.subject, profile: profile)),
                          Text(
                            '${_date(r.createdAt)} · ${helpClock(r.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (r.message != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          r.message!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        key: Key('help-request-status-${r.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: dot),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                helpStatusText(context, r),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _date(DateTime t) {
    final u = t.toUtc();
    return '${u.day.toString().padLeft(2, '0')}/${u.month.toString().padLeft(2, '0')}';
  }
}

/// One request (136's status, mockup 3): where it is (reçue → prise en
/// charge par … → résolue), the trainer's WhatsApp and call once taken,
/// « Autoriser l'accès 48 h » when the trainer is not of the business (the
/// owner or an admin only), « C'est réglé ? » with « Oui, merci » / « Pas
/// encore », and « Fermer la demande » with a 👍 / 👎.
class HelpRequestScreen extends StatefulWidget {
  const HelpRequestScreen({
    super.key,
    required this.org,
    required this.help,
    required this.request,
  });

  final OrgSummary org;
  final HelpRepository help;
  final HelpRequest request;

  @override
  State<HelpRequestScreen> createState() => _HelpRequestScreenState();
}

class _HelpRequestScreenState extends State<HelpRequestScreen> {
  late HelpRequest _r = widget.request;
  bool _busy = false;

  HelpRepository get _help => widget.help;

  /// The request as the server says it now.
  Future<void> _reload() async {
    try {
      final s = await _help.state(widget.org.id);
      for (final r in s.requests) {
        if (r.id == _r.id && mounted) setState(() => _r = r);
      }
    } catch (_) {}
  }

  Future<void> _act(Future<Object?> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final v = await f();
      if (v is HelpRequest && v.id == _r.id && mounted) setState(() => _r = v);
      HelpButton.changed.value++;
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _r;
    final t = r.trainer;
    final canAct = (r.mine || widget.org.isAdmin) && r.status != 'closed';
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Ma demande d\'aide')),
        actions: const [bellRoom],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _Box(
            key: const Key('help-request-card'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _ProBadge(),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _Chip(
                        helpSubjectLabel(
                          context,
                          r.subject,
                          profile: widget.org.profile,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(
                            helpContactIcon(r.contact),
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              helpContactLabel(context, r.contact),
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (r.message != null) ...[
                  const SizedBox(height: 10),
                  Text('« ${r.message} »', style: theme.textTheme.bodyLarge),
                ],
                if (r.hasPhoto) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.photo_outlined, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('Photo jointe'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                if (r.preferredAt != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          context.tr('Souhaité {when}', {
                            'when': helpWhen(context, r.preferredAt!),
                          }),
                          key: const Key('help-request-when'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Step(
            key: const Key('help-step-received'),
            done: true,
            n: 1,
            title: context.tr('Demande reçue'),
            sub: helpClock(r.createdAt),
          ),
          if (t != null)
            _Step(
              key: const Key('help-step-taken'),
              done: true,
              n: 2,
              title: context.tr(
                '{name}, de l\'équipe de formation, s\'en occupe',
                {'name': t.firstName},
              ),
              sub:
                  '${r.takenAt == null ? '' : '${helpClock(r.takenAt!)} · '}${_howText(context, r)}',
            )
          else
            _Step(
              key: const Key('help-step-waiting'),
              done: false,
              n: 2,
              title: context.tr('En attente d\'un formateur'),
              sub: r.status == 'closed'
                  ? null
                  : r.waitingForHours
                  ? helpWhenAnswered(context, r.routedAt!)
                  : r.escalated
                  ? context.tr('Toute l\'équipe de formation est prévenue.')
                  : context.tr('Un formateur va prendre votre demande.'),
            ),
          _Step(
            key: const Key('help-step-resolved'),
            done: r.status == 'resolved' || (r.status == 'closed' && t != null),
            n: 3,
            title: context.tr('Résolu'),
            sub: r.status == 'resolved' || r.status == 'closed'
                ? r.resolutionNote
                : null,
          ),
          const SizedBox(height: 12),
          if (t != null && t.phone != null && r.status != 'closed') ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('help-write-trainer'),
                    onPressed: () =>
                        _open(Uri.parse('https://wa.me/${t.phone}')),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(
                      context.tr('Écrire à {name}', {'name': t.firstName}),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('help-call-trainer'),
                    onPressed: () =>
                        _open(Uri(scheme: 'tel', path: '+${t.phone}')),
                    icon: const Icon(Icons.call_outlined),
                    label: Text(
                      context.tr('Appeler {name}', {'name': t.firstName}),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (r.access?.live ?? false)
            _Box(
              key: const Key('help-access-live'),
              colour: helpGreenSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.visibility_outlined, color: helpGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(
                            '{name} voit votre activité en lecture seule jusqu\'à {time}',
                            {
                              'name': t?.firstName ?? '',
                              'time': _until(context, r.access!.expiresAt),
                            },
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Rien ne peut être changé. L\'accès s\'arrête tout seul, ou quand vous le retirez.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (widget.org.isAdmin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const Key('help-revoke'),
                        onPressed: _busy
                            ? null
                            : () => _act(() async {
                                await _help.revokeAccess(r.id);
                                return null;
                              }),
                        child: Text(context.tr('Retirer l\'accès')),
                      ),
                    ),
                ],
              ),
            )
          else if (r.canGrant && widget.org.isAdmin)
            _Box(
              key: const Key('help-grant-card'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      '{name} n\'est pas de votre entreprise. Pour qu\'on vous guide, vous pouvez lui ouvrir votre activité en lecture seule, 48 h au plus.',
                      {'name': t!.firstName},
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    key: const Key('help-grant'),
                    onPressed: _busy ? null : () => _grant(r, t.firstName),
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(context.tr('Autoriser l\'accès 48 h')),
                  ),
                ],
              ),
            ),
          if (r.status == 'resolved' && canAct) ...[
            const SizedBox(height: 12),
            _Box(
              key: const Key('help-settled'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('C\'est réglé ?'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        key: const Key('help-yes'),
                        style: FilledButton.styleFrom(
                          backgroundColor: helpGreenSoft,
                          foregroundColor: helpGreen,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _act(() => _help.close(r.id, rating: 1)),
                        icon: const Icon(Icons.thumb_up_outlined),
                        label: Text(context.tr('Oui, merci')),
                      ),
                      FilledButton.tonalIcon(
                        key: const Key('help-not-yet'),
                        style: FilledButton.styleFrom(
                          backgroundColor: helpRedSoft,
                          foregroundColor: helpRed,
                        ),
                        onPressed: _busy
                            ? null
                            : () => _act(() => _help.reopen(r.id)),
                        icon: const Icon(Icons.thumb_down_outlined),
                        label: Text(context.tr('Pas encore')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (canAct) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                key: const Key('help-close'),
                onPressed: _busy ? null : () => _close(r),
                child: Text(context.tr('Fermer la demande')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _howText(BuildContext context, HelpRequest r) {
    if (r.contact == 'visit') {
      return switch (r.visitAnswer) {
        'accepted' => context.tr('viendra vous voir'),
        'call_instead' => context.tr('vous propose plutôt un appel'),
        _ => context.tr('a reçu votre demande de visite'),
      };
    }
    return r.contact == 'call'
        ? context.tr('vous appelle')
        : context.tr('vous écrit sur WhatsApp');
  }

  String _until(BuildContext context, DateTime t) {
    final now = DateTime.now().toUtc();
    final u = t.toUtc();
    final sameDay =
        u.year == now.year && u.month == now.month && u.day == now.day;
    final tomorrow = DateTime.utc(now.year, now.month, now.day + 1);
    final isTomorrow =
        u.year == tomorrow.year &&
        u.month == tomorrow.month &&
        u.day == tomorrow.day;
    final clock = helpClock(t);
    if (sameDay) return context.tr('{time} aujourd\'hui', {'time': clock});
    if (isTomorrow) return context.tr('demain {time}', {'time': clock});
    return '${u.day.toString().padLeft(2, '0')}/${u.month.toString().padLeft(2, '0')} $clock';
  }

  Future<void> _grant(HelpRequest r, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(d.tr('Autoriser l\'accès 48 h ?')),
        content: Text(
          d.tr(
            '{name} pourra voir votre activité (ventes, stock, comptes) sans rien pouvoir changer, pendant 48 heures au plus. Vous pouvez retirer l\'accès à tout moment ; il s\'arrête aussi quand vous fermez la demande.',
            {'name': name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(d.tr('Annuler')),
          ),
          FilledButton(
            key: const Key('help-grant-confirm'),
            onPressed: () => Navigator.pop(d, true),
            child: Text(d.tr('Autoriser')),
          ),
        ],
      ),
    );
    if (ok == true) await _act(() => _help.grantAccess(r.id));
  }

  Future<void> _close(HelpRequest r) async {
    final rated = r.trainer != null;
    final choice = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(d.tr('Fermer la demande ?')),
        content: Text(
          rated
              ? d.tr('L\'aide vous a-t-elle servi ?')
              : d.tr(
                  'Personne ne l\'a encore prise. Vous pourrez en faire une autre.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(d.tr('Annuler')),
          ),
          if (rated) ...[
            IconButton(
              key: const Key('help-rate-down'),
              tooltip: d.tr('Pas satisfait'),
              onPressed: () => Navigator.pop(d, -1),
              icon: const Icon(Icons.thumb_down_outlined),
            ),
            IconButton(
              key: const Key('help-rate-up'),
              tooltip: d.tr('Satisfait'),
              onPressed: () => Navigator.pop(d, 1),
              icon: const Icon(Icons.thumb_up_outlined),
            ),
          ] else
            FilledButton(
              key: const Key('help-close-confirm'),
              onPressed: () => Navigator.pop(d, 0),
              child: Text(d.tr('Fermer')),
            ),
        ],
      ),
    );
    if (choice == null) return;
    await _act(() => _help.close(r.id, rating: choice == 0 ? null : choice));
  }

  Future<void> _open(Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = context.tr('Impossible d\'ouvrir ce lien sur cet appareil.');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(failed)));
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child, this.colour});

  final Widget child;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:
          colour ??
          Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: maraBlack,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Text(
      'PRO',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 11,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

/// One step of « where is my help » (mockup 3): a green tick once done,
/// the step's number in grey before.
class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.done,
    required this.n,
    required this.title,
    this.sub,
  });

  final bool done;
  final int n;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done
                  ? helpGreen
                  : theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: done
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    '$n',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: done ? null : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (sub != null && sub!.isNotEmpty)
                  Text(
                    sub!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/notify/bell_room.dart';
import '../account/support.dart';
import '../shopper/report_sheet.dart';
import 'help_button.dart';
import 'help_sheet.dart';
import 'help_words.dart';

/// `/o/<id>/aide` (batch 136): the business's help.
///
///   * Pro (mockup 3) — « Ma demande d'aide »: the request, where it is
///     (reçue → prise en charge par Awa → résolue), the trainer's WhatsApp
///     and call buttons once taken, « Autoriser l'accès 48 h » when the
///     trainer is not of the business (the owner or an admin only), « C'est
///     réglé ? » with « Oui, merci » / « Pas encore », and « Fermer la
///     demande » with a 👍 / 👎 (the app's thumb icons). No request: the
///     « Besoin d'aide » button and the hours.
///   * Free, or a database without 133 (mockup 7) — « Aide »: the FAQ, the
///     guides (Le Chemin), « Écrire à Mara » (126's WhatsApp and e-mail,
///     « réponse sous 48 h »), « Signaler un problème », and a discreet
///     « Avec Mara Pro ».
///
/// The same for a shop, a farm and an association; only the subjects of
/// the sheet are the kind's own.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, required this.org, this.help});

  final OrgSummary org;
  final HelpRepository? help;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  late HelpRepository _help;
  HelpState? _state;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null && _error == null) {
      _help =
          widget.help ?? HelpRepository(AppScope.maybeOf(context)?.auth.client);
      Support.warm(AppScope.maybeOf(context)?.auth.client);
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
      if (mounted) {
        setState(() {
          _state = s;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _act(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
      HelpButton.changed.value++;
      await _load();
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

  Future<void> _ask() async {
    final s = _state;
    if (s == null) return;
    final r = await showHelpSheet(
      context,
      org: widget.org,
      state: s,
      help: _help,
      screen: 'Aide',
    );
    if (r != null) {
      HelpButton.changed.value++;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final pro = s?.trainers ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          pro ? context.tr('Ma demande d\'aide') : context.tr('Aide'),
        ),
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
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: Text(context.tr('Réessayer')),
                  ),
                ),
              ),
            if (s != null && pro) ..._pro(context, s),
            if (s != null && !pro) ..._free(context, s),
          ],
        ),
      ),
    );
  }

  // -- Pro --------------------------------------------------------------------

  List<Widget> _pro(BuildContext context, HelpState s) {
    final r = s.request;
    if (r == null) return _noRequest(context, s);
    final theme = Theme.of(context);
    final t = r.trainer;
    final canAct = r.mine || widget.org.isAdmin;
    return [
      _Box(
        key: const Key('help-request-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _ProBadge(),
                const SizedBox(width: 8),
                _Chip(helpSubjectLabel(context, r.subject)),
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
          title: context.tr('{name}, de l\'équipe de formation, s\'en occupe', {
            'name': t.firstName,
          }),
          sub:
              '${r.takenAt == null ? '' : '${helpClock(r.takenAt!)} · '}${_howText(context, r)}',
        )
      else
        _Step(
          key: const Key('help-step-waiting'),
          done: false,
          n: 2,
          title: context.tr('En attente d\'un formateur'),
          sub: r.waitingForHours
              ? helpWhenAnswered(context, r.routedAt!)
              : r.escalated
              ? context.tr('Toute l\'équipe de formation est prévenue.')
              : context.tr('Un formateur va prendre votre demande.'),
        ),
      _Step(
        key: const Key('help-step-resolved'),
        done: r.status == 'resolved',
        n: 3,
        title: context.tr('Résolu'),
        sub: r.status == 'resolved' ? r.resolutionNote : null,
      ),
      const SizedBox(height: 12),
      if (t != null && t.phone != null) ...[
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('help-write-trainer'),
                onPressed: () => _open(Uri.parse('https://wa.me/${t.phone}')),
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
                onPressed: () => _open(Uri(scheme: 'tel', path: '+${t.phone}')),
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
                        : () => _act(() => _help.revokeAccess(r.id)),
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
    ];
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

  List<Widget> _noRequest(BuildContext context, HelpState s) {
    final theme = Theme.of(context);
    final out = !s.hours.inHours && s.hours.nextOpen != null;
    return [
      _Box(
        key: const Key('help-no-request'),
        colour: maraCaramel.withValues(alpha: 0.18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.support, color: helpCaramelInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('Un formateur de Mara vous aide'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              out
                  ? '${helpWhenAnswered(context, s.hours.nextOpen!)}.'
                  : context.tr('Réponse en quelques minutes, {hours}', {
                      'hours': helpHoursText(s.hours.open, s.hours.close),
                    }),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('help-ask'),
              style: FilledButton.styleFrom(
                backgroundColor: maraCaramel,
                foregroundColor: helpCaramelInk,
              ),
              onPressed: _ask,
              icon: const Icon(Icons.support),
              label: Text(context.tr('Besoin d\'aide')),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ..._basics(context, showPro: false),
    ];
  }

  // -- Free -------------------------------------------------------------------

  List<Widget> _free(BuildContext context, HelpState s) =>
      _basics(context, showPro: !widget.org.isPro && widget.org.isAdmin);

  List<Widget> _basics(BuildContext context, {required bool showPro}) {
    final theme = Theme.of(context);
    return [
      _Tile(
        key: const Key('help-faq'),
        title: context.tr('Questions fréquentes'),
        sub: context.tr(
          'Ajouter un article · Partager ma vitrine · Annuler une vente…',
        ),
        onTap: () => context.push(Routes.faq),
      ),
      if (widget.org.isAdmin)
        _Tile(
          key: const Key('help-guides'),
          title: context.tr('Guides — Le Chemin'),
          sub: context.tr('Pas à pas, dans l\'app'),
          onTap: () => context.push(Routes.inside(widget.org.id, 'chemin')),
        ),
      ValueListenableBuilder<SupportContacts>(
        valueListenable: Support.contacts,
        builder: (context, c, _) => _Box(
          key: const Key('help-write-mara'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Écrire à Mara'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                c.whatsapp != null
                    ? context.tr('WhatsApp ou e-mail · réponse sous 48 h')
                    : context.tr('Par e-mail · réponse sous 48 h'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (c.whatsapp != null)
                    FilledButton.icon(
                      key: const Key('help-mara-whatsapp'),
                      onPressed: () => Support.openWhatsApp(context),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: Text(context.tr('WhatsApp')),
                    ),
                  OutlinedButton.icon(
                    key: const Key('help-mara-email'),
                    onPressed: () => Support.openEmail(context),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: Text(context.tr('E-mail')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 4),
      OutlinedButton(
        key: const Key('help-report'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        onPressed: () => showReportSheet(
          context,
          shopper: ShopperRepository(AppScope.maybeOf(context)?.auth.client),
          slug: widget.org.slug,
        ),
        child: Text(
          context.tr('Signaler un problème'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      if (showPro) ...[
        const SizedBox(height: 16),
        Container(
          key: const Key('help-pro-invite'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: maraDeep,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.support, color: maraCaramel),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('Avec Mara Pro'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('un formateur vous aide en quelques minutes.'),
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('help-discover-pro'),
                  style: FilledButton.styleFrom(
                    backgroundColor: maraCaramel,
                    foregroundColor: helpCaramelInk,
                  ),
                  onPressed: () =>
                      context.push(Routes.inside(widget.org.id, 'kaj-pro')),
                  child: Text(
                    context.tr('Découvrir Pro'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
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

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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

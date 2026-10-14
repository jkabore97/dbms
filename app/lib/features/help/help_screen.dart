import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/notify/bell_room.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../account/support.dart';
import '../shopper/report_sheet.dart';
import 'help_button.dart';
import 'help_contact.dart';
import 'help_request_flow.dart';
import 'help_words.dart';

/// `/o/<id>/aide` — the business's « Aide » (batch 143, the owner's
/// decisions; 136 before it). The same for a shop, a farm and an
/// association.
///
///   * Basic (a free business, or a database without 133): « WhatsApp »
///     with « Réponse sous 48 h » — once a day on this device a word about
///     Pro first (HelpContact) —, « Questions fréquentes » (its banner for
///     Pro), the guides, the e-mail, « Signaler un problème ». No « 24/7 ».
///   * Pro: « WhatsApp » with its « 24/7 », straight to the chat;
///     « Demander un formateur » — the step-by-step request, or, once the
///     business has some, its requests (`aide/demandes`) with « Nouvelle
///     demande »; « Mes demandes »; the questions without a banner; the
///     guides, the e-mail, « Signaler un problème ».
///
/// Every WhatsApp names the business, its kind, its plan and its reference
/// (helpWhatsAppText); every e-mail its name and reference.
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null && _error == null) {
      _help =
          widget.help ?? HelpRepository(AppScope.maybeOf(context)?.auth.client);
      Support.warm(AppScope.maybeOf(context)?.auth.client);
      unawaited(HelpContact.warm(context));
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

  /// Pro for the help: what the server says, else the cached plan (no
  /// signal, or no 133).
  bool get _pro {
    final s = _state;
    return s != null && s.installed && s.available ? s.pro : widget.org.isPro;
  }

  String get _page => context.tr('Aide');

  Future<void> _askTrainer() async {
    final s = _state;
    if (s == null) return;
    if (s.requests.isNotEmpty) {
      await context.push(Routes.inside(widget.org.id, 'aide/demandes'));
    } else {
      final sent = await HelpRequestFlow.open(
        context,
        org: widget.org,
        state: s,
        help: _help,
        screen: _page,
      );
      if (sent == true) HelpButton.changed.value++;
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final pro = _pro;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Aide')), actions: const [bellRoom]),
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
            _writeToMara(context, pro),
            if (pro && (s?.trainers ?? false)) ..._trainer(context, s!),
            // Whatever the plan: a business back on Basic still reads,
            // closes and takes back the access of the requests it made on
            // Pro (only a new one needs Pro).
            if (s != null && s.installed && s.available && s.requests.isNotEmpty)
              _myRequests(context, s),
            _Tile(
              key: const Key('help-faq'),
              icon: Icons.help_outline,
              title: context.tr('Questions fréquentes'),
              sub: context.tr(
                'Ajouter un article · Partager ma vitrine · Annuler une vente…',
              ),
              onTap: () =>
                  context.push('${Routes.faq}?org=${widget.org.id}'),
            ),
            if (widget.org.isAdmin)
              _Tile(
                key: const Key('help-guides'),
                icon: Icons.route_outlined,
                title: context.tr('Guides — Le Chemin'),
                sub: context.tr('Pas à pas, dans l\'app'),
                onTap: () =>
                    context.push(Routes.inside(widget.org.id, 'chemin')),
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
                shopper: ShopperRepository(
                  AppScope.maybeOf(context)?.auth.client,
                ),
                slug: widget.org.slug,
              ),
              child: Text(
                context.tr('Signaler un problème'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// « Écrire à Mara »: WhatsApp (Basic « Réponse sous 48 h », Pro
  /// « 24/7 ») when the platform set a number, the e-mail always.
  Widget _writeToMara(BuildContext context, bool pro) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<SupportContacts>(
      valueListenable: Support.contacts,
      builder: (context, c, _) => _Box(
        key: const Key('help-write-mara'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('Écrire à Mara'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              // « 24/7 » only where the WhatsApp is (no number set: the
              // e-mail alone, which promises its 48 h).
              pro && c.whatsapp != null
                  ? context.tr('WhatsApp 24 h/24, 7 j/7, avec Mara Pro')
                  : c.whatsapp != null
                  ? context.tr('WhatsApp ou e-mail · réponse sous 48 h')
                  : context.tr('Par e-mail · réponse sous 48 h'),
              key: const Key('help-write-when'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (c.whatsapp != null) ...[
              _WhatsAppButton(
                pro: pro,
                onTap: () => HelpContact.whatsApp(
                  context,
                  widget.org,
                  pro: pro,
                  canUpgrade: _state?.canUpgrade,
                  page: _page,
                  ref: _state?.ref,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('help-mara-email'),
                onPressed: () => HelpContact.email(
                  context,
                  widget.org,
                  pro: pro,
                  ref: _state?.ref,
                ),
                icon: const Icon(Icons.mail_outline, size: 18),
                label: Text(context.tr('Écrire un e-mail')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pro: « Demander un formateur » and the business's requests.
  List<Widget> _trainer(BuildContext context, HelpState s) {
    final theme = Theme.of(context);
    final out = !s.hours.inHours && s.hours.nextOpen != null;
    return [
      const SizedBox(height: 8),
      _Box(
        key: const Key('help-trainer-card'),
        colour: maraCaramel.withValues(alpha: 0.18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  // Open the whole day (0–24): Pro's promise, beside its
                  // « 24/7 » — never Basic's 48 h, nor « 00:00–24:00 ».
                  : s.hours.open <= 0 && s.hours.close >= 24
                  ? context.tr('Réponse rapide, 24 h/24')
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
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _askTrainer,
              icon: const Icon(Icons.support_agent),
              label: Text(
                context.tr('Demander un formateur'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
    ];
  }

  /// « Mes demandes »: the business's requests, Pro or not any more.
  Widget _myRequests(BuildContext context, HelpState s) {
    final active = s.active.length;
    return _Tile(
      key: const Key('help-my-requests'),
      icon: Icons.list_alt_outlined,
      title: context.tr('Mes demandes'),
      sub: active > 0
          ? context.tr('{n} en cours', {'n': active})
          : context.tr('Aucune en cours'),
      onTap: () async {
        await context.push(Routes.inside(widget.org.id, 'aide/demandes'));
        if (mounted) await _load();
      },
    );
  }
}

/// WhatsApp, with what it promises on its face: « Réponse sous 48 h » on
/// Basic, the « 24/7 » badge on Pro.
class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({required this.pro, required this.onTap});

  final bool pro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
    key: const Key('help-mara-whatsapp'),
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF1F7A4D),
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    ),
    onPressed: onTap,
    child: Row(
      children: [
        const Icon(Icons.chat_outlined, size: 20),
        const SizedBox(width: 10),
        // Never cut inside the word (320 px, large text): it shrinks.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              context.tr('WhatsApp'),
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: pro
              ? Container(
                  key: const Key('help-247'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: maraCaramel,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '24/7',
                    style: TextStyle(
                      color: helpCaramelInk,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                )
              : Text(
                  context.tr('Réponse sous 48 h'),
                  key: const Key('help-48h'),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
        ),
      ],
    ),
  );
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child, this.colour});

  final Widget child;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
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
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
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
                Icon(icon, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/help/help_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/mara_mark.dart';
import 'help_words.dart';

/// « Aide · Console » (batch 136, mockup 6): Clients › Formateurs › Aide in
/// the command center (`/console/formateurs/aide`), the platform admin's
/// view of the training team at work — next to the roster and the
/// assignments it is built on (038).
///
///   * four numbers: open requests, the average first answer (in open
///     minutes, 7 days), resolved in 7 days, the share of 👍 (30 days);
///   * what waits, the late ones first (« sans réponse depuis 30 min »);
///   * each trainer: on or off duty, how many in progress, resolved;
///   * WhatsApp: on, off (no template set — the bell alone), refused by
///     Meta (the template is not approved yet), waiting (the Worker has not
///     carried anything for 5 minutes).
class HelpConsoleScreen extends StatefulWidget {
  const HelpConsoleScreen({super.key, this.help});

  final HelpRepository? help;

  @override
  State<HelpConsoleScreen> createState() => _HelpConsoleScreenState();
}

class _HelpConsoleScreenState extends State<HelpConsoleScreen> {
  late HelpRepository _help;
  HelpConsole? _c;
  bool _loaded = false;
  String? _error;
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
    try {
      final c = _help.isConfigured ? await _help.console() : null;
      if (mounted) {
        setState(() {
          _c = c;
          _loaded = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeError(e);
          _loaded = true;
        });
      }
    }
  }

  String _waText(BuildContext context, HelpConsole c) => switch (c.whatsapp) {
    'on' => context.tr('WhatsApp : actif (modèle « {t} »)', {'t': c.template}),
    'template' => context.tr(
      'WhatsApp : le modèle « {t} » n\'est pas encore approuvé par Meta — les formateurs sont prévenus dans l\'app.',
      {'t': c.template},
    ),
    'failing' => context.tr(
      'WhatsApp : les derniers envois ont échoué — les formateurs sont prévenus dans l\'app.',
    ),
    'waiting' => context.tr(
      'WhatsApp : en attente — le Worker n\'a rien envoyé depuis 5 minutes.',
    ),
    'unknown' => context.tr('WhatsApp : modèle « {t} », pas encore d\'envoi.', {
      't': c.template,
    }),
    _ => context.tr(
      'WhatsApp : désactivé (aucun modèle dans Réglages) — les formateurs sont prévenus dans l\'app.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _c;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Aide · Console')),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          bellRoom,
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!_loaded) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(title: Text(_error!)),
              ),
            if (_loaded && c == null && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  context.tr(
                    'La base de données n\'a pas encore l\'aide Pro (migration 133).',
                  ),
                  key: const Key('help-console-missing'),
                  textAlign: TextAlign.center,
                ),
              ),
            if (c != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      key: const Key('help-console-open'),
                      big: '${c.open}',
                      small: context.tr('ouvertes'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Tile(
                      key: const Key('help-console-avg'),
                      big: c.avgMinutes == null
                          ? '—'
                          : context.tr('{n} min', {'n': c.avgMinutes}),
                      small: context.tr('réponse moyenne'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      key: const Key('help-console-resolved'),
                      big: '${c.resolved7}',
                      small: context.tr('résolues · 7 j'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Tile(
                      key: const Key('help-console-up'),
                      big: c.upPercent == null ? '—' : '${c.upPercent} %',
                      smallIcon: Icons.thumb_up_outlined,
                      small: context.tr('satisfaits · 30 j'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final w in c.late)
                Container(
                  key: Key('help-console-late-${w.id}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: helpRedSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: helpRed,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              context.tr('Sans réponse depuis {n} min', {
                                'n': w.minutes,
                              }),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${w.org} · ${helpSubjectLabel(context, w.subject, profile: w.profile)}'
                        '${w.escalated ? ' · ${context.tr('remontée à vous')}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: Key('help-console-take-${w.id}'),
                          onPressed: () => context.push(
                            '${Routes.trainerInbox}?demande=${w.id}',
                          ),
                          child: Text(context.tr('Voir dans les demandes')),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                key: const Key('help-console-whatsapp'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.whatsapp == 'on'
                      ? helpGreenSoft
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_outlined,
                      color: c.whatsapp == 'on'
                          ? helpGreen
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _waText(context, c),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('Formateurs'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              if (c.trainers.isEmpty)
                Text(
                  context.tr('Aucun formateur pour le moment'),
                  style: theme.textTheme.bodySmall,
                ),
              for (final t in c.trainers)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  // The name on its line, its state under it (a long
                  // name never squeezes the numbers).
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            t.onDuty ? Icons.circle : Icons.circle_outlined,
                            size: 10,
                            color: t.onDuty ? helpGreen : maraGrey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [
                                t.onDuty
                                    ? context.tr('en service')
                                    : context.tr('hors service'),
                                if (t.taken > 0)
                                  context.tr('{n} en cours', {'n': t.taken}),
                                context.tr('{n} résolues · 7 j', {
                                  'n': t.resolved7,
                                }),
                              ].join(' · '),
                              style: TextStyle(
                                color: t.onDuty
                                    ? helpGreen
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 143: the number they are reached on is their
                      // profile's — none, nobody can ring them.
                      if (!t.hasPhone)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            context.tr('Pas de numéro sur son profil'),
                            key: Key('help-console-no-phone-${t.userId ?? t.name}'),
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Un formateur se choisit dans Personnes : ouvrez la fiche de la personne, « Formateur Mara ».',
                ),
                key: const Key('help-console-how-trainers'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr(
                  'Heures de l\'aide Pro : {hours}, heure de Ouagadougou — Réglages › Notifications.',
                  {'hours': helpHoursText(c.hours.open, c.hours.close)},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.big,
    required this.small,
    this.smallIcon,
  });

  final String big;
  final String small;
  final IconData? smallIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            big,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Row(
            children: [
              if (smallIcon != null) ...[
                Icon(
                  smallIcon,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  small,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

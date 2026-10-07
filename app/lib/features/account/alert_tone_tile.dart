import 'package:flutter/material.dart';

import '../../core/db/local_db.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/alert_tone.dart';

/// Compte › Préférences › Sons des notifications: folded, one line until
/// opened. Inside, the buzz on or off and the four tones, each with a play
/// button — a tone is chosen by ear, not by name.
class AlertToneTile extends StatelessWidget {
  const AlertToneTile({super.key, required this.db});

  final LocalDb db;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<AlertToneSettings>(
      valueListenable: AlertTone.settings,
      builder: (context, now, _) => ExpansionTile(
        key: const Key('compte-tones'),
        leading: const Icon(Icons.music_note_outlined),
        title: Text(context.tr('Sons des notifications')),
        subtitle: Text([
          toneLabel(context, now.tone),
          if (now.vibrate) context.tr('vibreur'),
        ].join(' · ')),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          SwitchListTile(
            key: const Key('tone-vibrate'),
            secondary: const Icon(Icons.vibration),
            title: Text(context.tr('Vibrer')),
            value: now.vibrate,
            onChanged: (on) => AlertTone.choose(db, vibrate: on),
          ),
          for (final choice in AlertTone.choices)
            ListTile(
              key: Key('tone-${choice.id}'),
              minTileHeight: 56,
              leading: Icon(
                choice.id == now.tone
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: choice.id == now.tone ? theme.colorScheme.primary : null,
              ),
              title: Text(toneLabel(context, choice.id)),
              trailing: IconButton.filledTonal(
                key: Key('tone-play-${choice.id}'),
                tooltip: context.tr('Écouter'),
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => AlertTone.preview(choice.id),
              ),
              onTap: () {
                AlertTone.choose(db, tone: choice.id);
                AlertTone.preview(choice.id);
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              context.tr('Ce son retentit quand l\'application est ouverte. Application fermée, une notification web sonne avec le son du téléphone ; sur Android, pas encore de notification application fermée.'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tone's name on screen.
String toneLabel(BuildContext context, String id) => switch (id) {
      'balafon' => context.tr('Balafon'),
      'clochette' => context.tr('Clochette'),
      'goutte' => context.tr('Goutte'),
      _ => context.tr('Carillon'),
    };

import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/notifications_repository.dart';
import '../../core/notify/push_setup.dart';

/// « Notifications » (115): this device's ring with the app closed, the
/// person's switches per type, and « M'envoyer une notification test ».
/// Opened from the bell's list, the shopper's profile, the courier's space
/// and Compte; the platform's « Tester la notification » is in the command
/// center's Réglages.
///
/// A switch off writes nothing at all — no line in the bell, no push. The
/// account's own messages (a new device, a decision on a request) have no
/// switch: they always ring.
class NotificationSettingsSheet extends StatefulWidget {
  const NotificationSettingsSheet({
    super.key,
    required this.notify,
    required this.audiences,
  });

  final NotificationsRepository notify;

  /// Whose switches are shown: 'customer', 'courier', 'shop'.
  final Set<String> audiences;

  static Future<void> open(
    BuildContext context, {
    required NotificationsRepository notify,
    required Set<String> audiences,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => NotificationSettingsSheet(notify: notify, audiences: audiences),
      );

  @override
  State<NotificationSettingsSheet> createState() => _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<NotificationSettingsSheet> {
  List<NotificationPref>? _prefs;
  bool? _pushable;
  bool? _pushOn;
  String? _busy;
  String? _said;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await widget.notify.prefs();
      final pushable = await PushSetup.available();
      final on = pushable && await PushSetup.ensure(widget.notify);
      if (!mounted) return;
      setState(() {
        _prefs = [for (final p in prefs) if (widget.audiences.contains(p.audience)) p];
        _pushable = pushable;
        _pushOn = on;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _set(NotificationPref p, bool on) async {
    setState(() => _busy = p.type);
    try {
      await widget.notify.setPref(p.type, on);
      if (!mounted) return;
      setState(() {
        _prefs = [
          for (final x in _prefs!)
            x.type == p.type
                ? NotificationPref(type: x.type, audience: x.audience, label: x.label, enabled: on)
                : x,
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _enablePush() async {
    setState(() => _busy = 'push');
    final on = await PushSetup.enable(widget.notify);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _pushOn = on;
      if (!on) {
        _said = context.tr('Les notifications sont refusées sur cet appareil. Elles s\'activent dans ses paramètres.');
      }
    });
  }

  Future<void> _test() async {
    setState(() {
      _busy = 'test';
      _said = null;
      _error = null;
    });
    try {
      final r = await widget.notify.sendTest();
      if (!mounted) return;
      setState(() => _said = r == null
          ? context.tr('Le test arrive avec la prochaine mise à jour du serveur.')
          : testOutcome(context, web: r.web, android: r.android, webhook: r.webhook));
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = _prefs;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          key: const Key('notification-settings'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(context.tr('Notifications'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_pushable == true)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_pushOn == true
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined),
                title: Text(_pushOn == true
                    ? context.tr('Cet appareil sonne même l\'application fermée')
                    : context.tr('Cet appareil ne sonne que l\'application ouverte')),
                trailing: _pushOn == true
                    ? null
                    : FilledButton.tonal(
                        key: const Key('settings-push-enable'),
                        onPressed: _busy == null ? _enablePush : null,
                        child: Text(context.tr('Activer')),
                      ),
              )
            else if (_pushable == false)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_none),
                title: Text(context.tr('Sur cet appareil, les notifications arrivent dans la cloche quand l\'application est ouverte.')),
              ),
            if (prefs == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (prefs != null && prefs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(context.tr('Ce que vous voulez entendre'),
                  style: theme.textTheme.titleSmall),
              for (final p in prefs)
                SwitchListTile(
                  key: Key('pref-${p.type}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr(p.label)),
                  value: p.enabled,
                  onChanged: _busy == null ? (on) => _set(p, on) : null,
                ),
              Text(
                context.tr('Éteint : rien n\'est écrit dans la cloche et rien ne sonne. Les messages de votre compte sonnent toujours.'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('notify-test'),
              onPressed: _busy == null ? _test : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(context.tr('M\'envoyer une notification test')),
            ),
            if (_said != null) ...[
              const SizedBox(height: 8),
              Text(_said!, key: const Key('notify-test-said')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

/// What a test answered, in words: where it went, and — to the platform —
/// whether anything wakes the push Worker.
String testOutcome(BuildContext context, {required int web, required int android, bool? webhook}) {
  final devices = web + android;
  final where = devices == 0
      ? context.tr('Envoyée dans la cloche. Aucun appareil n\'est inscrit pour sonner application fermée : touchez « Activer ».')
      : context.tr('Envoyée à {n} appareil(s) : {web} navigateur(s), {android} téléphone(s) Android.',
          {'n': devices, 'web': web, 'android': android});
  if (webhook == null) return where;
  return webhook
      ? '$where ${context.tr('Le webhook de la base est en place.')}'
      : '$where ${context.tr('Aucun webhook sur la table notifications : rien ne réveille le Worker push (README, « Push notifications »).')}';
}

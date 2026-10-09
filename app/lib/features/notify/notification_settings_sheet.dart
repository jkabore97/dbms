import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/notifications_repository.dart';
import '../../core/notify/push_client.dart';
import '../../core/notify/push_setup.dart';
import 'push_diagnostics.dart';

/// « Notifications » (115): this device's ring with the app closed, the
/// person's switches per type, and « M'envoyer une notification test ».
///
/// The ring itself is one switch, « Notifications sur ce téléphone » (122):
/// on asks the phone and registers it, off withdraws it. It says what the
/// phone's own permission says, and points to the phone's settings when
/// they block it. No tone or vibration choice of the app's own: a
/// notification rings with the phone's sound, set in the phone.
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
    this.device = const PushDevice(),
  });

  final NotificationsRepository notify;

  /// This phone's ring; a test gives its own.
  final PushDevice device;

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
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => NotificationSettingsSheet(notify: notify, audiences: audiences),
      );

  @override
  State<NotificationSettingsSheet> createState() => _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<NotificationSettingsSheet>
    with WidgetsBindingObserver {
  List<NotificationPref>? _prefs;
  bool? _pushable;
  bool? _pushOn;
  PushPermission _permission = PushPermission.prompt;
  String? _busy;
  String? _said;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the phone's settings: the switch says what they now say.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _lookAtDevice();
  }

  Future<void> _load() async {
    try {
      final prefs = await widget.notify.prefs();
      if (!mounted) return;
      setState(() =>
          _prefs = [for (final p in prefs) if (widget.audiences.contains(p.audience)) p]);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
    await _lookAtDevice();
  }

  Future<void> _lookAtDevice() async {
    try {
      final device = widget.device;
      final pushable = await device.available();
      final on = pushable && await device.ensure(widget.notify);
      final permission =
          pushable ? await device.permission() : PushPermission.unsupported;
      if (!mounted) return;
      setState(() {
        _pushable = pushable;
        _pushOn = on;
        _permission = permission;
      });
    } catch (_) {
      if (mounted) setState(() => _pushable = false);
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

  /// « Notifications sur ce téléphone »: on asks the phone (from this very
  /// tap — a browser asks only from a gesture) and registers it; off takes
  /// this phone out of the person's book.
  Future<void> _setPush(bool on) async {
    setState(() {
      _busy = 'push';
      _said = null;
    });
    if (on) {
      final now = await widget.device.enable(widget.notify);
      final permission = await widget.device.permission();
      if (!mounted) return;
      setState(() {
        _busy = null;
        _pushOn = now;
        _permission = permission;
        if (!now) {
          _said = context.tr('Les notifications sont refusées sur cet appareil. Elles s\'activent dans ses paramètres.');
        }
      });
    } else {
      await widget.device.disable(widget.notify);
      if (!mounted) return;
      setState(() {
        _busy = null;
        _pushOn = false;
      });
    }
  }

  bool get _blocked => _permission == PushPermission.blocked;

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
            if (_pushable == true) ...[
              SwitchListTile(
                key: const Key('settings-push-switch'),
                contentPadding: EdgeInsets.zero,
                secondary: Icon(_pushOn == true
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined),
                title: Text(context.tr('Notifications sur ce téléphone')),
                subtitle: Text(_pushOn == true
                    ? context.tr('Elles sonnent avec le son et la vibration du téléphone, même l\'application fermée.')
                    : _blocked
                        ? context.tr('Bloquées dans les réglages du téléphone : c\'est là qu\'elles se rallument.')
                        : context.tr('Éteint : ce téléphone ne sonne pas. La cloche de l\'application garde tout.')),
                value: _pushOn == true,
                onChanged: _busy == null && (_pushOn == true || !_blocked)
                    ? _setPush
                    : null,
              ),
              if (_blocked && _pushOn != true)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: kIsWeb
                      ? Text(
                          context.tr('Dans le navigateur : le cadenas à côté de l\'adresse, puis Notifications.'),
                          style: theme.textTheme.bodySmall,
                        )
                      : OutlinedButton.icon(
                          key: const Key('settings-push-open-settings'),
                          onPressed: widget.device.openSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(context.tr('Ouvrir les réglages du téléphone')),
                        ),
                ),
            ] else if (_pushable == false)
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
            // What stands between THIS device and a ring (120).
            PushDiagnosticsPanel(notify: widget.notify),
          ],
        ),
      ),
    );
  }
}

/// What the switch needs of this phone: [PushSetup] and [PushClient]; a
/// test gives its own.
class PushDevice {
  const PushDevice();

  Future<bool> available() => PushSetup.available();
  Future<bool> ensure(NotificationsRepository notify) => PushSetup.ensure(notify);
  Future<PushPermission> permission() => PushClient.permission();
  Future<bool> enable(NotificationsRepository notify) => PushSetup.enable(notify);
  Future<void> disable(NotificationsRepository notify) => PushSetup.disable(notify);
  Future<bool> openSettings() => PushClient.openSettings();
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

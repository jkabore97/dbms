import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/notify/notifications_repository.dart';
import '../../core/notify/push_client.dart';
import '../../core/notify/push_setup.dart';

/// « Activer les notifications ? » at the app's opening (120).
///
/// The owner's words: the notifications are to be turned on as soon as the
/// app opens, and asked again every time it opens while they are not. So,
/// to every signed-in person — shopper, courier, member of a shop, a farm
/// or an association, the platform — on a cold start, on a sign-in, and on
/// a return after [longAway]: when THIS device is not in the person's book
/// and can still be turned on, a pop-up asks. « Activer » asks the device
/// (in a browser, from that very tap: browsers ask only from a gesture);
/// « Plus tard » asks again at the next opening. Blocked in the device's
/// settings, it says where to turn them on instead.
///
/// Never twice in one opening, never over the code, the second step or a
/// first setup (they are not signed-in phases, or sit under a
/// [PushPromptQuiet]), and never where nothing could ring (a build or a
/// platform without push).
class PushPrompt {
  PushPrompt({
    required this.device,
    required this.context,
    this.longAway = const Duration(hours: 1),
  }) {
    quiet.addListener(_quietChanged);
  }

  final PushPromptDevice device;

  /// Where the pop-up is shown: the app's root navigator, once it exists.
  final BuildContext? Function() context;

  /// How long away counts as opening the app again.
  final Duration longAway;

  /// How many screens that must not be interrupted are drawn now (a first
  /// setup, the creation of a business). See [PushPromptQuiet].
  static final quiet = ValueNotifier<int>(0);

  bool _signedIn = false;
  bool _everIn = false;
  bool _pending = false;
  bool _asked = false;
  bool _looking = false;

  /// The session's phase changed: [signedIn] is a phase with somebody in
  /// it and no gate in front (no code, no second step). The first such
  /// phase since the app started, or since a sign-out, is an opening.
  void phase({required bool signedIn}) {
    _signedIn = signedIn;
    if (!signedIn) return;
    if (!_everIn) {
      _everIn = true;
      _pending = true;
    }
    _try();
  }

  /// Signed out: the next sign-in is a new opening.
  void signedOut() {
    _signedIn = false;
    _everIn = false;
    _pending = false;
    _asked = false;
  }

  /// Back in the foreground after [away].
  void resumed(Duration away) {
    if (away >= longAway) {
      _asked = false;
      _pending = true;
    }
    _try();
  }

  void dispose() => quiet.removeListener(_quietChanged);

  void _quietChanged() {
    if (quiet.value == 0) _try();
  }

  bool get _blockedNow => !_signedIn || _asked || quiet.value > 0;

  Future<void> _try() async {
    if (!_pending || _looking || _blockedNow) return;
    _looking = true;
    try {
      final standing = await device.standing();
      if (standing == PushStanding.on || standing == PushStanding.unavailable) {
        _pending = false;
        return;
      }
      // The address the phase change leads to is drawn first: a pop-up over
      // a page the router then replaces would go with it.
      await WidgetsBinding.instance.endOfFrame;
      if (_blockedNow || !_pending) return;
      final ctx = context();
      if (ctx == null || !ctx.mounted) return;
      _asked = true;
      _pending = false;
      await showPushPromptDialog(ctx,
          device: device, blocked: standing == PushStanding.blocked);
    } finally {
      _looking = false;
    }
  }
}

/// What the pop-up needs of the device — the real one is [AppPushDevice];
/// a test gives its own.
abstract class PushPromptDevice {
  Future<PushStanding> standing();

  /// From the person's tap: asks the device, saves its address.
  Future<bool> enable();

  /// Opens the phone's settings for the app's notifications.
  Future<bool> openSettings();

  /// Whether [openSettings] can do anything here (not in a browser).
  bool get canOpenSettings;
}

class AppPushDevice implements PushPromptDevice {
  const AppPushDevice(this.notify);

  final NotificationsRepository notify;

  @override
  Future<PushStanding> standing() => PushSetup.standing(notify);

  @override
  Future<bool> enable() => PushSetup.enable(notify);

  @override
  Future<bool> openSettings() => PushClient.openSettings();

  @override
  bool get canOpenSettings => !kIsWeb;
}

/// The pop-up itself.
Future<void> showPushPromptDialog(
  BuildContext context, {
  required PushPromptDevice device,
  required bool blocked,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PushPromptDialog(device: device, blocked: blocked),
    );

class _PushPromptDialog extends StatefulWidget {
  const _PushPromptDialog({required this.device, required this.blocked});

  final PushPromptDevice device;
  final bool blocked;

  @override
  State<_PushPromptDialog> createState() => _PushPromptDialogState();
}

class _PushPromptDialogState extends State<_PushPromptDialog> {
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    // Called straight from the tap: a browser asks only from a gesture.
    final on = await widget.device.enable();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final said = on
        ? context.tr('Activé : les notifications sonneront même l\'application fermée.')
        : context.tr('Les notifications sont refusées sur cet appareil. Elles s\'activent dans ses paramètres.');
    Navigator.of(context).pop();
    messenger?.showSnackBar(SnackBar(content: Text(said)));
  }

  Future<void> _settings() async {
    Navigator.of(context).pop();
    await widget.device.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final later = TextButton(
      key: const Key('push-prompt-later'),
      onPressed: _busy ? null : () => Navigator.of(context).pop(),
      child: Text(context.tr('Plus tard')),
    );
    if (widget.blocked) {
      final settings = widget.device.canOpenSettings;
      return AlertDialog(
        key: const Key('push-prompt-blocked'),
        icon: const Icon(Icons.notifications_off_outlined),
        title: Text(context.tr('Notifications bloquées')),
        content: Text(settings
            ? context.tr('Les notifications de Mara sont bloquées sur ce téléphone. Ouvrez les réglages, touchez « Notifications » et autorisez-les : vous recevrez vos commandes, livraisons et messages même l\'application fermée.')
            : context.tr('Ce navigateur bloque les notifications de Mara. Touchez le cadenas à gauche de l\'adresse, puis autorisez les notifications pour ce site, et rechargez la page.')),
        actions: [
          later,
          if (settings)
            FilledButton(
              key: const Key('push-prompt-settings'),
              onPressed: _settings,
              child: Text(context.tr('Ouvrir les réglages')),
            ),
        ],
      );
    }
    return AlertDialog(
      key: const Key('push-prompt'),
      icon: const Icon(Icons.notifications_active_outlined),
      title: Text(context.tr('Activer les notifications ?')),
      content: Text(context.tr('Recevez vos commandes, livraisons et messages dès qu\'ils arrivent, même l\'application fermée.')),
      actions: [
        later,
        FilledButton(
          key: const Key('push-prompt-enable'),
          onPressed: _busy ? null : _enable,
          child: Text(context.tr('Activer')),
        ),
      ],
    );
  }
}

/// A screen the pop-up must not cover (a first setup, the creation of a
/// business): while it is drawn, [PushPrompt] waits, and asks once it is
/// gone.
class PushPromptQuiet extends StatefulWidget {
  const PushPromptQuiet({super.key, required this.child});

  final Widget child;

  @override
  State<PushPromptQuiet> createState() => _PushPromptQuietState();
}

class _PushPromptQuietState extends State<PushPromptQuiet> {
  @override
  void initState() {
    super.initState();
    PushPrompt.quiet.value++;
  }

  @override
  void dispose() {
    // The prompt's look is asynchronous: nothing is drawn mid-unmount.
    PushPrompt.quiet.value--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

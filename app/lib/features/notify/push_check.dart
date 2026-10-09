import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/notifications_repository.dart';
import 'notification_settings_sheet.dart' show testOutcome;
import 'push_diagnostics.dart';
import 'push_offer.dart';

/// « Tester la notification » in the command center's Réglages (115): one
/// ring to the platform admin's own devices, and what stands between a bell
/// row and a phone — how many devices this account has, and whether the
/// database webhook that wakes the push Worker exists.
class PushCheck extends StatefulWidget {
  const PushCheck({super.key, required this.notify});

  final NotificationsRepository notify;

  @override
  State<PushCheck> createState() => _PushCheckState();
}

class _PushCheckState extends State<PushCheck> {
  bool _busy = false;
  String? _said;
  bool _failed = false;

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      final r = await widget.notify.sendTest();
      if (!mounted) return;
      setState(() {
        _failed = false;
        _said = r == null
          ? context.tr('Le test arrive avec la prochaine mise à jour du serveur.')
          : testOutcome(context, web: r.web, android: r.android, webhook: r.webhook);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _said = describeError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PushOfferCard(
          notify: widget.notify,
          message: context.tr('Recevez les demandes et les signalements même l\'application fermée.'),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('platform-push-test'),
            onPressed: _busy ? null : _test,
            icon: const Icon(Icons.send_outlined),
            label: Text(context.tr('Tester la notification')),
          ),
        ),
        if (_said != null) ...[
          const SizedBox(height: 8),
          Text(_said!,
              key: const Key('platform-push-said'),
              style: _failed ? TextStyle(color: theme.colorScheme.error) : null),
        ],
        // What stands between THIS device and a ring (120).
        PushDiagnosticsPanel(notify: widget.notify),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/notify/notifications_repository.dart';
import '../../core/notify/push_setup.dart';
import '../../core/orders/order_alert.dart';

/// « Soyez prévenu… » (115): the one offer of the closed-app ring, on every
/// home of the three kinds, the shopper's profile and the courier's space.
///
/// It shows while THIS device is not in the person's book — a permission
/// given is not enough (the bug of before: the shop's home hid the offer
/// once the browser said yes, and such a browser was never subscribed). On
/// first draw it quietly writes the device back when the permission is
/// already there, and then disappears without a tap.
///
/// [doorbell]: the shop's till also wants the browser's banner for a tab in
/// the background (OrderAlert) — offered even in a build with no push.
class PushOfferCard extends StatefulWidget {
  const PushOfferCard({
    super.key,
    required this.notify,
    required this.message,
    this.doorbell = false,
    this.onChanged,
    this.padding = const EdgeInsets.only(bottom: 16),
  });

  /// Null in a tree with no app around it (a test): nothing is drawn.
  final NotificationsRepository? notify;

  /// What the ring is for, in a few words (« Soyez prévenu à chaque
  /// commande de la vitrine. »).
  final String message;
  final bool doorbell;

  /// Told after the person said yes (or no).
  final VoidCallback? onChanged;

  /// Around the card when it is drawn — nothing at all when it is not, so
  /// a page never keeps an empty gap where the offer was.
  final EdgeInsets padding;

  @override
  State<PushOfferCard> createState() => _PushOfferCardState();
}

class _PushOfferCardState extends State<PushOfferCard> {
  /// Null while the device is being looked at: nothing drawn meanwhile.
  bool? _shown;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Turned on elsewhere (the pop-up at the app's opening): gone here too.
    PushSetup.changes.addListener(_look);
    _look();
  }

  @override
  void dispose() {
    PushSetup.changes.removeListener(_look);
    super.dispose();
  }

  bool get _bellWanted =>
      widget.doorbell && OrderAlert.supported && !OrderAlert.granted;

  Future<void> _look() async {
    final notify = widget.notify;
    if (notify == null || !notify.isConfigured) return;
    final pushable = await PushSetup.available();
    var on = false;
    if (pushable) on = await PushSetup.ensure(notify);
    if (!mounted) return;
    // Switched off on purpose (Notifications sur ce téléphone, 122): no
    // card asks again; the switch is the way back.
    setState(() => _shown = (pushable && !on && !PushSetup.off) || _bellWanted);
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    // The browser grants a notification from a person's own gesture only:
    // the doorbell first (it is the same browser permission), then the
    // subscription, which then asks nothing more.
    var bell = false;
    if (widget.doorbell && OrderAlert.supported) bell = await OrderAlert.request();
    final on = await PushSetup.enable(widget.notify!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _shown = !(on || bell);
    });
    widget.onChanged?.call();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(on
          ? context.tr('Activé : les notifications sonneront même l\'application fermée.')
          : bell
              ? context.tr('Activé : une commande sonnera quand cet onglet est en arrière-plan.')
              : context.tr('Les notifications sont refusées sur cet appareil. Elles s\'activent dans ses paramètres.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_shown != true) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimaryContainer;
    return Padding(
      padding: widget.padding,
      child: Material(
        key: const Key('push-offer'),
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.notifications_active_outlined, color: on),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.message, style: TextStyle(color: on))),
              const SizedBox(width: 8),
              FilledButton.tonal(
                key: const Key('push-offer-enable'),
                onPressed: _busy ? null : _enable,
                child: Text(context.tr('Activer')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

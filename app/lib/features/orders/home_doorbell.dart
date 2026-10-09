import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/notify/alert_tone.dart';
import '../../core/orders/order_alert.dart';
import '../../core/retail/retail_repository.dart';

/// The vitrine's doorbell on a farm's or an association's home (100), as
/// the shop's home has had it (074): while the home is open the count of
/// orders — an association's demandes — still waiting is re-read quietly,
/// and a rise rings: the tone and the buzz chosen in Compte › Préférences
/// (only while the home is the page on top: the orders list, pushed over
/// it, rings for itself), a system banner where the browser allows it, and
/// a line with « Voir ». A fall is not news; no signal is not news either.
mixin HomeDoorbell<T extends StatefulWidget> on State<T> {
  Timer? _doorbell;

  /// Waiting orders as last read; null before the first read, which only
  /// sets the count (what was already there when the home opened is not a
  /// new order).
  int? _rung;

  static const doorbellEvery = Duration(seconds: 90);

  /// The business, and its orders. Null retail: no doorbell.
  OrgSummary get doorbellOrg;
  RetailRepository? get doorbellRetail;

  /// Told the count at every read, for the home's own badge.
  void onDoorbellCount(int pending) {}

  /// Starts listening; called once the home has drawn. Safe to call again.
  void armDoorbell() {
    final retail = doorbellRetail;
    if (_doorbell != null || retail == null || !retail.isConfigured) return;
    unawaited(_listen());
    _doorbell = Timer.periodic(doorbellEvery, (_) => _listen());
  }

  @override
  void dispose() {
    _doorbell?.cancel();
    super.dispose();
  }

  Future<void> _listen() async {
    final retail = doorbellRetail;
    if (retail == null || !mounted) return;
    final int pending;
    try {
      pending = await retail.pendingOrders(doorbellOrg.id);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final before = _rung;
    _rung = pending;
    onDoorbellCount(pending);
    if (before == null || pending <= before) return;

    final org = doorbellOrg;
    if (ModalRoute.of(context)?.isCurrent ?? true) unawaited(AlertTone.ring());
    final demande = org.isAssociation;
    OrderAlert.show(
      demande
          ? context.tr('Nouvelle demande — {name}', {'name': org.name})
          : context.tr('Nouvelle commande — {name}', {'name': org.name}),
      context.tr(
          demande
              ? (pending > 1 ? '{n} demandes à traiter sur la vitrine.' : '{n} demande à traiter sur la vitrine.')
              : (pending > 1 ? '{n} commandes à traiter sur la vitrine.' : '{n} commande à traiter sur la vitrine.'),
          {'n': pending}),
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(demande
          ? context.tr('Nouvelle demande : {pending} à traiter sur la vitrine.',
              {'pending': pending})
          : context.tr('Nouvelle commande : {pending} à traiter sur la vitrine.',
              {'pending': pending})),
      action: SnackBarAction(
        label: context.tr('Voir'),
        onPressed: () => context.push(Routes.inside(org.id, 'commandes')),
      ),
    ));
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/local_db.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/shopper/shopper_repository.dart';
import '../storefront/booking_sheet.dart';

/// « Recommander » (113): the vitrine's basket filled again with what of
/// this order it still has (the server says what, at most what is left),
/// then the vitrine opens on it — the basket the street keeps on the
/// device (`street_basket_<slug>`), so the shopper sees it, can change it,
/// and orders as always. Anything already in that basket stays.
///
/// « Réserver à nouveau » ([booking], 125): a service is booked, never
/// basketed — the vitrine opens on that service's booking sheet, for a new
/// day and time.
Future<void> reorderInto(
  BuildContext context, {
  required ShopperRepository shopper,
  required LocalDb db,
  required String orderId,
  bool booking = false,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  ReorderBasket basket;
  try {
    basket = await shopper.reorder(orderId);
  } catch (e) {
    if (context.mounted) say(describeError(e));
    return;
  }
  if (!context.mounted) return;
  if (basket.closed) {
    say(context.tr('Cette vitrine ne prend pas de commandes pour le moment.'));
    return;
  }
  if (basket.lines.isEmpty) {
    say(context.tr('Plus rien de cette commande n\'est disponible sur la vitrine.'));
    return;
  }
  if (booking) {
    final line = basket.lines.entries.first;
    await db.writePref(
      pendingBookingKey(basket.slug),
      jsonEncode(BookingChoice(
        productId: line.key,
        quantity: line.value.round().clamp(1, 20),
      ).toJson()),
    );
    await db.writePref(streetResumeKey, streetResumeNote(basket.slug, booking: true));
    if (!context.mounted) return;
    context.go(Routes.storefront(basket.slug));
    say(context.tr('Choisissez un jour et une heure.'));
    return;
  }
  final key = 'street_basket_${basket.slug}';
  final merged = <String, double>{};
  try {
    final raw = await db.readPref(key);
    if (raw != null) {
      for (final e in Map<String, dynamic>.from(jsonDecode(raw) as Map).entries) {
        merged[e.key] = (e.value as num).toDouble();
      }
    }
  } catch (_) {
    // A basket that cannot be read is an empty basket.
  }
  merged.addAll(basket.lines);
  await db.writePref(key, jsonEncode(merged));
  if (!context.mounted) return;
  final note = basket.missing == 1
      ? context.tr('Votre panier est prêt. 1 article de la commande n\'est plus disponible.')
      : basket.missing > 1
          ? context.tr('Votre panier est prêt. {n} articles de la commande ne sont plus disponibles.',
              {'n': basket.missing})
          : context.tr('Votre panier est prêt : vérifiez-le, puis commandez.');
  context.go(Routes.storefront(basket.slug));
  say(note);
}

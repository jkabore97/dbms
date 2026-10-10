import 'package:flutter/widgets.dart';

import '../../core/l10n/tr.dart';
import '../../core/orders/booking.dart';
import '../../core/orders/orders.dart';

/// Where a booking stands, in one word (125): « Mes commandes »' chip.
String bookingStateWord(BuildContext context, BookingState state) => switch (state) {
      BookingState.requested => context.tr('Demandé'),
      BookingState.proposed => context.tr('Autre heure proposée'),
      BookingState.confirmed => context.tr('Confirmé'),
      BookingState.done => context.tr('Terminé'),
      BookingState.declined => context.tr('Refusé'),
      BookingState.cancelled => context.tr('Annulé'),
    };

/// The business's line for a booking (125), in Commandes: « Rendez-vous
/// demandé — mardi 14 oct., 10:00 », « Rendez-vous confirmé — … »,
/// « Autre heure proposée — … (en attente du client) ».
String shopBookingHeadline(BuildContext context, ShopOrder order) {
  final lang = context.trLanguage;
  final asked = bookingWhen(order.bookedFor!, lang, short: true);
  final state = bookingStateOf(order.status, proposedFor: order.proposedFor);
  return switch (state) {
    BookingState.requested =>
      context.tr('Rendez-vous demandé — {when}', {'when': asked}),
    BookingState.proposed => context.tr('Autre heure proposée — {when} (en attente du client)',
        {'when': bookingWhen(order.proposedFor!, lang, short: true)}),
    BookingState.confirmed =>
      context.tr('Rendez-vous confirmé — {when}', {'when': asked}),
    BookingState.done => context.tr('Rendez-vous terminé — {when}', {'when': asked}),
    BookingState.declined => context.tr('Rendez-vous refusé — {when}', {'when': asked}),
    BookingState.cancelled => context.tr('Rendez-vous annulé — {when}', {'when': asked}),
  };
}

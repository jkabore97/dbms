/// Booking a service (125): the day and the time, not a basket.
///
/// The slots the booking sheet offers are the ones the server accepts
/// (125's booking_check_slot): in the future, within the next 14 days, on
/// :00 or :30, inside the vitrine's opening hours that day — a vitrine with
/// no hours set takes every day, 08:00–20:00, and a night shop's hours
/// after midnight belong to the day before (093).
///
/// Every time here is Ouagadougou's, which is UTC all year (no summer
/// time): a business keeps no time zone and the database reads every
/// booking there. So the slots are built, sent and shown in UTC — never
/// the phone's own zone, which would move a 10:00 at the salon to 11:00 on
/// a phone set to Paris.
library;

import 'package:intl/intl.dart';

import '../storefront/storefront_repository.dart' show VitrineSchedule;

/// How far ahead a booking is taken.
const bookingWindow = Duration(days: 14);

/// The hours a vitrine with none set takes bookings in.
const defaultBookingHours =
    VitrineSchedule(days: [1, 2, 3, 4, 5, 6, 7], open: '08:00', close: '20:00');

/// The most a booking by the person or by the hour may count.
const bookingMaxQuantity = 20;

/// Ouagadougou's clock (UTC): [at] as the business reads it.
DateTime ouagaTime(DateTime at) => at.toUtc();

int _minutes(String hhmm) =>
    int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

/// Whether the vitrine is open at [local] (a time on Ouagadougou's clock),
/// by [hours] — the server's vitrine_open_at.
bool openAt(VitrineSchedule hours, DateTime local) {
  final day = local.weekday; // 1 = lundi, as ISO and 093 count
  final prev = day == 1 ? 7 : day - 1;
  final t = local.hour * 60 + local.minute;
  final open = _minutes(hours.open);
  final close = _minutes(hours.close);
  if (close > open) return hours.days.contains(day) && t >= open && t < close;
  return (hours.days.contains(day) && t >= open) ||
      (hours.days.contains(prev) && t < close);
}

/// One day of the sheet: its date (midnight, UTC) and its free times.
class BookingDay {
  const BookingDay(this.date, this.slots);

  final DateTime date;
  final List<DateTime> slots;
}

/// The days and times a booking may take from [now]: the next 14 days that
/// have at least one slot, each with its half-hours inside the hours and
/// still ahead. [hours] null: [defaultBookingHours].
List<BookingDay> bookingDays(VitrineSchedule? hours, {required DateTime now}) {
  final h = hours ?? defaultBookingHours;
  final from = ouagaTime(now);
  final last = from.add(bookingWindow);
  final today = DateTime.utc(from.year, from.month, from.day);
  final days = <BookingDay>[];
  for (var d = 0; d < 15; d++) {
    final date = DateTime.utc(today.year, today.month, today.day + d);
    final slots = <DateTime>[
      for (var half = 0; half < 48; half++)
        if (date.add(Duration(minutes: 30 * half)) case final at
            when at.isAfter(from) && !at.isAfter(last) && openAt(h, at))
          at,
    ];
    if (slots.isNotEmpty) days.add(BookingDay(date, slots));
  }
  return days;
}

/// A service booked by the person or by the hour asks how many (125);
/// any other is booked once.
bool bookingAsksQuantity(String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  return u == 'personne' || u == 'heure';
}

/// « mardi 14 octobre, 10:00 » / « Tuesday 14 October, 10:00 » — or, [short],
/// « mardi 14 oct., 10:00 » / « Tuesday 14 Oct, 10:00 » (Commandes). On
/// Ouagadougou's clock, in [lang] ('en', else French).
String bookingWhen(DateTime at, String lang, {bool short = false}) {
  final local = ouagaTime(at);
  final locale = lang == 'en' ? 'en' : 'fr_FR';
  final day = DateFormat(short ? 'EEEE d MMM' : 'EEEE d MMMM', locale).format(local);
  return '$day, ${DateFormat('HH:mm').format(local)}';
}

/// « mardi 14 oct. » / « Tuesday 14 Oct »: a day chip.
String bookingDayLabel(DateTime date, String lang) =>
    DateFormat('EEE d MMM', lang == 'en' ? 'en' : 'fr_FR').format(ouagaTime(date));

/// « 10:00 »: a time chip.
String bookingTimeLabel(DateTime at) => DateFormat('HH:mm').format(ouagaTime(at));

/// Where a booking stands (125), read from the order's status and its
/// proposal — the server keeps no third column.
enum BookingState { requested, proposed, confirmed, done, declined, cancelled }

BookingState bookingStateOf(String status, {DateTime? proposedFor}) =>
    switch (status) {
      'pending' => proposedFor == null ? BookingState.requested : BookingState.proposed,
      'accepted' || 'ready' => BookingState.confirmed,
      'picked_up' || 'delivered' => BookingState.done,
      'refused' => BookingState.declined,
      _ => BookingState.cancelled,
    };

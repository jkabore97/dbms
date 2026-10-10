import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/orders/booking.dart';
import '../../core/storefront/storefront_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../common/keyboard_sheet.dart';
import 'shop_style.dart';
import 'storefront_screen.dart' show priceOf;

/// What the customer chose on the booking sheet (125): one service, its
/// day and time, how many when it is by the person or the hour, their
/// words. Kept on the device through a sign-in, as the basket is.
class BookingChoice {
  const BookingChoice({
    required this.productId,
    this.at,
    this.quantity = 1,
    this.note,
    this.phone,
  });

  final String productId;

  /// The slot, on Ouagadougou's clock (UTC); null before one is chosen.
  final DateTime? at;
  final int quantity;
  final String? note;
  final String? phone;

  Map<String, Object?> toJson() => {
        'product': productId,
        if (at != null) 'at': at!.toUtc().toIso8601String(),
        'quantity': quantity,
        if (note != null) 'note': note,
        if (phone != null) 'phone': phone,
      };

  static BookingChoice? fromJson(Object? json) {
    if (json is! Map || json['product'] is! String) return null;
    final q = json['quantity'];
    return BookingChoice(
      productId: json['product'] as String,
      at: json['at'] is String ? DateTime.tryParse(json['at'] as String)?.toUtc() : null,
      quantity: q is num ? q.toInt().clamp(1, bookingMaxQuantity) : 1,
      note: json['note'] as String?,
      phone: json['phone'] as String?,
    );
  }
}

/// The days as chips, then the times of the day picked (125) — the booking
/// sheet's, and the business's « Proposer une autre heure ».
class BookingSlotPicker extends StatelessWidget {
  const BookingSlotPicker({
    super.key,
    required this.days,
    required this.day,
    required this.slot,
    required this.onDay,
    required this.onSlot,
  });

  final List<BookingDay> days;

  /// The day picked, by its date; null: none yet.
  final DateTime? day;
  final DateTime? slot;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<DateTime> onSlot;

  @override
  Widget build(BuildContext context) {
    final lang = context.trLanguage;
    final theme = Theme.of(context);
    final picked = [
      for (final d in days)
        if (d.date == day) d,
    ].firstOrNull;
    if (days.isEmpty) {
      return Text(
        context.tr('Aucun créneau dans les 14 prochains jours.'),
        key: const Key('booking-no-day'),
        style: TextStyle(color: theme.colorScheme.error),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('Quel jour ?'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            key: const Key('booking-days'),
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = days[i];
              return ChoiceChip(
                key: Key('booking-day-${d.date.toIso8601String().substring(0, 10)}'),
                label: Text(bookingDayLabel(d.date, lang)),
                selected: d.date == day,
                onSelected: (_) => onDay(d.date),
              );
            },
          ),
        ),
        if (picked != null) ...[
          const SizedBox(height: 16),
          Text(context.tr('À quelle heure ?'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            key: const Key('booking-times'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final at in picked.slots)
                ChoiceChip(
                  key: Key('booking-time-${bookingTimeLabel(at)}'),
                  label: Text(bookingTimeLabel(at)),
                  selected: at == slot,
                  onSelected: (_) => onSlot(at),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// « Réserver » on a service (125): the service and its price, the days the
/// vitrine opens in the next 14, the half-hours of the day picked (those of
/// today already past left out), how many only for a service by the person
/// or the hour, a word, and « Réserver ». Never the basket: one service,
/// one slot. Closes with the [BookingChoice]; the vitrine signs the
/// customer in if needed, then sends it.
class BookingSheet extends StatefulWidget {
  const BookingSheet({
    super.key,
    required this.item,
    required this.currency,
    this.hours,
    this.profile = 'retail',
    this.initial,
    this.error,
    this.provedPhone,
    this.now,
  });

  final PublicItem item;
  final String currency;

  /// The vitrine's hours (093); null: every day, 08:00–20:00.
  final VitrineSchedule? hours;

  /// Who « la boutique » is in the sheet's words.
  final String profile;

  /// What was chosen before (through a sign-in, or a refusal to correct).
  final BookingChoice? initial;

  /// The server's refusal of [initial], said above the button.
  final String? error;

  /// The number WhatsApp proved (109), said instead of the optional field.
  final String? provedPhone;

  /// The clock, for tests; the device's otherwise.
  final DateTime? now;

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  late final List<BookingDay> _days =
      bookingDays(widget.hours, now: widget.now ?? DateTime.now());
  DateTime? _day;
  DateTime? _slot;
  late int _quantity = widget.initial?.quantity ?? 1;
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late String? _error = widget.error;

  bool get _asksQuantity => bookingAsksQuantity(widget.item.unit);

  @override
  void initState() {
    super.initState();
    // The slot chosen before, when it is still free to take; else its day.
    final at = widget.initial?.at;
    for (final d in _days) {
      if (at != null && d.slots.contains(at)) {
        _day = d.date;
        _slot = at;
      }
    }
    if (_day == null && at != null) {
      final date = DateTime.utc(at.year, at.month, at.day);
      if (_days.any((d) => d.date == date)) _day = date;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _send() {
    final slot = _slot;
    if (slot == null) {
      setState(() => _error = context.tr('Choisissez un jour et une heure.'));
      return;
    }
    final note = _note.text.trim();
    final phone = _phone.text.trim();
    Navigator.of(context).pop(BookingChoice(
      productId: widget.item.id,
      at: slot,
      quantity: _asksQuantity ? _quantity : 1,
      note: note.isEmpty ? null : note,
      phone: widget.provedPhone != null || phone.isEmpty ? null : phone,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(widget.currency);
    final theme = Theme.of(context);
    final lang = context.trLanguage;
    final perPerson = (widget.item.unit ?? '').trim().toLowerCase() == 'personne';
    final hours = widget.hours;
    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('booking-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            key: const Key('booking-send'),
            onPressed: _slot == null ? null : _send,
            child: Text(
              _slot == null
                  ? context.tr('Réserver')
                  : context.tr('Réserver · {when}', {
                      'when': bookingWhen(_slot!, lang, short: true),
                    }),
            ),
          ),
        ],
      ),
      children: [
        Text(
          widget.item.name,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: ShopStyle.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          priceOf(money, widget.item, lang),
          style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.schedule_outlined, size: 15, color: ShopStyle.mist),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hours == null
                    // 125: no hours set — every day, 08:00–20:00.
                    ? context.tr('Horaires non précisés : tous les jours, de 8 h à 20 h.')
                    : hours.label(lang),
                key: const Key('booking-hours'),
                style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        BookingSlotPicker(
          days: _days,
          day: _day,
          slot: _slot,
          onDay: (d) => setState(() {
            _day = d;
            _slot = null;
            _error = null;
          }),
          onSlot: (at) => setState(() {
            _slot = at;
            _error = null;
          }),
        ),
        if (_asksQuantity) ...[
          const SizedBox(height: 18),
          Row(
            key: const Key('booking-quantity'),
            children: [
              Expanded(
                child: Text(
                  perPerson
                      ? context.tr('Pour combien de personnes ?')
                      : context.tr('Combien d\'heures ?'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton.outlined(
                key: const Key('booking-less'),
                tooltip: context.tr('Moins'),
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove, size: 18),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_quantity',
                  key: const Key('booking-count'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton.outlined(
                key: const Key('booking-more'),
                tooltip: context.tr('Plus'),
                onPressed: _quantity < bookingMaxQuantity
                    ? () => setState(() => _quantity++)
                    : null,
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const Key('booking-note'),
          controller: _note,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: switch (widget.profile) {
              'farm' => context.tr('Un mot pour la ferme (facultatif)'),
              'association' || 'church' => context.tr('Un mot pour l\'association (facultatif)'),
              _ => context.tr('Un mot pour la boutique (facultatif)'),
            },
          ),
        ),
        const SizedBox(height: 12),
        if (widget.provedPhone != null)
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 20, color: maraGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('Votre numéro WhatsApp vérifié : {phone}', {
                    'phone': widget.provedPhone,
                  }),
                  style: const TextStyle(fontSize: 14, color: ShopStyle.ink),
                ),
              ),
            ],
          )
        else
          TextField(
            key: const Key('booking-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: context.tr('Votre numéro (facultatif)'),
              hintText: '+226 70 00 00 00',
            ),
          ),
        const SizedBox(height: 10),
        Text(
          context.tr('Rien à payer maintenant : vous payez sur place, au rendez-vous.'),
          style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('Vous recevrez la réponse ici : l\'heure confirmée, ou une autre proposée.'),
          style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
        ),
      ],
    );
  }
}

/// Where the vitrine leaves itself a note while the shopper signs in (F1):
/// `slug|when|what`. Back signed in within half an hour, what the sign-in
/// interrupted — the basket's order, or the booking — opens again by
/// itself, and only that one ([streetResumeNote]).
const streetResumeKey = 'street_order_after_sign_in';

/// The note [streetResumeKey] keeps: this vitrine, now, and whether a
/// booking ([booking]) or the basket's order asked for the sign-in — so a
/// booking forgotten on the device never takes the place of an order.
String streetResumeNote(String slug, {required bool booking}) =>
    '$slug|${DateTime.now().toIso8601String()}|${booking ? 'booking' : 'order'}';

/// Where a booking chosen before a sign-in sleeps on the device, per
/// vitrine (125), as the basket does (`street_basket_<slug>`).
String pendingBookingKey(String slug) => 'street_booking_$slug';

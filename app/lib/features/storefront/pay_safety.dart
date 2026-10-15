import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import 'shop_style.dart';

/// How the shopper pays, for the safety line (batch 151).
enum PayWay {
  /// Cash at the door or at the counter (057's 'cash').
  cash,

  /// Wave, paid from inside Mara once the order is accepted — Mara's
  /// checkout (076) or the shop's own link Mara shows (057).
  wave,
}

/// Where the cash is handed over (batch 151).
enum PayAt { either, pickup, delivery }

/// « Ne payez jamais d'avance » (batch 151): one calm line where a shopper
/// could be asked for money — the order sheet before sending, an open
/// order's card, the vitrine's contact area — and a way to report.
///
/// Said for the way the shopper pays: in cash, never pay ahead, pay at the
/// door or the counter; by Wave, Mara's own button is the way, once the
/// order is accepted — never a number sent by message or a call. A
/// payment through Mara is never called « d'avance » here: it is the safe
/// way, and saying otherwise would scare people off the one channel Mara
/// can vouch for.
class PaySafetyLine extends StatelessWidget {
  const PaySafetyLine({
    super.key,
    this.way = PayWay.cash,
    this.alsoWave = false,
    this.at = PayAt.either,
    this.onReport,
  });

  final PayWay way;

  /// Where the money changes hands: the door, the counter, or either (a
  /// vitrine that delivers). A farm that never delivers is never told
  /// « à la livraison ».
  final PayAt at;

  /// The vitrine's contact area of a business that takes Wave: the cash
  /// line says Wave in Mara is fine too.
  final bool alsoWave;

  /// « Signaler » — the report sheet (150's), when there is one to open.
  final VoidCallback? onReport;

  static String sentence(BuildContext context, PayWay way,
          {bool alsoWave = false, PayAt at = PayAt.either}) =>
      switch ((way, at, alsoWave)) {
        (PayWay.wave, _, _) => context.tr(
            'Payez par Wave seulement depuis Marakaj, une fois la commande acceptée — jamais à un numéro reçu par message ou par appel.'),
        (PayWay.cash, PayAt.pickup, true) => context.tr(
            'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez au retrait, ou par Wave dans Marakaj.'),
        (PayWay.cash, PayAt.pickup, false) => context.tr(
            'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez au retrait.'),
        (PayWay.cash, PayAt.delivery, _) => context.tr(
            'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez à la livraison, quand vous recevez la commande.'),
        (PayWay.cash, PayAt.either, true) => context.tr(
            'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez à la livraison, au retrait, ou par Wave dans Marakaj.'),
        (PayWay.cash, PayAt.either, false) => context.tr(
            'Ne payez jamais d\'avance à quelqu\'un que vous ne connaissez pas. Payez à la livraison ou au retrait.'),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pay-safety'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: ShopStyle.stone,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.verified_user_outlined, size: 18, color: ShopStyle.mist),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sentence(context, way, alsoWave: alsoWave, at: at),
                  key: const Key('pay-safety-text'),
                  style: const TextStyle(fontSize: 13, height: 1.35, color: ShopStyle.ink),
                ),
                if (onReport != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: InkWell(
                      key: const Key('pay-safety-report'),
                      onTap: onReport,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        // A finger's height, the line itself small.
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          context.tr('On vous demande de payer avant ? Signalez-le'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ShopStyle.ink,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

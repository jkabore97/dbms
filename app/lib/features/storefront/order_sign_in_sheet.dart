import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import 'shop_style.dart';

/// What the shopper chose on [OrderSignInSheet].
enum OrderSignIn { google, otherWay, newAccount }

/// « Connectez-vous pour commander » (F1): a stranger browsed the street,
/// filled a basket, and only now — at « Commander » or « Réserver » — is
/// asked who they are. The owner's order: « Continuer avec Google » first,
/// big, one tap; at the bottom « Se connecter autrement » and « Créer un
/// compte ». The basket stays on the device and the vitrine opens the
/// order again once they are back (StorefrontScreen).
///
/// [googleAvailable] is the project's answer (Google switched on in
/// Supabase): while it is asked the button waits; off, it is not drawn and
/// the two others carry the sheet.
Future<OrderSignIn?> showOrderSignInSheet(
  BuildContext context, {
  required bool booking,
  required Future<bool> Function() googleAvailable,
}) {
  return showModalBottomSheet<OrderSignIn>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ShopStyle.paper,
    builder: (sheet) => Theme(
      data: ShopStyle.theme(sheet),
      child: OrderSignInSheet(booking: booking, googleAvailable: googleAvailable),
    ),
  );
}

class OrderSignInSheet extends StatefulWidget {
  const OrderSignInSheet({
    super.key,
    required this.booking,
    required this.googleAvailable,
  });

  final bool booking;
  final Future<bool> Function() googleAvailable;

  @override
  State<OrderSignInSheet> createState() => _OrderSignInSheetState();
}

class _OrderSignInSheetState extends State<OrderSignInSheet> {
  /// Null while the project is asked.
  bool? _google;

  @override
  void initState() {
    super.initState();
    widget.googleAvailable().then(
      (on) {
        if (mounted) setState(() => _google = on);
      },
      onError: (Object _) {
        if (mounted) setState(() => _google = false);
      },
    );
  }

  void _choose(OrderSignIn choice) => Navigator.of(context).pop(choice);

  @override
  Widget build(BuildContext context) {
    final google = _google;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          key: const Key('order-sign-in'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.booking
                  ? context.tr('Connectez-vous pour réserver')
                  : context.tr('Connectez-vous pour commander'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: ShopStyle.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('Votre panier est gardé : vous revenez ici juste après.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
            ),
            const SizedBox(height: 24),
            if (google != false) ...[
              SizedBox(
                height: 58,
                child: FilledButton(
                  key: const Key('order-sign-in-google'),
                  onPressed: google == true ? () => _choose(OrderSignIn.google) : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (google == null)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const _GoogleG(),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          context.tr('Continuer avec Google'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
            // The two other doors at the bottom: one above the other on a
            // phone, where « Se connecter autrement » would wrap in half a
            // row; side by side, the same height, on a wider screen.
            LayoutBuilder(
              builder: (context, box) {
                final other = OutlinedButton(
                  key: const Key('order-sign-in-other'),
                  onPressed: () => _choose(OrderSignIn.otherWay),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text(
                    context.tr('Se connecter autrement'),
                    textAlign: TextAlign.center,
                  ),
                );
                final create = OutlinedButton(
                  key: const Key('order-sign-in-create'),
                  onPressed: () => _choose(OrderSignIn.newAccount),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: Text(
                    context.tr('Créer un compte'),
                    textAlign: TextAlign.center,
                  ),
                );
                if (box.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [other, const SizedBox(height: 10), create],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: other),
                      const SizedBox(width: 10),
                      Expanded(child: create),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Google's « G » on a white disc, so it reads on the dark button.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 17,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}

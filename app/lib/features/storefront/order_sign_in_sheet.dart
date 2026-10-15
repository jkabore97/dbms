import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton;

import '../../core/auth/auth_repository.dart' show appleSignInPlatform, appleWebPlatform;
import '../../core/l10n/tr.dart';
import 'shop_style.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';

/// What the shopper chose on [OrderSignInSheet].
enum OrderSignIn { apple, google, otherWay, newAccount }

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
///
/// On an iPhone, « Continuer avec Apple » above Google, as big (125: App
/// Review's 4.8), when [appleAvailable] says the project has Apple on. On
/// the website the same (139), when [appleWebAvailable] says « Connexion
/// Apple sur le site » is on. Android never draws it.
Future<OrderSignIn?> showOrderSignInSheet(
  BuildContext context, {
  required bool booking,
  required Future<bool> Function() googleAvailable,
  Future<bool> Function()? appleAvailable,
  Future<bool> Function()? appleWebAvailable,
  Color? accent,
  bool report = false,
  void Function(BuildContext context)? onWriteUs,
}) {
  return showMaraSheet<OrderSignIn>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: ShopStyle.paper,
    builder: (sheet) => Theme(
      // The vitrine's own colour on its sheet (122).
      data: ShopStyle.theme(sheet, accent: accent),
      child: OrderSignInSheet(
        booking: booking,
        report: report,
        onWriteUs: onWriteUs,
        googleAvailable: googleAvailable,
        appleAvailable: appleAvailable,
        appleWebAvailable: appleWebAvailable,
      ),
    ),
  );
}

class OrderSignInSheet extends StatefulWidget {
  const OrderSignInSheet({
    super.key,
    required this.booking,
    required this.googleAvailable,
    this.appleAvailable,
    this.appleWebAvailable,
    this.report = false,
    this.onWriteUs,
  });

  final bool booking;

  /// « Signaler cette vitrine » (150): the same doors, its own words — the
  /// report sheet opens again once the person is back.
  final bool report;

  /// « ou écrivez-nous »: Mara's help, for somebody who would rather not
  /// make an account. Null: not drawn.
  final void Function(BuildContext context)? onWriteUs;
  final Future<bool> Function() googleAvailable;

  /// The project's Apple switch; asked on an iPhone only. Null: no Apple.
  final Future<bool> Function()? appleAvailable;

  /// The website's Apple switch (139); asked on the website only.
  final Future<bool> Function()? appleWebAvailable;

  @override
  State<OrderSignInSheet> createState() => _OrderSignInSheetState();
}

class _OrderSignInSheetState extends State<OrderSignInSheet> {
  /// Null while the project is asked.
  bool? _google;

  /// Drawn once the project says Apple is on — on an iPhone, or on the
  /// website with its switch on (139).
  bool _apple = false;

  @override
  void initState() {
    super.initState();
    final apple = appleSignInPlatform
        ? widget.appleAvailable
        : appleWebPlatform
            ? widget.appleWebAvailable
            : null;
    if (apple != null) {
      apple().then(
        (on) {
          if (mounted && on) setState(() => _apple = true);
        },
        onError: (Object _) {},
      );
    }
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
    // One height for both buttons: 58, or 52 on a narrow phone (AU-1).
    final double buttonHeight = MediaQuery.sizeOf(context).width < 360 ? 52 : 58;
    // On an iPhone, Google only beside Apple, below it (130: App Review 4.8
    // — never Google alone, never Google first).
    final google = appleSignInPlatform && !_apple ? false : _google;
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
              widget.report
                  ? context.tr('Connectez-vous pour signaler')
                  : widget.booking
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
              // A booking (125) is kept as the basket is, with its day and time.
              widget.report
                  ? context.tr('Mara vous répond dans vos notifications. Vous revenez ici juste après.')
                  : widget.booking
                  ? context.tr('Votre réservation est gardée : vous revenez ici juste après.')
                  : context.tr('Votre panier est gardé : vous revenez ici juste après.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
            ),
            const SizedBox(height: 24),
            if (_apple) ...[
              // Apple's own button, as tall as Google's, above it. Its label
              // is sized from its height, as Apple's system button is — never
              // wrapped and cut at large text (UI audit AU-1); a little lower
              // on an iPhone SE so the words keep one line.
              MediaQuery.withNoTextScaling(
                child: SignInWithAppleButton(
                  key: const Key('order-sign-in-apple'),
                  text: context.tr('Continuer avec Apple'),
                  height: buttonHeight,
                  borderRadius: BorderRadius.all(Radius.circular(buttonHeight / 2)),
                  onPressed: () => _choose(OrderSignIn.apple),
                ),
              ),
              SizedBox(height: google == false ? 28 : 12),
            ],
            if (google != false) ...[
              SizedBox(
                height: buttonHeight,
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            context.tr('Continuer avec Google'),
                            maxLines: 1,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
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
            if (widget.onWriteUs != null) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  key: const Key('order-sign-in-write-us'),
                  onPressed: () {
                    // From the tap itself: a browser opens a chat only so.
                    widget.onWriteUs!(context);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.support_agent_outlined, size: 18),
                  label: Text(context.tr('ou écrivez-nous')),
                ),
              ),
            ],
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
        // The mark keeps its disc's size whatever the text size.
        textScaler: TextScaler.noScaling,
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

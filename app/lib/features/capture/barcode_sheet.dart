import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';

/// Reading a barcode with the camera.
///
/// Works on both ship targets — a native detector on Android, the browser's
/// own on web — so unlike OCR this is offered everywhere rather than behind a
/// platform check.
///
/// What it is for: at the counter, a known product is one scan instead of
/// scrolling a list, and an unknown one opens the new-product form with the
/// number already in it. `product_by_barcode()` answers which of the two it
/// is, and returns nothing rather than a guess when the shop has never seen
/// the code.
///
/// Returns the barcode as a string, or null if the person backed out.
class BarcodeSheet extends StatefulWidget {
  const BarcodeSheet({super.key, this.title = 'Scanner un code', this.qr = false});

  final String title;

  /// A QR code — a ticket at the door — rather than a product's barcode
  /// (the owner: « your code scanner do not work »: the door's scanner was
  /// the counter's, which read the shop's barcodes and no QR code at all).
  final bool qr;

  /// The shop's barcodes (EAN, UPC, Code 128 and 39).
  static const productFormats = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
  ];

  /// What the camera looks for: a ticket's QR code, or a product's barcode.
  static List<BarcodeFormat> formatsFor({required bool qr}) =>
      qr ? const [BarcodeFormat.qrCode] : productFormats;

  /// Opens it and hands back what was read; [qr] for a ticket's QR code.
  static Future<String?> scan(BuildContext context, {String? title, bool qr = false}) {
    return showMaraSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Its own « X » beside its title.
      closeButton: false,
      builder: (_) => BarcodeSheet(title: title ?? context.tr('Scanner un code'), qr: qr),
    );
  }

  @override
  State<BarcodeSheet> createState() => _BarcodeSheetState();
}

class _BarcodeSheetState extends State<BarcodeSheet> {
  late final _controller = MobileScannerController(
    // One code, then close. Continuous detection re-reads the same label
    // dozens of times a second and the first one is always the answer.
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: BarcodeSheet.formatsFor(qr: widget.qr),
  );

  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;

      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: context.tr('Fermer'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 280,
                width: double.infinity,
                child: _error != null
                    ? Container(
                        color: theme.colorScheme.errorContainer,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!, textAlign: TextAlign.center),
                      )
                    : MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        // A camera that will not open — no permission, no
                        // device — has to say so. Left as a silent black
                        // rectangle it looks like a broken app.
                        errorBuilder: (context, error) {
                          return Container(
                            color: theme.colorScheme.errorContainer,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              context.tr('La caméra n\'est pas disponible : {name}', {'name': error.errorCode.name}),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.qr
                  ? context.tr('Placez le QR code du billet dans le cadre.')
                  : context.tr('Placez le code-barres dans le cadre.'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

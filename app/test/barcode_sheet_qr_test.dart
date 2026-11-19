import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/features/capture/barcode_sheet.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The owner: « your code scanner do not work » — the door's scanner was
/// the counter's, which read the shop's barcodes and no QR code at all.
void main() {
  test('a ticket is read as a QR code; a product as its barcode, as before', () {
    expect(BarcodeSheet.formatsFor(qr: true), [BarcodeFormat.qrCode]);
    expect(BarcodeSheet.formatsFor(qr: false), isNot(contains(BarcodeFormat.qrCode)));
    expect(BarcodeSheet.formatsFor(qr: false), containsAll([BarcodeFormat.ean13, BarcodeFormat.code128]));
  });

  test('both door scanners ask for the QR code', () {
    for (final f in ['lib/features/events/events_screens.dart', 'lib/features/events/tickets_screens.dart']) {
      final src = File(f).readAsStringSync();
      final scans = RegExp(r'BarcodeSheet\.scan\([^;]*\)').allMatches(src).map((m) => m[0]!).toList();
      expect(scans, isNotEmpty, reason: f);
      expect(scans.every((s) => s.contains('qr: true')), isTrue, reason: '$f: $scans');
    }
  });
}

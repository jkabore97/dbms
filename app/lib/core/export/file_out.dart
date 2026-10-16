import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'file_out_io.dart' if (dart.library.js_interop) 'file_out_web.dart' as platform;

/// A file the app hands out (153): the accounting reports' PDF and CSV.
///
/// Each platform the way the invoice's PDF already leaves
/// (invoice_document_screen):
///   * the web: a real download, the file named as given;
///   * Android and iOS: the system share sheet — « Enregistrer dans
///     Fichiers », Drive, WhatsApp, e-mail…
///
/// A PDF goes through `printing`'s sharePdf, exactly as the invoice does.
/// A CSV is a blob download on the web and a shared file on the phone.

/// Overridden in tests: what was handed out, instead of a download.
typedef FileOut = Future<void> Function(Uint8List bytes, String filename, String mime);

FileOut? debugFileOut;

Future<void> handOutFile(Uint8List bytes, {required String filename, required String mime}) async {
  final debug = debugFileOut;
  if (debug != null) return debug(bytes, filename, mime);
  if (mime == 'application/pdf') {
    await Printing.sharePdf(bytes: bytes, filename: filename);
    return;
  }
  await platform.saveFile(bytes, filename, mime);
}

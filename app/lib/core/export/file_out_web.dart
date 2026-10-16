import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser: a real download, named as given.
Future<void> saveFile(Uint8List bytes, String filename, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Revoked a moment later: some browsers start the download after the
  // click has returned.
  Future<void>.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}

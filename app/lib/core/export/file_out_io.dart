import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Android and iOS: the share sheet, which offers to keep the file
/// (« Enregistrer dans Fichiers », Drive) as well as to send it.
Future<void> saveFile(Uint8List bytes, String filename, String mime) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, mimeType: mime, name: filename)],
    fileNameOverrides: [filename],
  ));
}

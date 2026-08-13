import 'dart:io' show Platform;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// The device half of the conditional import in `text_reader.dart`.
///
/// This is the only file in the app allowed to import ML Kit. The web build
/// compiles `text_reader_stub.dart` in its place and never resolves the
/// package, which is the whole reason the split exists — the plugin has no
/// web implementation and adding one is not on anybody's roadmap.
///
/// Everything happens on the device. No image and no text leaves the phone,
/// which matters for a photograph of somebody's invoice and also means this
/// works at the farm gate with no signal.

/// `dart.library.io` is true in a Dart VM as well as on a phone, so the
/// conditional import alone would hand a `flutter test` run a plugin with no
/// platform behind it. The runtime check is what makes false the honest
/// answer everywhere except a real Android or iOS device.
bool get isAvailable {
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

Future<String?> readText(String path) async {
  if (!isAvailable) return null;

  // Latin script: French, and the English that appears on packaging. The
  // other recognisers are separate downloads and none of them helps here.
  final recogniser = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recogniser.processImage(InputImage.fromFilePath(path));
    final text = result.text.trim();
    return text.isEmpty ? null : text;
  } catch (_) {
    // A failed reading is not a failed capture. The photograph is already
    // safe by the time this runs, and OCR is an accelerator — the person can
    // always type what they see, which is what they did before this existed.
    return null;
  } finally {
    await recogniser.close();
  }
}

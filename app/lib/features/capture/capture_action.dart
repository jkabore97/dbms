import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/capture/text_reader.dart';

/// Taking the photograph.
///
/// The one rule this file exists to hold: **nothing is asked before the
/// picture is taken.** No category, no product, no amount, not even a name.
/// The camera opens, the shutter closes, and the app says "gardée" — every
/// required field at capture time loses a user, and Esperance's losses come
/// from data that was never captured at all.
///
/// Filing it is a different act, done later or never, from the gallery.
class CaptureAction {
  const CaptureAction._();

  /// Opens the camera, files what comes back, and tells the person what
  /// happened in one line. Returns true if anything was captured — queued
  /// counts, because from where she is standing the photograph is safe either
  /// way.
  static Future<bool> take(
    BuildContext context, {
    required String orgId,
    required CaptureRepository capture,
    ImageSource source = ImageSource.camera,
    String? kind,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        // A 12 megapixel original is four megabytes over a market's
        // connection for no gain: what is being photographed is a label or a
        // delivery note, and 2000px reads either of them.
        maxWidth: 2000,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );
    } on Exception catch (error) {
      // A browser with no camera permission, or a device with no camera at
      // all, throws here rather than returning null.
      messenger.showSnackBar(SnackBar(
        content: Text("La caméra n'est pas disponible : $error"),
      ));
      return false;
    }

    if (file == null) return false; // Cancelled. Say nothing.

    final bytes = await file.readAsBytes();
    final contentType = _typeOf(file);

    if (contentType == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Ce type de fichier ne peut pas être envoyé.'),
      ));
      return false;
    }

    // On a device that can, read the label before sending. It happens here
    // rather than server-side for three reasons: it works with no signal, no
    // photograph of anybody's invoice leaves the phone to be read, and the
    // answer is available while the person is still standing in front of the
    // thing they photographed.
    //
    // Best-effort throughout. `TextReader.read` never throws and returns null
    // on web, in tests, and whenever the reading fails — all of which are the
    // ordinary case, not an error, because capture works completely without
    // it.
    String? reading;
    if (TextReader.isAvailable && contentType.startsWith('image/')) {
      reading = await TextReader.read(file.path);
    }

    try {
      final id = await capture.capture(
        orgId: orgId,
        bytes: bytes,
        contentType: contentType,
        kind: kind,
        ocrText: reading,
      );

      messenger.showSnackBar(SnackBar(
        content: Text(id == null
            // Not an error. The bytes are on the device and will go when
            // there is signal — saying "échec" here would teach her to stop
            // taking photographs when the connection is poor, which is
            // exactly when they matter.
            ? 'Photo gardée. Elle partira dès qu’il y a du réseau.'
            : 'Photo enregistrée.'),
      ));
      return true;
    } on CaptureException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
      return false;
    }
  }

  /// Camera or the gallery. Offered as a sheet only where both make sense —
  /// the home screen's button goes straight to the camera, because a choice
  /// is a field.
  static Future<bool> choose(
    BuildContext context, {
    required String orgId,
    required CaptureRepository capture,
    String? kind,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text(
                  kIsWeb ? 'Choisir un fichier' : 'Choisir une photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !context.mounted) return false;
    return take(context, orgId: orgId, capture: capture, source: source, kind: kind);
  }

  /// What the upload Worker will accept. `XFile.mimeType` is filled in on the
  /// web and usually null on Android, where the extension is all there is.
  static String? _typeOf(XFile file) {
    final declared = file.mimeType?.toLowerCase();
    if (declared != null && _allowed.contains(declared)) return declared;

    final name = file.name.toLowerCase();
    for (final entry in _byExtension.entries) {
      if (name.endsWith(entry.key)) return entry.value;
    }
    // image_picker only ever returns images, so a name with no extension —
    // which happens on some Android camera intents — is a JPEG.
    return declared == null ? 'image/jpeg' : null;
  }

  static const _byExtension = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.heif': 'image/heif',
    '.pdf': 'application/pdf',
  };

  static const _allowed = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
    'application/pdf',
  };
}

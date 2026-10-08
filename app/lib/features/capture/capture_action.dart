import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/capture/models.dart';
import '../../core/capture/text_reader.dart';
import '../../core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import 'photo_library_sheet.dart';

/// What [CaptureAction.pick] hands back: the picture, and — chosen in
/// « Photos » (114) — the document it already is.
typedef PickedPhoto = ({Uint8List bytes, String contentType, CapturedDocument? from});

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
      if (!context.mounted) return false;
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('La caméra n\'est pas disponible : {error}', {'error': error})),
      ));
      return false;
    }

    if (file == null) return false; // Cancelled. Say nothing.

    final bytes = await file.readAsBytes();
    final contentType = _typeOf(file);

    if (contentType == null) {
      if (!context.mounted) return false;
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('Ce type de fichier ne peut pas être envoyé.')),
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

      if (!context.mounted) return false;
      messenger.showSnackBar(SnackBar(
        content: Text(id == null
            // Not an error. The bytes are on the device and will go when
            // there is signal — saying "échec" here would teach her to stop
            // taking photographs when the connection is poor, which is
            // exactly when they matter.
            ? context.tr('Photo gardée. Elle partira dès qu’il y a du réseau.')
            : context.tr('Photo enregistrée.')),
      ));
      return true;
    } on CaptureException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
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
              title: Text(context.tr('Prendre une photo')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                  kIsWeb ? context.tr('Choisir un fichier') : context.tr('Choisir une photo')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !context.mounted) return false;
    return take(context,
        orgId: orgId, capture: capture, source: source, kind: kind);
  }

  /// Picks a photograph and hands back the bytes without filing anything —
  /// the notebook reader wants an image to read, not a gallery entry.
  /// Returns null on cancel, and says why on any other dead end.
  ///
  /// For an article or a service, [photos] (with [orgId]) adds « Choisir
  /// dans Photos » (114): one of the business's own photographs, handed
  /// back with the document it already is ([PickedPhoto.from]) — [hang]
  /// then gives it to the article.
  static Future<PickedPhoto?> pick(
    BuildContext context, {
    String? orgId,
    CaptureRepository? photos,
  }) async {
    final library = orgId != null && photos != null && photos.isConfigured;
    final source = await showModalBottomSheet<Object>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(context.tr('Prendre une photo')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            if (library)
              ListTile(
                key: const Key('pick-from-photos'),
                leading: const Icon(Icons.collections_outlined),
                title: Text(context.tr('Choisir dans Photos')),
                subtitle: Text(context.tr('Une photo déjà prise par votre activité')),
                onTap: () => Navigator.of(sheetContext).pop(_fromPhotos),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                  kIsWeb ? context.tr('Choisir un fichier') : context.tr('Choisir une photo')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return null;
    if (source == _fromPhotos) {
      return _fromLibrary(context, orgId: orgId!, capture: photos!);
    }
    if (source is! ImageSource) return null;

    final messenger = ScaffoldMessenger.of(context);
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );
    } on Exception catch (error) {
      if (!context.mounted) return null;
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('La caméra n\'est pas disponible : {error}', {'error': error})),
      ));
      return null;
    }
    if (file == null) return null; // Cancelled. Say nothing.

    final contentType = _typeOf(file);
    if (contentType == null || !contentType.startsWith('image/')) {
      if (!context.mounted) return null;
      messenger.showSnackBar(SnackBar(
        content: Text(context.tr('Ce type de fichier ne peut pas être lu.')),
      ));
      return null;
    }
    return (bytes: await file.readAsBytes(), contentType: contentType, from: null);
  }

  static const _fromPhotos = 'photos';

  static Future<PickedPhoto?> _fromLibrary(
    BuildContext context, {
    required String orgId,
    required CaptureRepository capture,
  }) async {
    final doc = await showPhotoLibrary(context, orgId: orgId, capture: capture);
    if (doc == null || !context.mounted) return null;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Already held: the sheet drew it from these very bytes.
      final bytes = await capture.objectBytes(doc.key);
      final type = doc.contentType;
      return (
        bytes: bytes,
        contentType: type != null && type.startsWith('image/') ? type : 'image/jpeg',
        from: doc,
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      return null;
    }
  }

  /// Gives a picked photo to an article or a service, through the one
  /// server path (file_document; 100's photo limit holds the door there,
  /// and its refusal is said in French by the caller).
  ///
  /// A photo from « Photos » that is about nothing yet goes onto an article
  /// that has none, as it is: no second copy in Photos. Any other — one
  /// another article wears (that one keeps it), one filed on an entry, or
  /// one for an article that already has a newer photo (the newest is the
  /// one shown) — is sent again as the article's own picture, as a new one
  /// is. Returns the document now on the article, or null when a new
  /// picture waits for signal on the phone.
  static Future<String?> hang(
    CaptureRepository capture, {
    required String orgId,
    required String productId,
    required String name,
    required PickedPhoto photo,
    required bool hadPhoto,
  }) async {
    final from = photo.from;
    if (from != null && from.productId == null && from.entryId == null && !hadPhoto) {
      await capture.file(
        documentId: from.id,
        productId: productId,
        caption: (from.caption?.trim().isEmpty ?? true) ? name : null,
      );
      return from.id;
    }
    final id = await capture.capture(
      orgId: orgId,
      bytes: photo.bytes,
      contentType: photo.contentType,
      kind: 'product_photo',
      caption: name,
    );
    if (id != null) await capture.file(documentId: id, productId: productId);
    return id;
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

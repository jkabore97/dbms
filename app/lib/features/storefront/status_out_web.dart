import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storefront/storefront_repository.dart' show whatsappShareUrl;
import 'package:web/web.dart' as web;

import 'status_out.dart';

StatusPlatform deviceStatusPlatform() => const _WebStatusPlatform();

/// The browser's half: Web Share with the file where the browser has it
/// (Chrome on Android, Safari), and a download always.
class _WebStatusPlatform implements StatusPlatform {
  const _WebStatusPlatform();

  @override
  StatusOs get os => StatusOs.web;

  web.File _file(Uint8List png, String name) => web.File(
        [png.toJS].toJS,
        name,
        web.FilePropertyBag(type: 'image/png'),
      );

  @override
  Future<bool> canShareFiles() async {
    try {
      final navigator = web.window.navigator;
      if (!navigator.hasProperty('canShare'.toJS).toDart) return false;
      final probe = web.ShareData(files: [_file(Uint8List(8), 'mara.png')].toJS);
      return navigator.canShare(probe);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> whatsApp(Uint8List png, String name, String text) async => false;

  @override
  Future<bool> facebookStory(Uint8List png, String appId) async => false;

  @override
  Future<void> text(String text) async {
    await launchUrl(Uri.parse(whatsappShareUrl(text)), mode: LaunchMode.externalApplication);
  }

  @override
  Future<void> system(Uint8List png, String name, String text) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: name)],
      text: text,
    ));
  }

  @override
  Future<bool> save(Uint8List png, String name) async {
    try {
      final blob = web.Blob([png.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
      final url = web.URL.createObjectURL(blob);
      final a = web.HTMLAnchorElement()
        ..href = url
        ..download = name
        ..style.display = 'none';
      web.document.body?.append(a);
      a.click();
      a.remove();
      // Revoked a moment later: some browsers start the download after
      // the click has returned.
      Future<void>.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
      return true;
    } catch (_) {
      return false;
    }
  }
}

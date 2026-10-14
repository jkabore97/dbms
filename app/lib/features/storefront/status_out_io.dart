import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'status_out.dart';

StatusPlatform deviceStatusPlatform() => const _ChannelStatusPlatform();

/// The phone's half: `bf.kaj.app/status` in MainActivity.kt and
/// AppDelegate.swift for what no plugin does (WhatsApp by its package,
/// Facebook's stories, the photos), share_plus for the system sheet. A
/// method the platform does not have answers false, and the caller falls
/// back to the sheet.
class _ChannelStatusPlatform implements StatusPlatform {
  const _ChannelStatusPlatform();

  static const _channel = MethodChannel('bf.kaj.app/status');

  @override
  StatusOs get os => switch (defaultTargetPlatform) {
        TargetPlatform.android => StatusOs.android,
        TargetPlatform.iOS => StatusOs.ios,
        _ => StatusOs.other,
      };

  Future<bool> _ask(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> canShareFiles() async => false;

  @override
  Future<bool> whatsApp(Uint8List png, String name, String text) =>
      _ask('whatsapp', {'bytes': png, 'name': name, 'text': text});

  @override
  Future<bool> facebookStory(Uint8List png, String appId) =>
      _ask('facebook', {'bytes': png, 'appId': appId});

  @override
  Future<bool> save(Uint8List png, String name) => _ask('save', {'bytes': png, 'name': name});

  @override
  Future<void> text(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Future<void> system(Uint8List png, String name, String text) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png', name: name)],
      text: text,
    ));
  }
}

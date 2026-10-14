import 'dart:typed_data';

import 'status_out_io.dart' if (dart.library.js_interop) 'status_out_web.dart';

/// Mara's Facebook App ID: public — it names the app that sends a story to
/// Facebook, it opens nothing. A build may name another with
/// `--dart-define=FACEBOOK_APP_ID=…`; one given empty keeps Mara's (an
/// empty define is not an absent one, and Facebook refuses an empty ID).
const facebookAppId = _facebookAppIdDefined == '' ? '1471844268381528' : _facebookAppIdDefined;
const _facebookAppIdDefined = String.fromEnvironment('FACEBOOK_APP_ID');

/// Where the picture goes from the foot of StatusPreview (140).
enum StatusTarget {
  /// Android: straight to WhatsApp, which asks « Mon statut » or a contact.
  /// iOS: the system sheet (Apple lets no app post a status directly).
  whatsapp,

  /// The Facebook story composer, the picture as its background.
  facebook,

  /// The system sheet: Telegram, Instagram, Messenger, SMS… On the web,
  /// the browser's own share (« Partager… »).
  others,

  /// Into the phone's photos; on the web, a download.
  save,
}

/// The phone the picture leaves from.
enum StatusOs { android, ios, web, other }

/// What became of it.
enum StatusOutcome {
  /// The app asked for opened with the picture.
  direct,

  /// That app is not on the phone: the system sheet opened instead.
  fallback,

  /// Saved to the photos (downloaded on the web).
  saved,

  /// Nothing could take it.
  failed,
}

/// The phone's side, behind one interface so a test can stand in for it.
/// The real one is the `bf.kaj.app/status` channel (MainActivity.kt,
/// AppDelegate.swift) with share_plus for the system sheet; on the web, the
/// browser's Web Share and a download.
abstract class StatusPlatform {
  /// The device's own.
  factory StatusPlatform.device() => deviceStatusPlatform();

  StatusOs get os;

  /// The browser can share files (Web Share level 2). False off the web.
  Future<bool> canShareFiles();

  /// Android: the PNG sent to WhatsApp (com.whatsapp, then
  /// com.whatsapp.w4b). False when neither is installed.
  Future<bool> whatsApp(Uint8List png, String name, String text);

  /// Android: com.facebook.stories.ADD_TO_STORY; iOS: facebook-stories://
  /// with the pasteboard. False when Facebook is not installed.
  Future<bool> facebookStory(Uint8List png, String appId);

  /// « Le lien »: the message with the link, to a contact — the system
  /// sheet on a phone (WhatsApp is in it), WhatsApp's own « send to… »
  /// page (wa.me) on the web.
  Future<void> text(String text);

  /// The system share sheet with the file (and the text).
  Future<void> system(Uint8List png, String name, String text);

  /// Into the photos (Android MediaStore, iOS Photos add-only); a download
  /// on the web. False when it could not be saved.
  Future<bool> save(Uint8List png, String name);
}

/// The four ways out, what each platform shows, and each one's fallback.
class StatusSharer {
  StatusSharer(this.platform);

  final StatusPlatform platform;

  /// The buttons the foot shows, in order. On the web the direct ones are
  /// hidden — a browser cannot reach WhatsApp's status or Facebook's
  /// stories — and « Partager… » is there only where the browser shares
  /// files; « Enregistrer » (a download) always is.
  Future<List<StatusTarget>> targets() async {
    if (platform.os == StatusOs.web) {
      final share = await platform.canShareFiles().catchError((Object _) => false);
      return [if (share) StatusTarget.others, StatusTarget.save];
    }
    return StatusTarget.values;
  }

  /// iOS only: WhatsApp's button opens the system sheet, so say where to go.
  bool get whatsAppHint => platform.os == StatusOs.ios;

  Future<StatusOutcome> send(StatusTarget target, Uint8List png, String name, String text) async {
    Future<StatusOutcome> sheet(StatusOutcome ok) async {
      await platform.system(png, name, text);
      return ok;
    }

    try {
      switch (target) {
        case StatusTarget.whatsapp:
          if (platform.os == StatusOs.android) {
            final sent = await platform.whatsApp(png, name, text).catchError((Object _) => false);
            return sent ? StatusOutcome.direct : await sheet(StatusOutcome.fallback);
          }
          // iOS, and anything else: the system sheet, where WhatsApp is.
          return await sheet(StatusOutcome.direct);
        case StatusTarget.facebook:
          if (platform.os == StatusOs.android || platform.os == StatusOs.ios) {
            final sent =
                await platform.facebookStory(png, facebookAppId).catchError((Object _) => false);
            return sent ? StatusOutcome.direct : await sheet(StatusOutcome.fallback);
          }
          return await sheet(StatusOutcome.fallback);
        case StatusTarget.others:
          return await sheet(StatusOutcome.direct);
        case StatusTarget.save:
          final saved = await platform.save(png, name);
          if (saved) return StatusOutcome.saved;
          // A phone that keeps no photo for us (Android 9 and older ask a
          // storage right Mara does not hold): the sheet, which can save.
          if (platform.os == StatusOs.web) return StatusOutcome.failed;
          return await sheet(StatusOutcome.fallback);
      }
    } catch (_) {
      return StatusOutcome.failed;
    }
  }
}

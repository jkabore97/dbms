import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Which build this is, and whether a newer one is out.
///
/// The web app is whatever was deployed last, every time the page loads.
/// The Android app is whatever APK was installed the day it was installed,
/// and nothing told the phone a newer one existed: every fix shipped since
/// only reached phones that were reinstalled by hand. This closes that gap
/// from the app's side. Every build carries the commit it was made from
/// (`--dart-define=BUILD_SHA`); the web deploy writes the same commit into
/// `version.json` beside the app. When the two differ, a banner says so —
/// "Télécharger" on a phone, "Recharger" in a browser tab that has been
/// open since before a deploy.
///
/// A build with no BUILD_SHA (a local `flutter run`) never shows the
/// banner: it has nothing to compare against, and a developer's build is
/// newer than anything deployed anyway.
const buildSha = String.fromEnvironment('BUILD_SHA');

/// Where the deployed app lives, and therefore where its version.json is.
/// On the web the page's own origin is used instead, so a preview deploy
/// compares against itself rather than against production.
const productionSite = 'https://dbms.kabore-boss.workers.dev';

/// What `version.json` says about the deployed build.
class UpdateInfo {
  const UpdateInfo({required this.sha, this.apkUrl, this.builtAt});

  final String sha;

  /// Where the phone downloads the new APK: the latest GitHub release.
  final String? apkUrl;
  final DateTime? builtAt;

  /// Null when the text is not the file we expect — a Worker answering
  /// index.html for an unknown path, a proxy page — so a wrong answer never
  /// becomes a banner.
  static UpdateInfo? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final sha = json['sha'];
      if (sha is! String || sha.trim().isEmpty) return null;
      final built = json['built_at'];
      return UpdateInfo(
        sha: sha.trim(),
        apkUrl: (json['apk'] as String?)?.trim(),
        builtAt: built is String ? DateTime.tryParse(built) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Fetches version.json, remembers the answer, and says whether it is newer.
class UpdateCheck extends ChangeNotifier {
  UpdateCheck({
    required this.fetch,
    this.currentSha = buildSha,
    this.isWeb = kIsWeb,
    Uri? versionUrl,
  }) : versionUrl = versionUrl ?? _defaultVersionUrl(isWeb);

  /// Reads a URL and answers its body, or throws. Injected so a test needs
  /// no network and the app needs no second HTTP client.
  final Future<String> Function(Uri uri) fetch;
  final String currentSha;
  final bool isWeb;
  final Uri versionUrl;

  UpdateInfo? _available;

  /// The newer build, or null when this one is current (or unknown).
  UpdateInfo? get available => _available;

  bool _dismissed = false;
  bool get dismissed => _dismissed;

  /// Whether to draw the banner right now.
  bool get shouldShow => _available != null && !_dismissed;

  static Uri _defaultVersionUrl(bool isWeb) {
    final origin = isWeb && Uri.base.scheme.startsWith('http')
        ? Uri.base.origin
        : productionSite;
    return Uri.parse('$origin/version.json');
  }

  /// True when [info] describes a different build than this one. A build
  /// with no sha of its own compares against nothing.
  bool isNewer(UpdateInfo info) =>
      currentSha.isNotEmpty && info.sha.isNotEmpty && info.sha != currentSha;

  /// One look. Quiet on any failure: no signal is not news, and the next
  /// look will try again.
  Future<void> check() async {
    final UpdateInfo? info;
    try {
      // A cache-busting query, because the Worker and the browser both
      // cache a small static file for a while, and a stale version.json is
      // exactly the one that would say "you are current" after a deploy.
      final uri = versionUrl.replace(queryParameters: {
        ...versionUrl.queryParameters,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      info = UpdateInfo.parse(await fetch(uri));
    } catch (_) {
      return;
    }
    if (info == null) return;
    final next = isNewer(info) ? info : null;
    final changed = (next?.sha) != (_available?.sha);
    _available = next;
    if (next == null) _dismissed = false;
    if (changed) notifyListeners();
  }

  /// "Plus tard": hides the banner until the next newer build.
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }
}

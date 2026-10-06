import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web shell says Kaj, not "a new Flutter project".
///
/// Every surface a stranger meets first — the browser tab, the home-screen
/// install, the WhatsApp preview of a shared vitrine — is drawn from these
/// two files, and both shipped for months as `flutter create` left them.
/// This pins the identity so a regenerated template can never quietly put
/// the Flutter logo back on the shop's front door.
void main() {
  final web = Directory('web').existsSync() ? 'web' : 'app/web';

  test('the manifest names the app and wears its colours', () {
    final manifest = jsonDecode(File('$web/manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(manifest['short_name'], 'Mara');
    expect(manifest['name'], startsWith('Mara'));
    expect(manifest['description'], isNot(contains('Flutter')));
    expect(manifest['lang'], 'fr');
    // The paper, not Flutter's blue.
    expect(manifest['theme_color'], '#1E2560');
    expect(manifest['background_color'], '#1E2560');
    // A tablet or a desktop window is not forced to portrait.
    expect(manifest['orientation'], 'any');
  });

  test('the page carries the title, the description and the share card', () {
    final html = File('$web/index.html').readAsStringSync();
    expect(html, contains('<html lang="fr">'));
    expect(html, contains('<title>Mara — Au Service du Peuple</title>'));
    expect(html, isNot(contains('kaj_app')));
    expect(html, isNot(contains('A new Flutter project')));
    expect(html, contains('property="og:title"'));
    expect(html, contains('property="og:image" content="https://'));
    expect(html, contains('name="theme-color" content="#1E2560"'));
    // The paper page shown while the engine loads, and its exit.
    expect(html, contains('id="mara-splash"'));
    expect(html, contains('flutter-first-frame'));
  });

  test('the icons are no longer the template logo', () {
    // `flutter create` writes these exact byte sizes; ours differ.
    const template = {
      'icons/Icon-192.png': 5292,
      'icons/Icon-512.png': 8252,
      'icons/Icon-maskable-192.png': 5594,
      'icons/Icon-maskable-512.png': 20998,
      'favicon.png': 917,
    };
    for (final e in template.entries) {
      final size = File('$web/${e.key}').lengthSync();
      expect(size, isNot(e.value), reason: '${e.key} is still the template');
    }
  });
}

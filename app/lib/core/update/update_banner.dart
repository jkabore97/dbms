import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'reload_stub.dart' if (dart.library.js_interop) 'reload_web.dart';
import 'update_check.dart';

/// The one strip that tells a phone — or a stale tab — that Kaj moved on.
///
/// Wraps the whole app, above every page, so it is seen wherever somebody
/// is when the look comes back. Says one sentence and offers one action:
/// download the APK on a phone, reload in a browser. "Plus tard" hides it
/// until the next newer build; it never nags twice for the same one.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.check, required this.child});

  final UpdateCheck check;
  final Widget child;

  Future<void> _act(BuildContext context) async {
    if (check.isWeb) {
      reloadPage();
      return;
    }
    final url = check.available?.apkUrl;
    if (url == null || url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text('Ouvrez ce lien dans votre navigateur : $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: check,
      builder: (context, _) {
        if (!check.shouldShow) return child;
        final theme = Theme.of(context);
        return Column(
          children: [
            Material(
              color: theme.colorScheme.inverseSurface,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      Icon(Icons.system_update_alt,
                          size: 20, color: theme.colorScheme.onInverseSurface),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          check.isWeb
                              ? 'Une nouvelle version de Kaj est en ligne.'
                              : 'Une nouvelle version de Kaj est disponible.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onInverseSurface),
                        ),
                      ),
                      TextButton(
                        onPressed: check.dismiss,
                        child: Text('Plus tard',
                            style: TextStyle(
                                color: theme.colorScheme.onInverseSurface)),
                      ),
                      FilledButton(
                        onPressed: () => _act(context),
                        child: Text(check.isWeb ? 'Recharger' : 'Télécharger'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

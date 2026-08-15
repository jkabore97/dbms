import 'package:flutter/material.dart';

import '../../core/l10n/locale_controller.dart';
import '../../core/nav/app_scope.dart';
import '../../l10n/strings.dart';

/// Choosing the language of this device.
///
/// Two decisions shape this screen, and both are about the person most likely
/// to need it — somebody who cannot comfortably read the language the app is
/// currently showing:
///
///   * **Every language is written in itself.** "English" not "Anglais",
///     "Mòoré" not "Mooré (langue locale)". A list of language names in the
///     current language is unreadable to exactly the person hunting for
///     theirs.
///   * **The change is immediate, no save button.** Tapping a language is the
///     preview and the decision at once, and if it was the wrong tap, the way
///     back is written in a language the person can read — their own.
///
/// The choice belongs to the device, not the account or the business:
/// language is personal, two people behind one counter can read different
/// ones, and it has to work before sign-in — the sign-in screen is where
/// somebody stuck in the wrong language is most stuck.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final locale = AppScope.of(context).localeController;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.language)),
      body: ListenableBuilder(
        listenable: locale,
        builder: (context, _) {
          final systemResolved =
              lookupStrings(LocaleController.platformResolved()).languageName;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Text(
                  strings.languageSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              _LanguageTile(
                title: strings.languageSystem,
                subtitle: strings.languageSystemSubtitle(systemResolved),
                selected: locale.chosen == null,
                onTap: () => locale.choose(null),
              ),
              const Divider(height: 24),
              for (final l in enabledLocales)
                _LanguageTile(
                  // The language's own name for itself, looked up in that
                  // language rather than the current one — see above.
                  title: lookupStrings(l).languageName,
                  selected: locale.chosen == l,
                  onTap: () => locale.choose(l),
                ),
            ],
          );
        },
      ),
    );
  }

}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: selected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : const Icon(Icons.circle_outlined),
      onTap: onTap,
    );
  }
}

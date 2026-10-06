import 'package:flutter/widgets.dart';

import '../../l10n/strings.dart';
import 'en.dart';

/// Every screen's words, in the person's language (French or English).
///
/// The French phrase is the key: the code stays readable in the language
/// the app was written in, and a phrase with no English yet simply shows in
/// French rather than as a key name. `{name}` in a phrase is filled from
/// [args]: `context.tr('{n} articles', {'n': 3})`.
///
/// Mooré and Dioula read French here until a speaker writes them (see
/// locale_controller.dart).
extension Tr on BuildContext {
  /// The language is the app's own — the Localizations that carries its
  /// Strings delegate, which follows the person's choice in Compte ›
  /// Langue. A tree without it (a bare test, say) reads French, the
  /// language the app was written in.
  ///
  /// Found without subscribing, so a screen may ask from initState; the app
  /// rebuilds its whole tree when the language changes (main.dart), so no
  /// phrase is left in the old one.
  String tr(String fr, [Map<String, Object?> args = const {}]) =>
      translate(trLanguage, fr, args);

  /// 'en' or 'fr' (any other language reads French).
  String get trLanguage {
    final l = findAncestorWidgetOfExactType<Localizations>();
    final ours = l != null && l.delegates.any((d) => d.type == Strings);
    return ours ? l.locale.languageCode : 'fr';
  }
}

String translate(String language, String fr, [Map<String, Object?> args = const {}]) {
  var s = language == 'en' ? (enStrings[fr] ?? fr) : fr;
  for (final e in args.entries) {
    s = s.replaceAll('{${e.key}}', '${e.value}');
  }
  return s;
}

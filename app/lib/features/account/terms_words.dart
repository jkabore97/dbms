import 'package:flutter/widgets.dart';

import '../../core/l10n/tr.dart';
import '../../core/terms/terms.dart';

/// The four documents of 142 by their names, in the reader's language.
String termsDocName(BuildContext context, String doc) => switch (doc) {
      TermsDoc.terms => context.tr('Conditions d\'utilisation'),
      TermsDoc.privacy => context.tr('Politique de confidentialité'),
      TermsDoc.seller => context.tr('Engagements du vendeur'),
      TermsDoc.courier => context.tr('Charte du livreur'),
      _ => doc,
    };

/// Where an acceptance was given.
String termsPlatformName(BuildContext context, String platform) => switch (platform) {
      'web' => context.tr('Site web'),
      'android' => 'Android',
      'ios' => 'iPhone',
      _ => platform,
    };

/// « 14 oct. 2026, 10:32 » / « 14 Oct 2026, 10:32 », on the phone's clock.
/// Said by hand: a page of the console needs no date locale loaded.
String termsDateTime(BuildContext context, DateTime at) {
  const fr = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.',
    'nov.', 'déc.'];
  const en = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final t = at.toLocal();
  final month = (context.trLanguage == 'en' ? en : fr)[t.month - 1];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day} $month ${t.year}, ${two(t.hour)}:${two(t.minute)}';
}

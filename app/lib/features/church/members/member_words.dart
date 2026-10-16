import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;
import 'package:intl/intl.dart';

import '../../../core/association/books_start.dart';
import '../../../core/association/members.dart';
import '../../../core/auth/models.dart';
import '../../../core/format/money.dart';
import '../../../core/l10n/tr.dart';

/// The words the members' screens share (148): who may change the list,
/// where a member stands, and the WhatsApp message.

/// Who adds, edits and removes members: what 148's policies allow — a
/// member of the business who is not only an observer or an approver, in a
/// business that is not suspended. Mara's own people are no member of it,
/// so they read and change nothing here (the server refuses them too).
bool canWriteMembers(OrgSummary org) =>
    !org.suspended &&
    org.roles.any((r) => r != 'observer' && r != 'approver' && r != 'platform_admin');

/// « Membre depuis mars 2024 ».
String memberSince(String lang, DateTime? since) {
  if (since == null) return '';
  return translate(lang, 'Membre depuis {date}', {
    'date': DateFormat('MMMM yyyy', intlLocale(lang)).format(since),
  });
}

/// When a period starts, as it is said: « septembre 2026 » for a month,
/// « le 5 oct. » for a week, « 2025 » for a year.
String periodStart(String lang, DateTime start, ContributionPeriod period) {
  final locale = intlLocale(lang);
  return switch (period) {
    ContributionPeriod.month => DateFormat('MMMM yyyy', locale).format(start),
    ContributionPeriod.week => translate(lang, 'le {date}',
        {'date': DateFormat('d MMM', locale).format(start)}),
    ContributionPeriod.year => '${start.year}',
  };
}

/// « À jour », « À payer ce mois-ci », « En retard depuis septembre 2026 ».
String duesLabel(String lang, MemberDues dues, ContributionPeriod? period) {
  final p = period ?? ContributionPeriod.month;
  switch (dues.status) {
    case DuesStatus.upToDate:
      return translate(lang, 'À jour');
    case DuesStatus.due:
      return switch (p) {
        ContributionPeriod.week => translate(lang, 'À payer cette semaine'),
        ContributionPeriod.month => translate(lang, 'À payer ce mois-ci'),
        ContributionPeriod.year => translate(lang, 'À payer cette année'),
      };
    case DuesStatus.late:
      final since = dues.lateSince;
      if (since == null) return translate(lang, 'En retard');
      return translate(lang, 'En retard depuis {since}', {'since': periodStart(lang, since, p)});
  }
}

/// The usual cotisation, said: « 1 000 FCFA par mois ».
String usualCotisation(String lang, ContributionDefault c, String currency) {
  final amount = moneyFormat(currency).format(c.amount);
  final args = {'amount': amount};
  return switch (c.period) {
    ContributionPeriod.week => translate(lang, '{amount} par semaine', args),
    ContributionPeriod.month => translate(lang, '{amount} par mois', args),
    ContributionPeriod.year => translate(lang, '{amount} par an', args),
  };
}

/// The message « Écrire sur WhatsApp » opens with: a greeting from the
/// association, and — when the member is late or this period is still to
/// pay — a polite reminder, never a demand.
String whatsappMessage(
  String lang, {
  required AssociationMember member,
  required String orgName,
  ContributionDefault? usual,
  String currency = 'XOF',
}) {
  final hello = translate(lang, 'Bonjour {name}, ici {org}.', {
    'name': member.fullName,
    'org': orgName,
  });
  final dues = member.dues;
  if (dues == null || usual == null) return hello;
  final amount = usualCotisation(lang, usual, currency);
  switch (dues.status) {
    case DuesStatus.late:
      final since = dues.lateSince;
      return '$hello ${translate(lang, 'Petit rappel amical : votre cotisation ({amount}) est en attente depuis {since}. Merci beaucoup, et à bientôt !', {
        'amount': amount,
        'since': since == null ? '' : periodStart(lang, since, usual.period),
      })}';
    case DuesStatus.due:
      return '$hello ${translate(lang, 'Petit rappel : la cotisation ({amount}) peut être versée quand vous le pourrez. Merci beaucoup !', {
        'amount': amount,
      })}';
    case DuesStatus.upToDate:
      return hello;
  }
}

/// wa.me with the message: the number's digits only.
Uri whatsappLink(String phone, String message) => Uri.parse(
    'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}?text=${Uri.encodeComponent(message)}');

/// Two letters for the avatar: « M0 » for « Membre n° 01 » reads badly,
/// so the first letters of the first two words that start with a letter.
String initialsOf(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && RegExp(r'^[A-Za-zÀ-ÿ]').hasMatch(w))
      .toList();
  if (words.isEmpty) return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  return words.take(2).map((w) => w.substring(0, 1).toUpperCase()).join();
}

/// A phone where a figure beside a name squeezes the name: 320 px at 1.3
/// (the width the text has, in its own size, under about 340).
bool isNarrow(BuildContext context) {
  final mq = MediaQuery.of(context);
  return mq.size.width / mq.textScaler.scale(1) < 340;
}

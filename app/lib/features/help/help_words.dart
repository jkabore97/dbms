import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/help/help_repository.dart' show helpRef;
import '../../core/l10n/tr.dart';

/// « Demander un formateur » (143): what a request is about. Every kind
/// gets the same eight, « Autre » last; a farm adds its batches and its
/// stock, an association its members, its dues and its events. The keys are
/// 133's where one fitted (ventes is the till and the sales, equipe the
/// account and the team, bandes the batches and harvests, contributions
/// the dues) and three new ones (catalogue, livraison, evenements, 138).
/// The server takes any of them.
List<String> helpSubjectsFor(String profile) => [
  'catalogue',
  'vitrine',
  'ventes',
  'factures',
  'livraison',
  'rapports',
  'equipe',
  if (profile == 'farm') ...const ['bandes', 'stock'],
  if (profile == 'association' || profile == 'church')
    ...const ['membres', 'contributions', 'evenements'],
  'autre',
];

/// A subject's words. [profile] says whose: a farm's « stock » is its own
/// (« Stock de la ferme »), a shop's older requests' plain « Stock ».
String helpSubjectLabel(
  BuildContext context,
  String subject, {
  String? profile,
}) => switch (subject) {
  'catalogue' => context.tr('Articles / Catalogue'),
  'vitrine' => context.tr('Vitrine'),
  'ventes' => context.tr('Caisse / Ventes'),
  'factures' => context.tr('Factures'),
  'livraison' => context.tr('Livraison'),
  'rapports' => context.tr('Rapports'),
  'equipe' => context.tr('Compte / Équipe'),
  'bandes' => context.tr('Bandes / Récoltes'),
  'stock' =>
    profile == 'farm' ? context.tr('Stock de la ferme') : context.tr('Stock'),
  'membres' => context.tr('Membres'),
  'contributions' => context.tr('Cotisations'),
  'evenements' => context.tr('Événements'),
  'commandes' => context.tr('Commandes'),
  _ => context.tr('Autre'),
};

/// Each subject's icon, for the flow's big choices.
IconData helpSubjectIcon(String subject) => switch (subject) {
  'catalogue' => Icons.inventory_2_outlined,
  'vitrine' => Icons.storefront_outlined,
  'ventes' => Icons.point_of_sale_outlined,
  'factures' => Icons.receipt_long_outlined,
  'livraison' => Icons.local_shipping_outlined,
  'rapports' => Icons.bar_chart_outlined,
  'equipe' => Icons.groups_outlined,
  'bandes' => Icons.grass_outlined,
  'stock' => Icons.warehouse_outlined,
  'membres' => Icons.people_outline,
  'contributions' => Icons.volunteer_activism_outlined,
  'evenements' => Icons.event_outlined,
  _ => Icons.help_outline,
};

/// How to be helped, in the flow's order.
const helpContacts = ['whatsapp', 'call', 'visit'];

String helpContactLabel(BuildContext context, String contact) =>
    switch (contact) {
      'call' => context.tr('Appel'),
      'visit' => context.tr('Venir me voir'),
      _ => context.tr('WhatsApp'),
    };

IconData helpContactIcon(String contact) => switch (contact) {
  'call' => Icons.call_outlined,
  'visit' => Icons.directions_walk_outlined,
  _ => Icons.chat_outlined,
};

String helpKindLabel(BuildContext context, String profile) => switch (profile) {
  'farm' => context.tr('Ferme'),
  'association' || 'church' => context.tr('Association'),
  _ => context.tr('Boutique'),
};

/// The first message of a WhatsApp to Mara (143), in the person's language,
/// so whoever answers knows who writes before reading a word:
///
///     [PRO] Bonjour Mara, j'ai besoin d'aide.
///     Entreprise : Ferme Horizon Vert (Ferme · Pro)
///     Réf. : 3F2A91C0
///     Page : Aide
///
/// « [PRO] » only for a Pro business; the reference is [helpRef] — the
/// command center's search finds it. [page] is where the person came from.
String helpWhatsAppText(
  BuildContext context,
  OrgSummary org, {
  required bool pro,
  String? page,
  String? ref,
}) {
  final lines = [
    '${pro ? '[PRO] ' : ''}${context.tr('Bonjour Marakaj, j\'ai besoin d\'aide.')}',
    context.tr('Entreprise : {name} ({kind} · {plan})', {
      'name': org.name.trim(),
      'kind': helpKindLabel(context, org.profile),
      'plan': pro ? 'Pro' : 'Basic',
    }),
    context.tr('Réf. : {ref}', {'ref': ref ?? helpRef(org.id)}),
    if (page != null && page.trim().isNotEmpty)
      context.tr('Page : {page}', {'page': page.trim()}),
  ];
  return lines.join('\n');
}

/// The subject of an e-mail to Mara: the same name and reference.
String helpEmailSubject(
  BuildContext context,
  OrgSummary org, {
  required bool pro,
  String? ref,
}) => context.tr('Aide Marakaj — {name} · Réf. {ref}{pro}', {
  'name': org.name.trim(),
  'ref': ref ?? helpRef(org.id),
  'pro': pro ? ' · PRO' : '',
});

/// « 07:00 » on Ouagadougou's clock (UTC all year).
String helpClock(DateTime t) {
  final u = t.toUtc();
  return '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}';
}

/// « 7:00–21:00 ».
String helpHoursText(int open, int close) =>
    '${open.toString().padLeft(2, '0')}:00–${close.toString().padLeft(2, '0')}:00';

/// « mer. 15/10 · 10:00 » — a chosen time, on Ouagadougou's clock.
String helpWhen(BuildContext context, DateTime t, {DateTime? now}) {
  final u = t.toUtc();
  final n = (now ?? DateTime.now()).toUtc();
  final days = DateTime.utc(
    u.year,
    u.month,
    u.day,
  ).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
  final clock = helpClock(t);
  if (days == 0) return context.tr('aujourd\'hui à {time}', {'time': clock});
  if (days == 1) return context.tr('demain à {time}', {'time': clock});
  return context.tr('le {d} à {time}', {
    'd':
        '${u.day.toString().padLeft(2, '0')}/${u.month.toString().padLeft(2, '0')}',
    'time': clock,
  });
}

/// When a request made now, out of the hours, is answered: « Un formateur
/// vous répondra demain à partir de 7 h » (or « aujourd'hui », before the
/// opening; or the date).
String helpWhenAnswered(
  BuildContext context,
  DateTime nextOpen, {
  DateTime? now,
}) {
  final n = (now ?? DateTime.now()).toUtc();
  final o = nextOpen.toUtc();
  final today = DateTime.utc(n.year, n.month, n.day);
  final day = DateTime.utc(o.year, o.month, o.day);
  final days = day.difference(today).inDays;
  final hour = o.minute == 0
      ? '${o.hour}'
      : '${o.hour}:${o.minute.toString().padLeft(2, '0')}';
  if (days <= 0) {
    return context.tr(
      'Un formateur vous répondra aujourd\'hui à partir de {h} h',
      {'h': hour},
    );
  }
  if (days == 1) {
    return context.tr('Un formateur vous répondra demain à partir de {h} h', {
      'h': hour,
    });
  }
  return context.tr('Un formateur vous répondra le {d} à partir de {h} h', {
    'd':
        '${o.day.toString().padLeft(2, '0')}/${o.month.toString().padLeft(2, '0')}',
    'h': hour,
  });
}

/// « 1 min », « 25 min », « 2 h », « 3 j » since [t].
String helpAge(BuildContext context, DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return context.tr('à l\'instant');
  if (d.inMinutes < 60) return context.tr('{n} min', {'n': d.inMinutes});
  if (d.inHours < 24) return context.tr('{n} h', {'n': d.inHours});
  return context.tr('{n} j', {'n': d.inDays});
}

/// The help's own colours (the mockups'): the ink on Mara's caramel (the
/// Pro button, maraCaramel), the green of « en service » and the red of
/// « nouvelle ».
const helpCaramelInk = Color(0xFF2B2118);
const helpGreen = Color(0xFF2E7D4F);
const helpGreenSoft = Color(0xFFE6F2E8);
const helpRed = Color(0xFFB3261E);
const helpRedSoft = Color(0xFFFBE4E2);

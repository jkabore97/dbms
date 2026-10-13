import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';

/// « Besoin d'aide » (136): the subjects a kind of business asks about —
/// seven chips each, « Autre » last. The server takes any of them (133).
List<String> helpSubjectsFor(String profile) => switch (profile) {
  'farm' => const [
    'bandes',
    'stock',
    'ventes',
    'factures',
    'vitrine',
    'equipe',
    'autre',
  ],
  'association' || 'church' => const [
    'contributions',
    'rapports',
    'membres',
    'factures',
    'vitrine',
    'equipe',
    'autre',
  ],
  _ => const [
    'ventes',
    'stock',
    'factures',
    'vitrine',
    'commandes',
    'equipe',
    'autre',
  ],
};

String helpSubjectLabel(BuildContext context, String subject) =>
    switch (subject) {
      'ventes' => context.tr('Ventes'),
      'stock' => context.tr('Stock'),
      'factures' => context.tr('Factures'),
      'vitrine' => context.tr('Vitrine'),
      'commandes' => context.tr('Commandes'),
      'equipe' => context.tr('Équipe'),
      'bandes' => context.tr('Bandes'),
      'contributions' => context.tr('Contributions'),
      'rapports' => context.tr('Rapports'),
      'membres' => context.tr('Membres'),
      _ => context.tr('Autre'),
    };

/// How to be helped, in the sheet's order.
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

/// « 07:00 » on Ouagadougou's clock (UTC all year).
String helpClock(DateTime t) {
  final u = t.toUtc();
  return '${u.hour.toString().padLeft(2, '0')}:${u.minute.toString().padLeft(2, '0')}';
}

/// « 7:00–21:00 ».
String helpHoursText(int open, int close) =>
    '${open.toString().padLeft(2, '0')}:00–${close.toString().padLeft(2, '0')}:00';

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

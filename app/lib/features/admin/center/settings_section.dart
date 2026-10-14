import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/console/command_center.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart' show parseAmount;
import '../../../core/l10n/en.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/nav/router.dart';
import '../../account/support.dart' show Support;
import '../../notify/push_check.dart';
import '../../../core/theme/kaj_card.dart';
import '../../../core/theme/mara_mark.dart';
import 'todo_section.dart' show featureName;
import '../../../core/notify/bell_room.dart';

/// How a setting is typed in.
enum SettingType {
  /// An amount of money (a whole number, but see [decimalSettings]).
  money,

  /// A whole number of things, days or minutes.
  count,

  /// A distance in km.
  km,

  /// A percentage, 0 to 100.
  pct,

  /// Oui / non.
  flag,

  /// Oui / non kept as 1 / 0.
  flag01,

  /// A few words.
  text,

  /// A currency's three letters.
  currency,

  /// A list of words from [SettingDef.options].
  list,
}

class SettingDef {
  const SettingDef(this.key, this.group, this.type, {this.options = const []});

  final String key;
  final String group;
  final SettingType type;
  final List<String> options;
}

/// Réglages: the platform settings the app uses, each with its name. The
/// server checks every value (105's platform_set_setting); test_batch105's
/// TEST 7 proves each of these keys is read by the server, and
/// test/command_center_test.dart that the two lists are the same. Three
/// settings nothing reads since 097 (progress_tools_pct, progress_orders,
/// progress_trial_days) are left out on purpose.
const platformSettingDefs = <SettingDef>[
  SettingDef('pro_price_month', 'pro', SettingType.money),
  SettingDef('pro_price_year', 'pro', SettingType.money),
  // 139: Mara Pro's price in the euro zone and everywhere else, to the
  // cent — what the card charges a business of that zone on the website.
  SettingDef('pro_price_month_eur', 'pro', SettingType.money),
  SettingDef('pro_price_year_eur', 'pro', SettingType.money),
  SettingDef('pro_price_month_usd', 'pro', SettingType.money),
  SettingDef('pro_price_year_usd', 'pro', SettingType.money),
  SettingDef('pro_currency', 'pro', SettingType.currency),
  SettingDef('platform_wave', 'pro', SettingType.text),
  SettingDef('platform_wave_name', 'pro', SettingType.text),
  SettingDef('stripe_on', 'pro', SettingType.flag),
  // 121's stripe_xof_per_usd left Réglages with 139: the card charges each
  // zone's own price in its own currency, nothing is converted.
  // 128: Mara Pro sold through the App Store and Google Play in the store
  // apps — off until both stores answer the payments Worker.
  SettingDef('store_billing_on', 'pro', SettingType.flag),
  // 128 (review S2): the one account, besides the platform's admins, whose
  // businesses a test (sandbox) purchase turns Pro — App Review's.
  SettingDef('store_review_account', 'pro', SettingType.text),
  // 130 (audit M4): empty, any business that account owns; ids (commas or
  // spaces between them), only those.
  SettingDef('store_review_orgs', 'pro', SettingType.text),
  SettingDef('pro_features', 'pro', SettingType.list, options: [
    'payroll', 'team_access', 'analytics', 'accounting', 'currencies', 'tontines',
    'vitrine_plus', 'delivery', 'online_payment',
  ]),
  SettingDef('free_max_staff', 'free', SettingType.count),
  SettingDef('free_max_invoices_month', 'free', SettingType.count),
  SettingDef('free_max_photos', 'free', SettingType.count),
  SettingDef('free_photo_items', 'free', SettingType.count),
  SettingDef('free_history_months', 'free', SettingType.count),
  SettingDef('vitrine_free_basics', 'free', SettingType.flag01),
  SettingDef('vitrine_min_items', 'street', SettingType.count),
  SettingDef('vitrine_min_items_association', 'street', SettingType.count),
  SettingDef('progress_street_pct', 'street', SettingType.pct),
  SettingDef('spots_max_live', 'street', SettingType.count),
  // 139: 7 days only, and Pro pays too — the 30-day prices and
  // pro_free_spots_month stay in the database, inert, out of Réglages.
  // The FCFA prices (the XOF zone, XAF the same number), then the euro
  // zone's and everywhere else's, to the cent.
  SettingDef('spot_price_article_7', 'street', SettingType.money),
  SettingDef('spot_price_shop_7', 'street', SettingType.money),
  SettingDef('spot_price_article_7_eur', 'street', SettingType.money),
  SettingDef('spot_price_shop_7_eur', 'street', SettingType.money),
  SettingDef('spot_price_article_7_usd', 'street', SettingType.money),
  SettingDef('spot_price_shop_7_usd', 'street', SettingType.money),
  SettingDef('delivery_base', 'delivery', SettingType.money),
  SettingDef('delivery_per_km', 'delivery', SettingType.money),
  SettingDef('delivery_currency', 'delivery', SettingType.currency),
  SettingDef('delivery_max_km', 'delivery', SettingType.km),
  SettingDef('delivery_included_km', 'delivery', SettingType.km),
  SettingDef('delivery_share_pct', 'delivery', SettingType.pct),
  SettingDef('own_courier_minutes', 'delivery', SettingType.count),
  SettingDef('stuck_ready_minutes', 'delivery', SettingType.count),
  // 112: what a courier's dossier asks — the licence for a moto or a car,
  // and a number proved on WhatsApp (off until 109's code is set up).
  SettingDef('courier_licence_required', 'delivery', SettingType.flag),
  SettingDef('courier_phone_verified', 'delivery', SettingType.flag),
  // 122: how far from a shop a courier hears of and sees its delivery.
  SettingDef('courier_radius_km', 'delivery', SettingType.km),
  SettingDef('wave_checkout', 'wave', SettingType.flag),
  SettingDef('wave_card', 'wave', SettingType.flag),
  SettingDef('wave_commission_pct', 'wave', SettingType.pct),
  SettingDef('cauris_order_min', 'cauris', SettingType.money),
  SettingDef('cauris_orders_per_customer', 'cauris', SettingType.count),
  SettingDef('cauris_quick_minutes', 'cauris', SettingType.count),
  SettingDef('cauris_expire_days', 'cauris', SettingType.count),
  SettingDef('cauris_unlock_days', 'cauris', SettingType.count),
  SettingDef('cauris_prize_1', 'cauris', SettingType.count),
  SettingDef('cauris_prize_2', 'cauris', SettingType.count),
  SettingDef('cauris_prize_3', 'cauris', SettingType.count),
  // 134: the winners' bell at the week's close — off (the owner: « remove
  // them »); the prizes themselves are always awarded.
  SettingDef('cauris_prize_notify', 'cauris', SettingType.flag01),
  SettingDef('league_small_max', 'cauris', SettingType.count),
  SettingDef('league_medium_max', 'cauris', SettingType.count),
  SettingDef('path_league_min', 'cauris', SettingType.count),
  SettingDef('progress_credit_orders', 'cauris', SettingType.count),
  SettingDef('path_gates_open', 'cauris', SettingType.flag01),
  // Shown, and changed where it always was: Compte › Sécurité (078).
  SettingDef('admin_two_step', 'security', SettingType.flag),
  // 109: a number proved on WhatsApp before an order — off until the
  // WhatsApp code Worker and Supabase's hook are set up.
  SettingDef('order_phone_verified', 'orders', SettingType.flag),
  // 134: until how many hours before its slot a customer may cancel a
  // booking (0 to 168).
  SettingDef('booking_cancel_hours', 'orders', SettingType.count),
  // 111: a number proved on WhatsApp before a business is created — off,
  // as 109's, until the same Worker and hook are set up.
  SettingDef('create_phone_verified', 'creation', SettingType.flag),
  // 113: the help number of « Aide Mara »'s WhatsApp button; empty, the
  // button is not drawn. 126: the help e-mail and the hours it answers —
  // the app's « Aide » and the site's /aide read the three.
  SettingDef('support_whatsapp', 'help', SettingType.text),
  SettingDef('support_email', 'help', SettingType.text),
  SettingDef('support_hours', 'help', SettingType.text),
  // 122: the web's « télécharger l'application » pop-up — Google Play once
  // the listing is live (the APK until then), the App Store once set.
  SettingDef('play_store_live', 'apps', SettingType.flag),
  SettingDef('app_store_url', 'apps', SettingType.text),
  // 124: the welcome e-mail a new account receives once (workers/mail).
  SettingDef('welcome_email_on', 'accounts', SettingType.flag),
  // 129: every platform admin hears of each new account.
  SettingDef('admin_new_user_notify', 'accounts', SettingType.flag),
  // 133 (batch 136): « Besoin d'aide » — the Pro help hours on
  // Ouagadougou's clock, when a request goes to every trainer, when it is
  // late, how many a day, the WhatsApp template (empty: the bell alone),
  // and the platform admins told of a request nobody took.
  SettingDef('help_hours_open', 'helppro', SettingType.count),
  SettingDef('help_hours_close', 'helppro', SettingType.count),
  SettingDef('help_escalate_minutes', 'helppro', SettingType.count),
  SettingDef('help_late_minutes', 'helppro', SettingType.count),
  SettingDef('help_daily_limit', 'helppro', SettingType.count),
  SettingDef('help_whatsapp_template', 'helppro', SettingType.text),
  SettingDef('admin_help_notify', 'helppro', SettingType.flag),
  // 135 (batch 139): « Continuer avec Apple » on the website — off until
  // the Services ID is made and Supabase's Apple « Client IDs » list it.
  SettingDef('apple_web_signin', 'signin', SettingType.flag),
  // 136 (batch 141): the photos an item shows and holds on Mara Pro (1 to
  // 20); Basic keeps one, its cover.
  SettingDef('max_item_photos_pro', 'pro', SettingType.count),
];

/// One of Réglages' eight cards (135): its address, its icon, and the
/// sub-headings of its short page, each with its settings in order.
class SettingCard {
  const SettingCard(this.key, this.icon, this.parts, {this.links = const []});

  /// Also its address: `/console/reglages/<key>`.
  final String key;
  final IconData icon;

  /// (sub-heading, keys), in the page's order.
  final List<(String, List<String>)> parts;

  /// The pages the card opens (Création's types and creation flow,
  /// Sécurité's journal): (label, route).
  final List<(String, String)> links;

  String get route => '${Routes.consoleSettings}/$key';
}

/// Réglages folded (135): « Quelles sont les règles ? » in eight cards,
/// every setting on exactly one (test/batch135_test.dart proves none is
/// lost). The sub-headings' names are [settingPartLabel]'s.
const settingCards = <SettingCard>[
  SettingCard('pro', Icons.workspace_premium_outlined, [
    ('prices', [
      'pro_price_month', 'pro_price_year', 'pro_price_month_eur', 'pro_price_year_eur',
      'pro_price_month_usd', 'pro_price_year_usd', 'pro_currency',
    ]),
    ('tools', ['pro_features']),
    ('with_pro', ['max_item_photos_pro']),
    ('free', [
      'free_max_staff', 'free_max_invoices_month', 'free_max_photos', 'free_photo_items',
      'free_history_months', 'vitrine_free_basics',
    ]),
  ]),
  SettingCard('vitrines', Icons.storefront_outlined, [
    ('street', ['vitrine_min_items', 'vitrine_min_items_association', 'progress_street_pct']),
    ('spots', [
      'spots_max_live', 'spot_price_article_7', 'spot_price_shop_7', 'spot_price_article_7_eur',
      'spot_price_shop_7_eur', 'spot_price_article_7_usd', 'spot_price_shop_7_usd',
    ]),
    ('orders', ['order_phone_verified', 'booking_cancel_hours']),
  ]),
  SettingCard('livraison', Icons.delivery_dining_outlined, [
    ('prices', ['delivery_base', 'delivery_per_km', 'delivery_currency', 'delivery_share_pct']),
    ('distance', ['delivery_max_km', 'delivery_included_km', 'courier_radius_km']),
    ('couriers', ['courier_licence_required', 'courier_phone_verified']),
    ('times', ['own_courier_minutes', 'stuck_ready_minutes']),
  ]),
  SettingCard('paiements', Icons.payments_outlined, [
    ('wave', ['wave_checkout', 'wave_card', 'wave_commission_pct', 'platform_wave', 'platform_wave_name']),
    ('card', ['stripe_on']),
    ('stores', ['store_billing_on', 'store_review_account', 'store_review_orgs']),
  ]),
  SettingCard('cauris', Icons.toll_outlined, [
    ('earn', [
      'cauris_order_min', 'cauris_orders_per_customer', 'cauris_quick_minutes',
      'cauris_expire_days', 'cauris_unlock_days',
    ]),
    ('prizes', ['cauris_prize_1', 'cauris_prize_2', 'cauris_prize_3', 'cauris_prize_notify']),
    ('leagues', ['league_small_max', 'league_medium_max', 'path_league_min']),
    ('path', ['progress_credit_orders', 'path_gates_open']),
  ]),
  SettingCard('creation', Icons.add_business_outlined, [
    ('check', ['create_phone_verified']),
  ], links: [
    ('Types d\'activité', Routes.consoleKinds),
    ('Parcours de création', Routes.consoleRequestForm),
  ]),
  SettingCard('notifications', Icons.notifications_outlined, [
    ('accounts', ['welcome_email_on', 'admin_new_user_notify']),
    ('help', ['support_whatsapp', 'support_email', 'support_hours']),
    ('pro_help', [
      'help_hours_open', 'help_hours_close', 'help_escalate_minutes', 'help_late_minutes',
      'help_daily_limit', 'help_whatsapp_template', 'admin_help_notify',
    ]),
    ('apps', ['play_store_live', 'app_store_url']),
  ]),
  SettingCard('securite', Icons.shield_outlined, [
    ('security', ['admin_two_step']),
    ('signin', ['apple_web_signin']),
  ], links: [
    ('Actions de Mara', Routes.consoleJournal),
    ('Activité', Routes.consoleAudit),
    // 142 (batch 147): the documents everyone accepts, and a new version.
    ('Conditions d\'utilisation', Routes.consoleTerms),
  ]),
];

/// The card a setting is on (135), or null for none (a test fails then).
SettingCard? settingCardOf(String key) {
  for (final c in settingCards) {
    for (final p in c.parts) {
      if (p.$2.contains(key)) return c;
    }
  }
  return null;
}

SettingCard? settingCardByKey(String? key) {
  for (final c in settingCards) {
    if (c.key == key) return c;
  }
  return null;
}

String settingCardTitle(BuildContext context, String card) => switch (card) {
      'pro' => context.tr('Pro et prix'),
      'vitrines' => context.tr('Vitrines'),
      'livraison' => context.tr('Livraison'),
      'paiements' => context.tr('Paiements'),
      'cauris' => context.tr('Cauris, Chemin'),
      'creation' => context.tr('Création'),
      'notifications' => context.tr('Notifications'),
      'securite' => context.tr('Sécurité, journal'),
      _ => card,
    };

String settingCardHint(BuildContext context, String card) => switch (card) {
      'pro' => context.tr('Prix, outils, limites sans Pro'),
      'vitrines' => context.tr('Rue, mises en avant'),
      'livraison' => context.tr('Prix au km, distance, livreurs'),
      'paiements' => context.tr('Wave, carte, boutiques d\'applis'),
      'cauris' => context.tr('Gains, ligues, prix'),
      'creation' => context.tr('Types d\'activité, parcours'),
      'notifications' => context.tr('Comptes, aide, applications'),
      'securite' => context.tr('Deux étapes, connexion, actions, activité'),
      _ => '',
    };

/// A card page's small uppercase sub-headings (135), in plain words.
String settingPartLabel(BuildContext context, String part) => switch (part) {
      'prices' => context.tr('Prix'),
      'tools' => context.tr('Outils réservés à Pro'),
      'free' => context.tr('Sans Pro'),
      'with_pro' => context.tr('Avec Pro'),
      'street' => context.tr('Pour paraître dans la rue'),
      'spots' => context.tr('Mises en avant'),
      'orders' => context.tr('Commandes'),
      'distance' => context.tr('Distance'),
      'couriers' => context.tr('Livreurs'),
      'times' => context.tr('Délais'),
      'wave' => context.tr('Wave'),
      'card' => context.tr('Carte bancaire'),
      'stores' => context.tr('Boutiques d\'applications'),
      'earn' => context.tr('Gagner des cauris'),
      'prizes' => context.tr('Prix de la semaine'),
      'leagues' => context.tr('Ligues'),
      'path' => context.tr('Le Chemin'),
      'check' => context.tr('Vérification'),
      'accounts' => context.tr('Nouveaux comptes'),
      'help' => context.tr('Aide aux clients'),
      'pro_help' => context.tr('Aide Pro : l\'équipe de formation'),
      'apps' => context.tr('Applications mobiles'),
      'security' => context.tr('Sécurité'),
      'signin' => context.tr('Connexion'),
      _ => part,
    };

/// A card's link, said in the screen's language.
String settingLinkLabel(BuildContext context, String fr) => switch (fr) {
      'Types d\'activité' => context.tr('Types d\'activité'),
      'Parcours de création' => context.tr('Parcours de création'),
      'Actions de Mara' => context.tr('Actions de Mara'),
      'Activité' => context.tr('Activité'),
      'Conditions d\'utilisation' => context.tr('Conditions d\'utilisation'),
      _ => fr,
    };

/// Lower case, no accents: « Délais » is found by « delai ».
String _fold(String s) {
  const plain = {
    'a': 'àâäá', 'c': 'ç', 'e': 'éèêë', 'i': 'îïí', 'o': 'ôöó', 'u': 'ûùüú', 'oe': 'œ',
  };
  var out = s.toLowerCase();
  for (final e in plain.entries) {
    for (final r in e.value.runes) {
      out = out.replaceAll(String.fromCharCode(r), e.key);
    }
  }
  return out;
}

final Map<String, String> _frOfEn = {for (final e in enStrings.entries) e.value: e.key};

/// Whether [query] finds [key] (135): its name in French and in English,
/// whichever the screen reads, or the key itself.
bool settingMatches(BuildContext context, String key, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return true;
  final shown = settingLabel(context, key);
  final fr = context.trLanguage == 'en' ? (_frOfEn[shown] ?? shown) : shown;
  final en = enStrings[fr] ?? fr;
  return [fr, en, key].any((s) => _fold(s).contains(q));
}

String settingGroupLabel(BuildContext context, String group) => switch (group) {
      'pro' => context.tr('Mara Pro'),
      'free' => context.tr('Sans Pro'),
      'street' => context.tr('Vitrines et rue'),
      'delivery' => context.tr('Livraison'),
      'wave' => context.tr('Paiements Wave'),
      'cauris' => context.tr('Cauris, ligues et Chemin'),
      'security' => context.tr('Sécurité de la plateforme'),
      'orders' => context.tr('Commandes de la rue'),
      'creation' => context.tr('Création d\'activité'),
      'help' => context.tr('Aide aux clients'),
      'apps' => context.tr('Applications mobiles'),
      'accounts' => context.tr('Nouveaux comptes'),
      'helppro' => context.tr('Aide Pro'),
      'signin' => context.tr('Connexion'),
      _ => group,
    };

String settingLabel(BuildContext context, String key) => switch (key) {
      'pro_price_month' => context.tr('Prix de Mara Pro, par mois — FCFA (zone franc CFA)'),
      'pro_price_year' => context.tr('Prix de Mara Pro, par an — FCFA (zone franc CFA)'),
      'pro_price_month_eur' => context.tr('Prix de Mara Pro, par mois — euros (zone euro)'),
      'pro_price_year_eur' => context.tr('Prix de Mara Pro, par an — euros (zone euro)'),
      'pro_price_month_usd' => context.tr('Prix de Mara Pro, par mois — dollars (reste du monde)'),
      'pro_price_year_usd' => context.tr('Prix de Mara Pro, par an — dollars (reste du monde)'),
      'pro_currency' => context.tr('Monnaie des prix de Mara Pro'),
      'platform_wave' => context.tr('Numéro Wave qui reçoit les paiements Pro'),
      'platform_wave_name' => context.tr('Nom du compte Wave de Mara'),
      'stripe_on' => context.tr('Abonnement par carte (Stripe)'),
      'store_billing_on' =>
        context.tr('Abonnement dans les applications (App Store, Google Play)'),
      'store_review_account' =>
        context.tr('Compte de test des boutiques (achats sandbox acceptés)'),
      'store_review_orgs' => context.tr(
          'Entreprises de ce compte de test (identifiants ; vide : toutes)'),
      'pro_features' => context.tr('Outils réservés à Mara Pro'),
      'max_item_photos_pro' => context.tr('Photos par article avec Pro (1 à 20)'),
      'free_max_staff' => context.tr('Personnes dans l\'équipe'),
      'free_max_invoices_month' => context.tr('Factures par mois'),
      'free_max_photos' => context.tr('Photos en tout'),
      'free_photo_items' => context.tr('Articles avec photo'),
      'free_history_months' => context.tr('Mois d\'historique'),
      'vitrine_free_basics' => context.tr('Habillage de base de la vitrine pour tous'),
      'vitrine_min_items' => context.tr('Articles pour paraître dans la rue (boutique, ferme)'),
      'vitrine_min_items_association' =>
        context.tr('Articles ou services pour paraître dans la rue (association)'),
      'progress_street_pct' => context.tr('Vitrine remplie à … % pour paraître dans la rue'),
      'spots_max_live' => context.tr('Mises en avant en même temps'),
      'spot_price_article_7' => context.tr('Un article à la une, 7 jours — FCFA (zone franc CFA)'),
      'spot_price_shop_7' => context.tr('La boutique à la une, 7 jours — FCFA (zone franc CFA)'),
      'spot_price_article_7_eur' => context.tr('Un article à la une, 7 jours — euros (zone euro)'),
      'spot_price_shop_7_eur' => context.tr('La boutique à la une, 7 jours — euros (zone euro)'),
      'spot_price_article_7_usd' => context.tr('Un article à la une, 7 jours — dollars (reste du monde)'),
      'spot_price_shop_7_usd' => context.tr('La boutique à la une, 7 jours — dollars (reste du monde)'),
      'delivery_base' => context.tr('Livraison : prise en charge'),
      'delivery_per_km' => context.tr('Livraison : par kilomètre'),
      'delivery_currency' => context.tr('Monnaie des prix de livraison'),
      'delivery_max_km' => context.tr('Distance de livraison la plus longue (km)'),
      'delivery_included_km' => context.tr('Kilomètres offerts avec Pro'),
      'delivery_share_pct' => context.tr('Part de Mara sur chaque livraison (%)'),
      'own_courier_minutes' => context.tr('Minutes réservées aux livreurs de la boutique'),
      'stuck_ready_minutes' => context.tr('Minutes avant de signaler une commande prête'),
      'courier_licence_required' => context.tr('Permis de conduire obligatoire pour livrer à moto ou en voiture'),
      'courier_phone_verified' => context.tr('Numéro WhatsApp vérifié pour devenir livreur'),
      'courier_radius_km' => context.tr('Distance où les livreurs reçoivent une livraison (km, 1 à 100)'),
      'wave_checkout' => context.tr('Payer en ligne par Wave'),
      'wave_card' => context.tr('Carte bancaire sur la page Wave'),
      'wave_commission_pct' => context.tr('Commission de Mara sur une commande payée en ligne (%)'),
      'cauris_order_min' => context.tr('Commande la plus petite qui rapporte des cauris'),
      'cauris_orders_per_customer' => context.tr('Commandes par client et par jour qui comptent'),
      'cauris_quick_minutes' => context.tr('Minutes pour une commande acceptée vite'),
      'cauris_expire_days' => context.tr('Jours sans mouvement avant que les cauris expirent'),
      'cauris_unlock_days' => context.tr('Jours d\'ouverture d\'un outil acheté en cauris'),
      'cauris_prize_1' => context.tr('Cauris pour la 1re place de la semaine'),
      'cauris_prize_2' => context.tr('Cauris pour la 2e place'),
      'cauris_prize_3' => context.tr('Cauris pour la 3e place'),
      'cauris_prize_notify' => context.tr('Prévenir les gagnants de la semaine (notification)'),
      'league_small_max' => context.tr('Petite ligue : moins de … commandes en 30 jours'),
      'league_medium_max' => context.tr('Ligue moyenne : moins de … commandes en 30 jours'),
      'path_league_min' => context.tr('Entreprises dans une ligue avant le classement'),
      'progress_credit_orders' => context.tr('Commandes terminées pour ouvrir le carnet de crédit'),
      'path_gates_open' => context.tr('Ouvrir tous les outils du Chemin à tout le monde'),
      'admin_two_step' => context.tr('Validation en deux étapes du compte de la plateforme'),
      'order_phone_verified' => context.tr('Numéro WhatsApp vérifié avant de commander'),
      'booking_cancel_hours' =>
        context.tr('Annulation d\'un rendez-vous par le client : jusqu\'à … heures avant'),
      'create_phone_verified' => context.tr('Numéro WhatsApp vérifié avant de créer une activité'),
      'support_whatsapp' => context.tr('Numéro WhatsApp de l\'aide Mara (vide : caché)'),
      'support_email' => context.tr('E-mail de l\'aide Mara'),
      'support_hours' => context.tr('Heures de l\'aide Mara (par exemple 24 h/24, 7 j/7)'),
      'play_store_live' => context.tr('Mara est publiée sur Google Play (sinon : le fichier APK)'),
      'app_store_url' => context.tr('Adresse de Mara sur l\'App Store (vide : écran d\'accueil)'),
      'welcome_email_on' => context.tr('E-mail de bienvenue aux nouveaux comptes'),
      'admin_new_user_notify' =>
        context.tr('Notifier les administrateurs de Mara à chaque nouveau compte'),
      'help_hours_open' => context.tr('Aide Pro : heure d\'ouverture (0 à 23, heure de Ouagadougou)'),
      'help_hours_close' => context.tr('Aide Pro : heure de fermeture (1 à 24, heure de Ouagadougou)'),
      'help_escalate_minutes' =>
        context.tr('Minutes sans réponse avant d\'envoyer une demande à tous les formateurs'),
      'help_late_minutes' => context.tr('Minutes sans réponse avant « en retard » dans Aujourd\'hui'),
      'help_daily_limit' => context.tr('Demandes d\'aide par entreprise et par 24 heures'),
      'help_whatsapp_template' =>
        context.tr('Modèle WhatsApp des formateurs chez Meta (vide : pas de WhatsApp)'),
      'admin_help_notify' =>
        context.tr('Notifier les administrateurs de Mara d\'une demande d\'aide sans réponse'),
      'apple_web_signin' => context.tr('Connexion Apple sur le site'),
      _ => key,
    };

/// The only numbers that take a decimal: every reader of these takes it
/// as numeric (the delivery fee and reach, the Wave commission). Every
/// other number is read as an integer by the server, which refuses
/// « 12.5 » there (105's platform_set_setting) — said here first.
const decimalSettings = {
  'delivery_base',
  'delivery_per_km',
  'delivery_max_km',
  'delivery_included_km',
  'wave_commission_pct',
  // 139: a euro or dollar price, to the cent (two decimals at most, which
  // the server checks too).
  ...zonePriceSettings,
};

/// The euro and dollar prices (139): typed to the cent.
const zonePriceSettings = {
  'spot_price_article_7_eur',
  'spot_price_shop_7_eur',
  'spot_price_article_7_usd',
  'spot_price_shop_7_usd',
  'pro_price_month_eur',
  'pro_price_year_eur',
  'pro_price_month_usd',
  'pro_price_year_usd',
};

/// A line under a card's sub-heading (139): the spots' and Mara Pro's
/// prices are the website's; the stores charge their own.
String? settingPartNote(BuildContext context, String card, String part) =>
    (card == 'vitrines' && part == 'spots') || (card == 'pro' && part == 'prices')
        ? context.tr('Sur Android et iPhone, le prix payé est celui de Google Play et de l\'App Store — mettez les mêmes prix dans Play Console et App Store Connect.')
        : null;

/// The largest number any setting takes (105's platform_set_setting).
const settingMax = 1000000000;

/// The numbers that are never zero: the card's rate divided every Pro
/// price (121's platform_set_setting refuses 0) — said here first. Out of
/// Réglages since 139, kept should it come back.
const positiveSettings = {'stripe_xof_per_usd'};

/// Mara's prices the card charges (139): never below what Stripe takes —
/// 300 FCFA, 0,50 € or $0.50 (the server refuses the rest too).
const cardMinimumSettings = <String, double>{
  'spot_price_article_7': 300,
  'spot_price_shop_7': 300,
  'pro_price_month': 300,
  'pro_price_year': 300,
  'spot_price_article_7_eur': 0.5,
  'spot_price_shop_7_eur': 0.5,
  'spot_price_article_7_usd': 0.5,
  'spot_price_shop_7_usd': 0.5,
  'pro_price_month_eur': 0.5,
  'pro_price_year_eur': 0.5,
  'pro_price_month_usd': 0.5,
  'pro_price_year_usd': 0.5,
};

/// The numbers with a range of their own: the couriers' radius is 1 to
/// 100 km (122's platform_set_setting refuses the rest) — said here first.
const rangedSettings = {
  'courier_radius_km': (1, 100),
  // 133: the help hours, its minutes and its daily limit (133's trigger
  // refuses the rest, and an opening after the closing).
  'help_hours_open': (0, 23),
  'help_hours_close': (1, 24),
  'help_escalate_minutes': (1, 1440),
  'help_late_minutes': (1, 1440),
  'help_daily_limit': (1, 50),
  // 134: a booking's cancel, 0 to 168 hours before (a trigger refuses the rest).
  'booking_cancel_hours': (0, 168),
  // 136: the photos an item holds on Pro (a trigger refuses the rest).
  'max_item_photos_pro': (1, 20),
};

/// A help number as typed or pasted, letters and digits only (126): the
/// spaces, « + », brackets, dashes of every kind and the invisible
/// direction marks a copied number carries (U+202A…U+202C) go.
String supportNumberDigits(String raw) =>
    raw.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// « ; », « , » or « / » between digits reads as two numbers (« 226 70 00
/// 00 00 / 226 76 00 00 00 »): refused, as 126's trigger refuses it, rather
/// than run together into one wrong number.
bool supportNumberHasTwo(String raw) => RegExp(r'[;,/]').hasMatch(raw);

/// The value as a person reads it.
String settingValueText(BuildContext context, SettingDef def, Object? v) {
  num? n = v is num ? v : num.tryParse('${v ?? ''}');
  final f = NumberFormat.decimalPattern('fr_FR');
  return switch (def.type) {
    SettingType.flag => v == true ? context.tr('Oui') : context.tr('Non'),
    SettingType.flag01 => (n ?? 0) > 0 ? context.tr('Oui') : context.tr('Non'),
    SettingType.pct => n == null ? '—' : '${f.format(n)} %',
    SettingType.km => n == null ? '—' : '${f.format(n)} km',
    // A euro or dollar price shows its cents (139): « 4,99 », « 5,00 ».
    SettingType.money when zonePriceSettings.contains(def.key) =>
      n == null ? '—' : NumberFormat.decimalPatternDigits(locale: 'fr_FR', decimalDigits: 2).format(n),
    SettingType.money || SettingType.count => n == null ? '—' : f.format(n),
    SettingType.list => v is List
        ? (v.isEmpty ? '—' : v.map((e) => featureName(context, '$e')).join(', '))
        : '—',
    SettingType.text || SettingType.currency =>
      (v == null || '$v'.trim().isEmpty) ? context.tr('(vide)') : '$v',
  };
}

/// Réglages (105): every setting, by group, with who changed it last.
/// A change is journaled with its « Annuler ». The two-step switch is
/// shown here and changed in Sécurité, where its explanation is.
///
/// Folded (135): with no [card], eight cards and « Chercher un réglage… »,
/// which finds any setting by its name in French or English; with a
/// [card], that card's short page under its small uppercase sub-headings.
class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key, required this.center, this.card});

  final CommandCenterRepository center;

  /// One of [settingCards]' keys; null: the cards.
  final String? card;

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  Map<String, SettingValue>? _values;
  String? _error;
  String? _busy;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await widget.center.settings();
      if (!mounted) return;
      setState(() {
        _values = v;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  /// Writes [value]; null when it went through, else the server's refusal
  /// — said in a snackbar, or handed back to the dialog that asked
  /// ([sayRefusal] false), which keeps it under the field with what was
  /// typed (or, gone by then, says it in a snackbar itself).
  Future<String?> _save(SettingDef def, Object value, {bool sayRefusal = true}) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('{name} : enregistré.', {'name': settingLabel(context, def.key)});
    final undoLabel = context.tr('Annuler');
    setState(() => _busy = def.key);
    try {
      final id = await widget.center.setSetting(def.key, value);
      await _load();
      messenger.showSnackBar(SnackBar(
        content: Text(saved),
        action: id == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () async {
                  try {
                    await widget.center.undo(id);
                    await _load();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
                  }
                },
              ),
      ));
      return null;
    } catch (e) {
      final refusal = describeError(e);
      if (sayRefusal) messenger.showSnackBar(SnackBar(content: Text(refusal)));
      return refusal;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// The dialog stays open until the server has answered: a refusal is
  /// shown under the field, and nothing typed is lost (126 — the owner's
  /// help number was refused after the dialog had closed, and only a
  /// passing snackbar said why).
  Future<void> _edit(SettingDef def, Object? current) async {
    await showDialog<void>(
      context: context,
      // Closed by « Annuler » only — and not while the server is asked
      // (the dialog's PopScope): a write is never left without its answer.
      barrierDismissible: false,
      builder: (_) => _EditDialog(
        def: def,
        current: current,
        save: (value) => _save(def, value, sayRefusal: false),
      ),
    );
  }

  SettingDef? _def(String key) {
    for (final d in platformSettingDefs) {
      if (d.key == key) return d;
    }
    return null;
  }

  void _open(String route) {
    final router = GoRouter.maybeOf(context);
    if (router != null) router.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = _values;
    final card = settingCardByKey(widget.card);
    final title = card == null ? context.tr('Réglages') : settingCardTitle(context, card.key);
    final Widget body;
    if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ),
      );
    } else if (values == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (card != null) {
      body = _cardPage(context, card, values);
    } else {
      body = _hub(context, values);
    }
    return Scaffold(
      appBar: AppBar(
        // A card's page: back to the eight cards (its address is go'd).
        leading: card == null || GoRouter.maybeOf(context) == null
            ? null
            : BackButton(
                key: const Key('settings-back'),
                onPressed: () => _open(Routes.consoleSettings),
              ),
        title: Text(title),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          bellRoom,
        ],
      ),
      body: body,
    );
  }

  /// Small uppercase words over a group, as the center's other lists.
  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 0.9, color: maraBrown, fontWeight: FontWeight.w800)),
      );

  Widget _rows(BuildContext context, Iterable<String> keys, Map<String, SettingValue> values) =>
      KajCard(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final k in keys)
              if (_def(k) case final d? when values.containsKey(k)) _row(context, d, values[k]!),
          ],
        ),
      );

  /// « Quelles sont les règles ? »: the search, then the eight cards — or,
  /// a word typed, every setting whose name has it, under its card's name.
  Widget _hub(BuildContext context, Map<String, SettingValue> values) {
    final theme = Theme.of(context);
    final q = _query.text.trim();
    final found = <SettingCard, List<String>>{};
    if (q.isNotEmpty) {
      for (final c in settingCards) {
        final keys = [
          for (final p in c.parts)
            for (final k in p.$2)
              if (values.containsKey(k) && settingMatches(context, k, q)) k,
        ];
        if (keys.isNotEmpty) found[c] = keys;
      }
    }
    return ListView(
      key: const Key('settings-hub'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        TextField(
          key: const Key('settings-search'),
          controller: _query,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: context.tr('Chercher un réglage…'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr('Effacer'),
                    onPressed: () => setState(_query.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (q.isEmpty) ...[
          LayoutBuilder(builder: (context, box) {
            final per = box.maxWidth >= 900 ? 4 : box.maxWidth >= 560 ? 3 : 2;
            final w = (box.maxWidth - (per - 1) * 10) / per;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in settingCards)
                  SizedBox(width: w, child: _cardTile(context, c)),
              ],
            );
          }),
          const SizedBox(height: 16),
          Text(
            context.tr('Chaque changement est écrit dans le Journal, où « Annuler » le reprend.'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ] else if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(context.tr('Aucun réglage ne porte ce nom.'),
                key: const Key('settings-none')),
          )
        else
          for (final e in found.entries) ...[
            _label(context, settingCardTitle(context, e.key.key)),
            _rows(context, e.value, values),
          ],
      ],
    );
  }

  Widget _cardTile(BuildContext context, SettingCard c) {
    final theme = Theme.of(context);
    return Material(
      key: Key('settings-card-${c.key}'),
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(c.route),
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(c.icon, color: maraBrown, size: 22),
              const SizedBox(height: 8),
              Text(settingCardTitle(context, c.key),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(settingCardHint(context, c.key),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardPage(BuildContext context, SettingCard card, Map<String, SettingValue> values) {
    return ListView(
      key: Key('settings-page-${card.key}'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        if (card.links.isNotEmpty) ...[
          _label(context, context.tr('Pages')),
          KajCard(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (label, route) in card.links)
                  ListTile(
                    key: Key('settings-link-$route'),
                    minVerticalPadding: 12,
                    title: Text(settingLinkLabel(context, label),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(route),
                  ),
              ],
            ),
          ),
        ],
        // The bell with the app closed, checked end to end (115).
        if (card.key == 'notifications')
          if (AppScope.maybeOf(context)?.notify case final notify?) ...[
            _label(context, context.tr('Sur cet appareil')),
            PushCheck(notify: notify),
          ],
        for (final (part, keys) in card.parts)
          if (keys.any(values.containsKey)) ...[
            _label(context, settingPartLabel(context, part)),
            _rows(context, keys, values),
            if (settingPartNote(context, card.key, part) case final note?)
              Padding(
                key: Key('settings-note-${card.key}-$part'),
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: maraBrown),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(note,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
          ],
      ],
    );
  }

  Widget _row(BuildContext context, SettingDef d, SettingValue v) {
    final theme = Theme.of(context);
    final busy = _busy == d.key;
    final who = v.changedBy == null || v.updatedAt == null
        ? null
        : context.tr('Changé par {who} le {date}', {
            'who': v.changedBy,
            'date': DateFormat('dd/MM/yyyy').format(v.updatedAt!),
          });
    if (d.key == 'admin_two_step') {
      return ListTile(
        key: const Key('setting-admin_two_step'),
        minVerticalPadding: 12,
        leading: const Icon(Icons.verified_user_outlined),
        title: Text(settingLabel(context, d.key)),
        subtitle: Text(v.value == true
            ? context.tr('Activée — changée dans Compte › Sécurité.')
            : context.tr('Désactivée — changée dans Compte › Sécurité.')),
        trailing: TextButton(
          onPressed: () async {
            await context.push(Routes.security);
            if (mounted) await _load();
          },
          child: Text(context.tr('Ouvrir')),
        ),
      );
    }
    if (d.type == SettingType.flag || d.type == SettingType.flag01) {
      final on = d.type == SettingType.flag
          ? v.value == true
          : ((v.value is num ? v.value as num : 0) > 0);
      // What must be set up before the switch is turned (109): a code that
      // cannot leave would stop every order.
      final before = d.key == 'order_phone_verified' || d.key == 'courier_phone_verified' ||
              d.key == 'create_phone_verified'
          ? context.tr('À n\'activer qu\'une fois le Worker whatsapp-otp déployé, le modèle WhatsApp « authentication » approuvé et le hook « Send SMS » de Supabase branché (BUILD_PLAN.md, « Numéros vérifiés par WhatsApp »).')
          : null;
      return SwitchListTile(
        key: Key('setting-${d.key}'),
        title: Text(settingLabel(context, d.key)),
        subtitle: before == null && who == null
            ? null
            : Text([?before, ?who].join('\n')),
        value: on,
        onChanged: busy
            ? null
            : (next) => _save(d, d.type == SettingType.flag ? next : (next ? 1 : 0)),
      );
    }
    return ListTile(
      key: Key('setting-${d.key}'),
      minVerticalPadding: 10,
      title: Text(settingLabel(context, d.key)),
      subtitle: who == null ? null : Text(who),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              settingValueText(context, d, v.value),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: 4),
          if (busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.edit_outlined, size: 20, color: maraBrown),
        ],
      ),
      onTap: busy ? null : () => _edit(d, v.value),
    );
  }
}

/// One setting, typed in its own way.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.def, required this.current, required this.save});

  final SettingDef def;
  final Object? current;

  /// Writes the value: null once it went through, else why not.
  final Future<String?> Function(Object value) save;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _text = TextEditingController(
      text: widget.current is List ? '' : '${widget.current ?? ''}');
  late final Set<String> _picked = {
    if (widget.current is List) for (final e in widget.current as List) '$e',
  };
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _ok() async {
    if (_saving) return;
    final def = widget.def;
    final raw = _text.text.trim();
    Object? value;
    String? problem;
    final decimals = decimalSettings.contains(def.key);
    switch (def.type) {
      case SettingType.money:
      case SettingType.count:
      case SettingType.km:
        final n = parseAmount(raw);
        if (positiveSettings.contains(def.key) &&
            (n == null || n <= 0 || n != n.roundToDouble())) {
          problem = context.tr('Un nombre entier plus grand que zéro.');
        } else if (n == null || n < 0 || (!decimals && n != n.roundToDouble())) {
          problem = decimals
              ? context.tr('Un nombre, zéro ou plus.')
              : context.tr('Un nombre entier, zéro ou plus.');
        } else if (cardMinimumSettings[def.key] case final min? when n < min) {
          problem = min >= 1
              ? context.tr('Au moins 300 FCFA : le paiement par carte (Stripe) ne prend pas moins.')
              : context.tr('Au moins 0,50 : le paiement par carte (Stripe) ne prend pas moins.');
        } else if (rangedSettings[def.key] case (final lo, final hi)
            when n < lo || n > hi) {
          problem = context.tr('Un nombre de {lo} à {hi}.', {'lo': '$lo', 'hi': '$hi'});
        } else if (n > settingMax) {
          problem = context.tr('Un nombre d\'un milliard au plus.');
        } else {
          value = n == n.roundToDouble() ? n.round() : n;
        }
      case SettingType.pct:
        final n = parseAmount(raw);
        if (n == null || n < 0 || n > 100 || (!decimals && n != n.roundToDouble())) {
          problem = decimals
              ? context.tr('Un pourcentage de 0 à 100.')
              : context.tr('Un pourcentage entier, de 0 à 100.');
        } else {
          value = n == n.roundToDouble() ? n.round() : n;
        }
      case SettingType.currency:
        if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(raw)) {
          problem = context.tr('Trois lettres, comme XOF.');
        } else {
          value = raw.toUpperCase();
        }
      case SettingType.text:
        // Counted as Postgres's char_length counts: one per character,
        // an emoji or an accented letter typed as two code units alike.
        if (raw.runes.length > 200) {
          problem = context.tr('200 caractères au plus.');
        } else if (def.key == 'app_store_url' && raw.isNotEmpty &&
            !RegExp(r'^https://\S+$').hasMatch(raw)) {
          problem = context.tr('Une adresse qui commence par https://, ou rien.');
        } else if (def.key == 'support_whatsapp') {
          // Digits only (126): a number pasted from WhatsApp or a phone's
          // contacts carries invisible direction marks and non-breaking
          // hyphens; spaces, « + » and brackets go too. Letters stay, so
          // a word is still refused.
          final digits = supportNumberDigits(raw);
          if (supportNumberHasTwo(raw) ||
              (digits.isNotEmpty && !RegExp(r'^[0-9]{8,15}$').hasMatch(digits))) {
            problem = context.tr('Le numéro WhatsApp de l\'aide : l\'indicatif du pays puis le numéro, en chiffres (par exemple 22670000000).');
          } else {
            value = digits;
          }
        } else if (def.key == 'support_email' && !Support.isEmail(raw)) {
          problem = context.tr('L\'e-mail de l\'aide : une adresse comme hello@kaj-consulting.com.');
        } else if (def.key == 'support_hours' && (raw.isEmpty || raw.runes.length > 60)) {
          problem = context.tr('Les heures de l\'aide : quelques mots, 60 caractères au plus (par exemple 24 h/24, 7 j/7).');
        } else {
          value = raw;
        }
      case SettingType.list:
        value = [for (final o in def.options) if (_picked.contains(o)) o];
      case SettingType.flag:
      case SettingType.flag01:
        value = null;
    }
    if (problem != null || value == null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // Taken now: should the dialog be gone when the answer comes, a
    // refusal is still said.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final refusal = await widget.save(value);
    if (!mounted) {
      if (refusal != null) messenger?.showSnackBar(SnackBar(content: Text(refusal)));
      return;
    }
    if (refusal != null) {
      setState(() {
        _saving = false;
        _error = refusal;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final numeric = def.type == SettingType.money ||
        def.type == SettingType.count ||
        def.type == SettingType.km ||
        def.type == SettingType.pct;
    // While the server is asked: no back gesture, no « Annuler » — the
    // answer comes back here, under the field.
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        // The keyboard up on a small phone: the dialog scrolls (A6).
        scrollable: true,
        title: Text(settingLabel(context, def.key)),
        content: SizedBox(
          width: 420,
          child: def.type == SettingType.list
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in def.options)
                      FilterChip(
                        label: Text(featureName(context, o)),
                        selected: _picked.contains(o),
                        onSelected: (on) => setState(() => on ? _picked.add(o) : _picked.remove(o)),
                      ),
                  ],
                )
              : TextField(
                  key: const Key('setting-field'),
                  controller: _text,
                  autofocus: true,
                  keyboardType: numeric
                      ? TextInputType.numberWithOptions(
                          decimal: decimalSettings.contains(def.key))
                      : TextInputType.text,
                  enabled: !_saving,
                  onSubmitted: (_) => _ok(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    // A refusal is a sentence: said whole, never cut (126).
                    errorMaxLines: 4,
                    suffixText: def.type == SettingType.pct
                        ? '%'
                        : def.type == SettingType.km
                            ? 'km'
                            : null,
                  ),
                ),
        ),
        actions: [
          TextButton(
            key: const Key('setting-cancel'),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            key: const Key('setting-save'),
            onPressed: _saving ? null : _ok,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('Enregistrer')),
          ),
        ],
      ),
    );
  }
}

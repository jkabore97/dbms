import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/notify/notifications_repository.dart';
import '../courier/courier_words.dart' show courierReasonLabel;

/// What a ring of the bell says, and where a tap on it goes.
///
/// The server writes each row's `message` in French — the push (060) sends
/// it as it is — and, since 099, the event's facts beside it in `params`.
/// On a French phone the server's line is shown, word for word what the
/// push said. On an English phone the line is written here from the kind
/// and its facts. A row with no facts (written before 099, or a message the
/// platform typed) reads as the server wrote it.
String notificationLine(BuildContext context, NotificationRow n) {
  final p = n.params;
  if (context.trLanguage != 'en' || p.isEmpty) return n.message;
  String s(String key) => '${p[key] ?? ''}';
  bool yes(String key) => p[key] == true;
  num? number(String key) {
    final v = p[key];
    return v is num ? v : num.tryParse('${v ?? ''}');
  }

  String money(String key, [String? currency]) {
    final v = number(key);
    final c = currency ?? (s('currency').isEmpty ? 'XOF' : s('currency'));
    return v == null ? '' : moneyFormat(c).format(v);
  }

  String date(String key) {
    final d = DateTime.tryParse(s(key));
    return d == null ? '' : DateFormat('dd/MM/yyyy', 'en').format(d);
  }

  final toShop = s('to') == 'shop';
  switch (n.kind) {
    case 'low_stock':
      return context.tr('Stock bas : {name} ({n} restant)',
          {'name': s('name'), 'n': s('quantity')});
    case 'member_joined':
      return context.tr('{who} a rejoint {org}', {'who': s('who'), 'org': s('org')});
    case 'debt_settled':
      return context.tr('Crédit soldé : {name} a fini de payer {amount}',
          {'name': s('customer'), 'amount': money('amount')});
    case 'tontine_ready':
      return context.tr('Tontine {name} : tour {round} prêt à clore, tout le monde a payé',
          {'name': s('name'), 'round': s('round')});
    case 'new_order':
      final total = [
        money('total'),
        if (yes('wave')) ' (Wave)',
        if (number('fee') != null)
          context.tr(' + livraison {fee}', {'fee': money('fee')}),
      ].join();
      return yes('booking')
          ? context.tr('Nouvelle demande de {name} : {total}', {'name': s('name'), 'total': total})
          : context.tr('Nouvelle commande de {name} : {total}', {'name': s('name'), 'total': total});
    case 'order_withdrawn':
      return yes('booking')
          ? context.tr('{name} a annulé sa demande', {'name': s('name')})
          : context.tr('{name} a annulé sa commande', {'name': s('name')});
    case 'order_accepted' || 'order_ready' || 'order_picked_up' || 'order_refused' ||
          'order_cancelled' when s('to') == 'customer':
      final status = switch (s('status')) {
        'accepted' => context.tr('acceptée'),
        'ready' => context.tr('prête'),
        'picked_up' => yes('booking') ? context.tr('terminée') : context.tr('récupérée'),
        'refused' => context.tr('refusée'),
        _ => context.tr('annulée'),
      };
      return yes('booking')
          ? context.tr('Votre réservation chez {shop} : {status}', {'shop': s('shop'), 'status': status})
          : context.tr('Votre commande chez {shop} : {status}', {'shop': s('shop'), 'status': status});
    case 'delivery_cancelled':
      return context.tr('La livraison pour {name} a été annulée par la boutique', {'name': s('name')});
    case 'courier_approved':
      return context.tr('Vous êtes livreur Mara : les livraisons vous attendent.');
    // The dossier (112): sent back with its reason, a new photo asked, and
    // the platform's own bell for a dossier sent.
    case 'courier_refused':
      final note = s('note');
      return context.tr('Votre demande de livreur est à corriger : {reason}.',
              {'reason': courierReasonLabel(context, s('reason')).toLowerCase()}) +
          (note.isEmpty ? '' : ' $note');
    case 'courier_photo':
      return s('reason') == 'new_selfie'
          ? context.tr('Mara demande une nouvelle photo de votre selfie.')
          : context.tr('Mara demande une nouvelle photo de votre pièce d\'identité.');
    case 'courier_application':
      return context.tr('Nouvelle demande de livreur : {name}', {'name': s('name')});
    case 'courier_suspended':
      return context.tr('Votre accès livreur est suspendu.');
    case 'courier_pending':
      return context.tr('Votre inscription livreur est à l\'étude.');
    case 'delivery_taken':
      return context.tr('Un livreur prend la commande de {name}', {'name': s('name')});
    case 'order_courier':
      return context.tr('Un livreur s\'occupe de votre commande chez {shop}', {'shop': s('shop')});
    case 'order_delivered':
      return toShop
          ? context.tr('La commande de {name} est livrée', {'name': s('name')})
          : context.tr('Votre commande chez {shop} est livrée', {'shop': s('shop')});
    case 'order_in_transit':
      return yes('self')
          ? context.tr('{shop} vous livre lui-même : votre commande est en route', {'shop': s('shop')})
          : context.tr('Votre commande chez {shop} est en route', {'shop': s('shop')});
    case 'delivery_failed':
      final reason = switch (s('reason')) {
        'absent' => context.tr('client absent'),
        'refused' => context.tr('refusée par le client'),
        'unreachable' => context.tr('client injoignable'),
        _ => context.tr('autre raison'),
      };
      return toShop
          ? context.tr('Livraison de {name} échouée ({reason}) : le livreur rapporte la commande.',
              {'name': s('name'), 'reason': reason})
          : context.tr('La livraison de votre commande chez {shop} n\'a pas pu se faire ({reason}).',
              {'shop': s('shop'), 'reason': reason});
    case 'order_paid':
      if (toShop) {
        return context.tr('Commande payée par Wave : {amount}. L\'argent part sur votre numéro Wave.',
            {'amount': money('amount')});
      }
      return yes('wave')
          ? context.tr('Paiement reçu par {shop} : merci !', {'shop': s('shop')})
          : context.tr('Votre paiement chez {shop} est confirmé', {'shop': s('shop')});
    case 'spot_approved':
      if (yes('wave')) {
        return context.tr('Mise en avant payée par Wave : elle est programmée.');
      }
      final start = DateTime.tryParse(s('starts_at'))?.toLocal();
      return context.tr('Votre mise en avant est validée : elle commence le {date}.', {
        'date': start == null ? '' : DateFormat('dd/MM, HH:mm', 'en').format(start),
      });
    case 'spot_refused':
      return context.tr('Votre demande de mise en avant n\'a pas été retenue.');
    case 'new_device':
      return context.tr(
          'Nouvelle connexion à votre compte sur {device}. Ce n\'était pas vous ? Ouvrez Compte › Sécurité et fermez les autres appareils.',
          {'device': s('device')});
    case 'pro_active':
      return yes('card')
          ? context.tr('Mara Pro est actif, payé par carte, jusqu\'au {date}.', {'date': date('until')})
          : context.tr('Mara Pro est actif jusqu\'au {date}.', {'date': date('until')});
    case 'cauris_board':
      final league = _league(context, s('league'));
      final farm = s('league').startsWith('farm|');
      final top = [
        for (final t in (p['top'] is List ? p['top'] as List : const []))
          if (t is Map)
            '${t['rank']}. ${t['name'] ?? (farm ? context.tr('une ferme') : context.tr('une boutique'))} ${t['score']}',
      ].join(' · ');
      final rank = _ordinal(number('rank')?.toInt() ?? 0);
      final where = yes('first')
          ? context.tr('Vous êtes 1er, bravo ! Gardez la tête.')
          : number('gap') != null
              ? context.tr('Vous êtes {rank} : encore {gap} cauris pour la place devant.',
                  {'rank': rank, 'gap': s('gap')})
              : context.tr('Vous êtes {rank}.', {'rank': rank});
      return context.tr('🏆 {league} : {top}. {where}',
          {'league': league, 'top': top, 'where': where});
    case 'cauris_prize':
      final args = {
        'rank': _ordinal(number('rank')?.toInt() ?? 0),
        'league': _league(context, s('league')),
        'points': s('points'),
      };
      return yes('spot')
          ? context.tr('🏆 {rank} de la semaine en {league} ! +{points} cauris, et votre vitrine mise en avant 7 jours.', args)
          : context.tr('🏆 {rank} de la semaine en {league} ! +{points} cauris.', args);
    case 'unlock':
      return switch (s('step')) {
        'invoices' => context.tr('Factures débloquées : {n} articles en vente et {p} en photo.',
            {'n': s('articles'), 'p': s('photos')}),
        'production' => context.tr('Production débloquée : l\'étape Remplir est terminée.'),
        'credits' => context.tr('Carnet de crédit débloqué : {n} commandes terminées.',
            {'n': s('orders')}),
        _ => n.message,
      };
    // The platform's gifts (100).
    case 'cauris_gift' || 'cauris_promo':
      final note = s('note');
      final line = n.kind == 'cauris_promo'
          ? context.tr('Mara vous offre {n} cauris, à utiliser avant le {date}',
              {'n': s('points'), 'date': date('until')})
          : context.tr('Mara vous offre {n} cauris', {'n': s('points')});
      return note.isEmpty ? '$line.' : '$line: $note.';
    case 'feature_gift':
      return context.tr('Mara vous offre {tool} jusqu\'au {date}.', {
        'tool': s('feature') == 'pro_all'
            ? context.tr('Mara Pro complet')
            : PlanTerms.labelOf(s('feature')),
        'date': date('until'),
      });
    // A gift taken back from the command center's journal (105).
    case 'gift_undone':
      return s('feature').isEmpty
          ? context.tr('Mara a repris {n} cauris offerts.', {'n': s('points')})
          : context.tr('Mara a annulé l\'ouverture de {tool}.', {
              'tool': s('feature') == 'pro_all'
                  ? context.tr('Mara Pro complet')
                  : PlanTerms.labelOf(s('feature')),
            });
    case 'payout_changed':
      return s('what') == 'wave'
          ? context.tr('Le compte Wave de vos ventes a été changé')
          : context.tr('Le numéro qui reçoit l\'argent de vos ventes a été changé');
    case 'org_kind_changed':
      return context.tr('Le genre de votre activité a été changé');
    // Mara's switchboard (104): one of the business's tools shown, hidden
    // or set back to its default.
    case 'feature_rule':
      final tool = context.tr(s('label'));
      return switch (s('state')) {
        'hidden' => context.tr('Mara a masqué « {tool} » pour votre activité.', {'tool': tool}),
        'visible' => context.tr('Mara a rendu « {tool} » visible pour votre activité.', {'tool': tool}),
        _ => context.tr('Mara a remis « {tool} » comme par défaut pour votre activité.', {'tool': tool}),
      };
    // A Pro tool a rule hides came back to hidden when the business's
    // payment ended (104): the admin's rule applies; renewing brings it back.
    case 'feature_lapsed':
      return context.tr('Votre Mara Pro a pris fin : {tool} n\'est plus disponible pour votre activité.',
          {'tool': context.tr(s('label'))});
    // The applicant hears the decision on their request (107).
    case 'application_approved':
      return context.tr('Votre demande est acceptée : {name} est ouverte.', {'name': s('name')});
    case 'application_refused':
      return context.tr('Votre demande pour {name} est refusée : {reason}',
          // A ready reason (applications_screen.dart) reads in English too.
          {'name': s('name'), 'reason': context.tr(s('reason'))});
    // A followed vitrine's news (113): one ring a day, said again in it.
    case 'vitrine_news':
      final names = [for (final x in (p['names'] is List ? p['names'] as List : const [])) '$x'];
      final count = number('count')?.toInt() ?? names.length;
      if (count <= 1) {
        return yes('offer')
            ? context.tr('Prix en baisse chez {shop} : {name} à {price}',
                {'shop': s('shop'), 'name': names.isEmpty ? '' : names.first, 'price': money('price')})
            : context.tr('Nouveau chez {shop} : {name}',
                {'shop': s('shop'), 'name': names.isEmpty ? '' : names.first});
      }
      return context.tr('{n} nouveautés chez {shop} : {names}', {
        'n': count,
        'shop': s('shop'),
        'names': names.join(', ') + (count > names.length ? '…' : ''),
      });
    // A report answered by Mara (113).
    case 'report_handled':
      final answer = s('answer');
      return answer.isEmpty
          ? context.tr('Mara a traité votre signalement. Merci !')
          : context.tr('Mara a traité votre signalement : {answer}', {'answer': answer});
    // Mara changed the business's vitrine or its identity from the command
    // center, or took her change back (106).
    case 'mara_edited' || 'mara_undone':
      final undone = n.kind == 'mara_undone';
      if (s('what') == 'vitrine') {
        return undone
            ? context.tr('Mara a annulé sa modification de votre vitrine')
            : context.tr('Mara a modifié votre vitrine');
      }
      if (undone) {
        return context.tr('Mara a annulé sa modification de l\'identité de votre activité');
      }
      return context.tr('Mara a modifié l\'identité de votre activité : {what}',
          {'what': _identityWords(context, p['fields'])});
  }
  return n.message;
}

/// « nom, téléphone »: the identity's columns Mara changed (106), in words.
String _identityWords(BuildContext context, Object? fields) {
  final words = <String>[];
  for (final f in (fields is List ? fields : const [])) {
    final w = switch ('$f') {
      'name' => context.tr('nom'),
      'slug' => context.tr('adresse web'),
      'profile' => context.tr('type d\'activité'),
      'default_currency' => context.tr('monnaie'),
      'phone' => context.tr('téléphone'),
      'address' => context.tr('adresse'),
      'verified_at' || 'verified_by' => context.tr('vérification'),
      final other => other,
    };
    if (!words.contains(w)) words.add(w);
  }
  return words.join(', ');
}

/// « Boutiques · Ouagadougou · petites », from the league's key
/// (`retail|Ouagadougou|petites`, 086).
String _league(BuildContext context, String key) {
  final parts = key.split('|');
  if (parts.length < 3) return key;
  final size = switch (parts[2]) {
    'petites' => context.tr('petites'),
    'moyennes' => context.tr('moyennes'),
    'grandes' => context.tr('grandes'),
    final other => other,
  };
  return [
    parts[0] == 'farm' ? context.tr('Fermes') : context.tr('Boutiques'),
    parts[1],
    size,
  ].join(' · ');
}

/// 1st, 2nd, 3rd, 4th… 11th, 12th, 13th, 21st.
String _ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$n$suffix';
}

/// Where a tap on a ring of the bell opens: the screen it is about, or null
/// when there is nothing more to see than the line itself (a message the
/// platform typed).
///
/// [isAdminOf] says whether the signed-in person answers for a business:
/// it decides, on a row from before 099 that does not say whom it was
/// written for, between the shop's « Commandes » and the customer's « Mes
/// commandes ». [profileOf] picks a farm's « À vendre » over a shop's
/// articles for low stock.
String? notificationTarget(
  NotificationRow n, {
  bool Function(String orgId)? isAdminOf,
  String? Function(String orgId)? profileOf,
}) {
  final org = n.orgId;
  final p = n.params;
  final to = p['to'] as String?;
  String inside(String rest) => Routes.inside(org!, rest);

  // An order's ring is the shop's or the customer's, whatever its kind.
  bool forShop() =>
      to == 'shop' || (to == null && org != null && (isAdminOf?.call(org) ?? false));

  switch (n.kind) {
    case 'courier_refused' || 'courier_photo':
      return Routes.becomeCourier;
    case 'courier_application':
      return Routes.consoleCouriers;
    case 'courier_approved' || 'courier_suspended' || 'courier_pending' ||
          'delivery_cancelled':
      return Routes.courier;
    case 'new_device':
      return Routes.security;
    case 'org_application':
      return Routes.applications;
    case 'spot_requested' || 'spot_paid':
      return Routes.consoleFeatured;
    case 'platform_message' || 'report_handled':
      return null;
    // A followed vitrine's news (113): the vitrine, which the follower is
    // not of.
    case 'vitrine_news':
      final slug = p['slug'];
      return slug is String && slug.isNotEmpty ? Routes.storefront(slug) : null;
  }
  if (org == null) return null;
  switch (n.kind) {
    case 'new_order' || 'order_withdrawn' || 'delivery_taken':
      return inside('commandes');
    case 'low_stock':
      if (profileOf?.call(org) == 'farm') return inside('a-vendre');
      final name = p['name'] as String?;
      return name == null || name.isEmpty
          ? inside('produits')
          : '${inside('produits')}?q=${Uri.encodeQueryComponent(name)}';
    case 'member_joined':
      return inside('equipe');
    case 'debt_settled':
      final customer = p['customer_id'] as String?;
      return customer == null ? inside('credits') : inside('credits/$customer');
    case 'tontine_ready':
      final tontine = p['tontine_id'] as String?;
      return tontine == null ? inside('tontines') : inside('tontines/$tontine');
    case 'unlock' || 'cauris_prize' || 'cauris_gift' || 'cauris_promo' ||
          'feature_gift' || 'gift_undone':
      return inside('chemin');
    case 'cauris_board':
      return inside('classement');
    case 'pro_active' || 'feature_lapsed':
      return inside('kaj-pro');
    case 'spot_approved' || 'spot_refused':
      return Routes.orgSettings(org, part: 'vitrine');
    // What Mara changed, where the owner sees it (106).
    case 'mara_edited' || 'mara_undone':
      return Routes.orgSettings(org,
          part: p['what'] == 'vitrine' ? 'vitrine' : 'identite');
  }
  if (n.kind.startsWith('order_') || n.kind.startsWith('delivery_')) {
    return forShop() ? inside('commandes') : Routes.myOrders;
  }
  return Routes.org(org);
}

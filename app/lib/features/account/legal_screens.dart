import 'package:flutter/material.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/nav/parent_route.dart';
import '../../core/theme/scroll_hint.dart';
import 'support.dart';

/// The three static pages the app must carry to be publishable: a privacy
/// policy, terms of use, and a short FAQ. They ship inside the app rather than
/// as links, so they open with no signal — a policy nobody can read offline is
/// a policy nobody reads on a two-bar connection.
///
/// The privacy policy and the terms stay in French on every phone: they are
/// legal texts, and the French one is the text that binds (the site serves
/// the same words). The FAQ is help, and is said in the phone's language.
///
/// The text is plain and in French, the app's primary language. It is written
/// to be true of what the app actually does today (Supabase storage, no resale
/// of data, WhatsApp support); update it when that changes. The site serves
/// the same two documents as plain pages (workers/kaj-app/src/legal.js), for
/// readers that run no JavaScript — Google's verification among them;
/// test/legal_pages_test.dart keeps the two copies saying the same thing.

class _DocScaffold extends StatelessWidget {
  const _DocScaffold({required this.title, required this.blocks, this.header});

  final String title;

  /// Drawn above the text (the FAQ's « Aide Mara » card).
  final Widget? header;

  /// Alternating (heading, body) is not assumed; each entry is a paragraph, and
  /// a heading is just a paragraph rendered bold via the leading '#'.
  final List<String> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScrollHint(child: Scaffold(
      appBar: AppBar(leading: parentBack(context), actions: const [bellRoom], title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          if (header case final header?) ...[header, const SizedBox(height: 20)],
          for (final b in blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: b.startsWith('# ')
                  ? Text(b.substring(2),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700))
                  : Text(b, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    ));
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DocScaffold(
      title: context.tr('Politique de confidentialité'),
      blocks: [
        'Mara enregistre les informations que vous saisissez pour faire '
            'fonctionner votre activité : ventes, dépenses, membres, produits, '
            'photos de pièces justificatives, et les personnes de votre équipe.',
        '# Ce que nous collectons',
        'Votre nom et votre numéro de téléphone, les données que vous entrez '
            'dans l\'application, et les photos que vous prenez pour vos reçus '
            'et livraisons.',
        '# Connexion avec Google',
        'Si vous vous connectez avec Google, nous recevons de Google votre nom, '
            'votre adresse e-mail et votre photo de profil. Ils servent '
            'uniquement à vous identifier et à afficher votre nom dans '
            'l\'application. Nous ne lisons rien d\'autre de votre compte Google '
            'et ne transmettons ces informations à personne.',
        '# Connexion avec Apple',
        'Si vous vous connectez avec Apple (sur iPhone), nous recevons '
            'd\'Apple une adresse e-mail — la vôtre, ou une adresse relais '
            'privée qu\'Apple crée pour vous — et, la première fois '
            'seulement, votre nom. Ils servent uniquement à vous identifier. '
            'Nous ne transmettons ces informations à personne.',
        '# Comment elles sont utilisées',
        'Uniquement pour vous fournir le service : afficher vos livres, vos '
            'rapports et vos stocks à vous et aux personnes que vous autorisez. '
            'Nous ne vendons pas vos données et ne les partageons pas à des fins '
            'publicitaires.',
        '# Où elles sont stockées',
        'Sur des serveurs sécurisés (Supabase et Cloudflare). Chaque activité '
            'ne voit que ses propres données ; l\'isolement entre activités est '
            'appliqué par le serveur.',
        '# Les prestataires',
        'Mara fait appel à quelques prestataires, chacun seulement pour '
            'ce qui le concerne : Supabase (la base de données et les '
            'comptes) et Cloudflare (le site, les photos) hébergent les '
            'données ; Google pour la connexion avec Google et l\'envoi des '
            'notifications sur le téléphone (Firebase) ; Apple pour la '
            'connexion avec Apple ; Stripe pour le '
            'paiement par carte de Mara Pro (Mara ne voit jamais le numéro '
            'de la carte) ; Sentry pour les rapports d\'erreur de '
            'l\'application (sans nom, numéro ni contenu de vos livres) ; '
            'Resend pour envoyer l\'e-mail de bienvenue ; '
            'et, quand ils sont ouverts, Wave pour le paiement par mobile '
            'money et WhatsApp (Meta) pour envoyer le code de vérification '
            'du numéro. Aucun ne reçoit vos données pour de la publicité.',
        '# Les visites des vitrines',
        'Quand vous ouvrez la vitrine d\'une activité, l\'application ou '
            'votre navigateur envoie un numéro tiré au hasard et gardé sur '
            'l\'appareil, afin que chaque visiteur ne soit compté qu\'une fois '
            'par jour. Ce numéro n\'est jamais lié à vous ni à votre compte, '
            'et la vitrine n\'affiche que le nombre de ses visiteurs. '
            'Les membres de l\'activité ne sont pas comptés ; les visites de '
            'plus de 400 jours sont effacées (le total reste).',
        '# Devenir livreur',
        'Pour devenir livreur, vous envoyez un selfie et la photo de votre '
            'pièce d\'identité (à moto ou en voiture, aussi votre permis). Ces '
            'photos sont gardées à part, en privé : seule l\'équipe Mara qui '
            'examine les demandes peut les voir, jamais les boutiques, les '
            'clients ni la rue. Si votre demande est refusée et que vous ne la '
            'renvoyez pas, elles ne sont plus jamais montrées après 30 jours, '
            'et sont effacées la fois suivante où la liste des livreurs est '
            'ouverte (par l\'équipe Mara, ou par vous sur « Devenir livreur »). '
            'Il en va de même, sans attendre, d\'une photo remplacée par une '
            'nouvelle et, après 30 jours sans suite, d\'une demande commencée '
            'puis laissée. Si vous êtes accepté, elles sont gardées tant que '
            'vous êtes livreur ; votre compte supprimé, elles ne sont plus '
            'montrées et sont effacées de la même façon.',
        'Quand vous êtes livreur et ouvrez les livraisons disponibles, votre '
            'téléphone donne votre position, si vous l\'autorisez. Mara garde '
            'la dernière, pour vous seul — ni les boutiques, ni les clients, ni '
            'les autres livreurs ne la voient — afin de vous montrer les '
            'livraisons proches et de vous prévenir de celles-ci. Après 24 '
            'heures, elle n\'est plus utilisée ; après 30 jours, elle est '
            'effacée.',
        '# Vos droits',
        'Vous pouvez demander la correction ou la suppression de vos '
            'données en contactant le support. Vous pouvez aussi télécharger '
            'vos données et supprimer votre compte vous-même, depuis Mon profil '
            '› Mes données : vos adresses, vos favoris et vos signalements '
            'partent avec lui ; vos commandes restent chez les boutiques, au '
            'nom de « Client supprimé », sans votre numéro ni votre adresse '
            '(une vente déjà inscrite dans leurs comptes y reste telle quelle). '
            'La suppression d\'une activité efface ses données de façon '
            'définitive.',
        '# Contact',
        'Pour toute question sur vos données, ou pour demander leur '
            'correction ou leur suppression, écrivez à '
            'hello@kaj-consulting.com, ou contactez le support depuis '
            'l\'écran Compte › Aide. Mara est édité par KAJ Consulting LLC.',
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DocScaffold(
      title: context.tr('Conditions d\'utilisation'),
      blocks: [
        'En utilisant Mara, vous acceptez ces conditions.',
        '# Votre compte',
        'Vous êtes responsable de l\'exactitude des informations que vous '
            'saisissez et de la confidentialité de votre code (PIN). Ne '
            'partagez pas votre accès avec une personne qui ne devrait pas voir '
            'vos données.',
        '# Utilisation correcte',
        'Mara est un outil de gestion pour votre activité. N\'utilisez pas '
            'l\'application pour enregistrer des activités illégales ou pour '
            'nuire à autrui.',
        '# Disponibilité',
        'Nous faisons de notre mieux pour que le service reste disponible, mais '
            'nous ne pouvons pas le garantir sans interruption. L\'application '
            'continue de fonctionner hors ligne et synchronise dès que la '
            'connexion revient.',
        '# Responsabilité',
        'Mara vous aide à tenir vos comptes, mais la responsabilité finale de '
            'vos décisions commerciales et de vos obligations légales vous '
            'revient.',
        '# Modifications',
        'Ces conditions peuvent évoluer. Les changements importants vous seront '
            'signalés dans l\'application.',
      ],
    );
  }
}

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DocScaffold(
      title: context.tr('Questions fréquentes'),
      // How to reach Mara first (126): the site's /aide says the same.
      header: const SupportCard(),
      blocks: [
        context.tr('# L\'application fonctionne-t-elle sans internet ?'),
        context.tr('Oui. Vous pouvez enregistrer des ventes et des dépenses hors ligne ; elles sont envoyées au serveur dès que la connexion revient. Certains écrans (rapports, historique) ont besoin de la connexion.'),
        context.tr('# Comment ajouter un employé ?'),
        context.tr('Dans Compte › Administration › Personnel, puis invitez la personne. Vous décidez ce que chacun peut voir et modifier.'),
        context.tr('# Comment changer la monnaie de mon activité ?'),
        context.tr('Dans Compte › Administration › Paramètres, choisissez la monnaie. Elle s\'applique partout dans l\'application.'),
        context.tr('# Comment recevoir un paiement Wave ?'),
        context.tr('Renseignez votre numéro Wave dans Paramètres, puis choisissez « Wave » au moment de la vente : le client scanne le QR et paie.'),
        context.tr('# Un client veut payer en dollars ou en euros.'),
        context.tr('Définissez vos taux dans Compte › Administration › Paramètres › Taux de change. À la vente, touchez la monnaie du client : l\'application affiche exactement le montant à encaisser, et le reçu garde les deux montants et le taux. Vos livres restent dans votre monnaie.'),
        context.tr('# Comment imprimer ou envoyer une facture ?'),
        context.tr('Ouvrez la facture : l\'icône imprimante lance l\'impression, et « Envoyer » la partage en image (WhatsApp ou autre). Le propriétaire peut aussi la corriger tant que rien n\'a été payé.'),
        context.tr('# Où sont les analyses et le carnet de crédit ?'),
        context.tr('Sous Compte › Mon entreprise, pour garder l\'écran de vente simple. Les analyses sont réservées au propriétaire.'),
        context.tr('# J\'ai oublié mon code (PIN).'),
        context.tr('Reconnectez-vous avec votre mot de passe pour définir un nouveau code.'),
        context.tr('# Comment contacter quelqu\'un ?'),
        context.tr('Depuis Compte › Aide (ou Mon profil › Aide) : par e-mail, ou sur WhatsApp quand le bouton est affiché.'),
      ],
    );
  }
}

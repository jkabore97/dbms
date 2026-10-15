import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/nav/parent_route.dart';
import '../../core/theme/scroll_hint.dart';
import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../help/help_contact.dart';
import 'support.dart';

/// The three static pages the app must carry to be publishable: a privacy
/// policy, terms of use, and a short FAQ. They ship inside the app rather than
/// as links, so they open with no signal — a policy nobody can read offline is
/// a policy nobody reads on a two-bar connection.
///
/// The privacy policy and the terms are written in French: they are legal
/// texts, and the French one is the text that binds (the site serves the
/// same words). A phone in English shows their faithful English translation
/// (en.dart, keyed by each French paragraph) under a note saying the French
/// binds (133). The FAQ is help, and is said in the phone's language.
///
/// The text is plain and in French, the app's primary language. It is written
/// to be true of what the app actually does today (Supabase storage, no resale
/// of data, WhatsApp support); update it when that changes. The site serves
/// the same two documents as plain pages (workers/kaj-app/src/legal.js), for
/// readers that run no JavaScript — Google's verification among them;
/// test/legal_pages_test.dart keeps the two copies saying the same thing.

class _DocScaffold extends StatelessWidget {
  const _DocScaffold({
    required this.title,
    required this.blocks,
    this.header,
    this.footer,
    this.legal = false,
  });

  final String title;

  /// A legal text, kept in French (the binding words): on a phone in
  /// English it is shown in its faithful English translation (en.dart),
  /// under a note that the French text is the one that binds (UI audit
  /// SH-9: App Review and English readers saw a French policy).
  final bool legal;

  /// Drawn above the text (the FAQ's « Aide Mara » card).
  final Widget? header;

  /// Drawn under the text (the FAQ's « Pas trouvé ? Écrire à Mara »).
  final Widget? footer;

  /// Alternating (heading, body) is not assumed; each entry is a paragraph, and
  /// a heading is just a paragraph rendered bold via the leading '#'.
  final List<String> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final english = legal && context.trLanguage != 'fr';
    // The French paragraphs are the keys of their English (en.dart).
    // « {email} » (the terms, 147) is the platform's support address, as
    // the app's « Aide » reads it (126's support_contacts).
    final email = {'email': Support.contacts.value.email};
    final shown = [
      for (final b in blocks) english ? context.tr(b, email) : translate('fr', b, email),
    ];
    return ScrollHint(child: Scaffold(
      appBar: AppBar(leading: parentBack(context), actions: const [bellRoom], title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          if (header case final header?) ...[header, const SizedBox(height: 20)],
          if (english)
            Card(
              key: const Key('legal-translation-note'),
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.tr('La version française de ce texte est celle qui fait foi. Voici sa traduction en anglais, pour information.'),
                  style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          for (final b in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: b.startsWith('# ')
                  ? Text(b.substring(2),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700))
                  : Text(b, style: theme.textTheme.bodyMedium),
            ),
          if (footer case final footer?) ...[const SizedBox(height: 8), footer],
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
      legal: true,
      blocks: [
        'Version 2 — en vigueur le 14 octobre 2026.',
        'Mara enregistre les informations que vous saisissez pour faire '
            'fonctionner votre activité : ventes, dépenses, membres, produits, '
            'photos de pièces justificatives, et les personnes de votre équipe.',
        '# Ce que nous collectons',
        'Votre nom et votre numéro de téléphone, votre date de naissance si '
            'vous la donnez (elle n\'est jamais obligatoire), les données que '
            'vous entrez dans l\'application, et les photos que vous prenez '
            'pour vos reçus et livraisons.',
        '# Connexion avec Google',
        'Si vous vous connectez avec Google, nous recevons de Google votre '
            'nom, votre adresse e-mail et votre photo de profil. Ils servent '
            'uniquement à vous identifier et à afficher votre nom dans '
            'l\'application. Nous ne lisons rien d\'autre de votre compte '
            'Google ; votre nom ne va qu\'aux personnes que décrit « Qui '
            'voit vos informations ».',
        '# Connexion avec Apple',
        'Si vous vous connectez avec Apple (sur iPhone), nous recevons '
            'd\'Apple une adresse e-mail — la vôtre, ou une adresse relais '
            'privée qu\'Apple crée pour vous — et, la première fois '
            'seulement, votre nom. Ils servent uniquement à vous identifier '
            '; votre nom ne va qu\'aux personnes que décrit « Qui voit vos '
            'informations ».',
        '# Comment elles sont utilisées',
        'Uniquement pour vous fournir le service : afficher vos livres, vos '
            'rapports et vos stocks à vous et aux personnes que vous autorisez. '
            'Nous ne vendons pas vos données et ne les partageons pas à des fins '
            'publicitaires.',
        '# Qui voit vos informations',
        'Quand vous commandez ou réservez, l\'entreprise reçoit ce qu\'il '
            'lui faut pour vous servir : votre nom, votre numéro de '
            'téléphone (celui que WhatsApp a vérifié, quand Mara le '
            'demande), votre adresse et le point de livraison sur la carte, '
            'et votre message. Les membres de l\'entreprise qui gèrent les '
            'commandes les voient, et elle les garde dans ses comptes, comme '
            'une boutique garde ses ventes.',
        'Pour une livraison, les livreurs proches voient l\'adresse et le '
            'point de livraison, sans votre nom ni votre numéro ; le livreur '
            'qui prend la course reçoit ensuite votre nom et votre numéro, '
            'pour vous joindre pendant la livraison, et s\'engage par sa '
            'charte à ne pas s\'en servir pour autre chose.',
        'Un formateur Mara ne voit les données d\'une entreprise qu\'à sa '
            'demande, en lecture seule et pour un temps limité. En dehors de '
            'ces cas et des prestataires ci-dessous, Mara ne transmet vos '
            'informations à personne, sauf sur une demande légale des '
            'autorités.',
        '# Où elles sont stockées',
        'Sur des serveurs sécurisés (Supabase et Cloudflare). Chaque activité '
            'ne voit que ses propres données ; l\'isolement entre activités est '
            'appliqué par le serveur.',
        '# Les prestataires',
        'Mara fait appel à quelques prestataires, chacun seulement pour ce '
            'qui le concerne : Supabase (la base de données et les comptes) et '
            'Cloudflare (le site, les photos) hébergent les données ; Google '
            'pour la connexion avec Google et l\'envoi des notifications sur le '
            'téléphone (Firebase) ; Apple pour la connexion avec Apple ; Apple '
            '(l\'App Store) et Google (Google Play) pour l\'abonnement Mara Pro '
            'pris dans l\'application, qu\'ils facturent et gèrent eux-mêmes ; '
            'Stripe pour le paiement par carte de Mara Pro (Mara ne voit jamais '
            'le numéro de la carte) ; Sentry pour les rapports d\'erreur de '
            'l\'application (sans nom, numéro ni contenu de vos livres) ; '
            'Resend pour envoyer l\'e-mail de bienvenue ; et, quand ils sont '
            'ouverts, Wave pour le paiement par mobile money et WhatsApp (Meta) '
            'pour envoyer le code de vérification du numéro. Aucun ne reçoit '
            'vos données pour de la publicité.',
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
        '# Vérifications contre la fraude',
        'Pour protéger les clients et les entreprises, Mara peut vérifier '
            'votre numéro de téléphone (un code envoyé sur WhatsApp) et, '
            'pour une entreprise ou un livreur, demander une pièce '
            'd\'identité ou des documents sur l\'activité. Ces pièces '
            'servent seulement à cette vérification ; seule l\'équipe Mara '
            'les voit.',
        '# Ce que Mara garde',
        'Mara garde la trace de votre acceptation des conditions (le '
            'document, sa version, la date, l\'application utilisée) tant '
            'que votre compte existe. Mara garde aussi les informations que '
            'la loi exige ou permet de conserver pour régler un litige ou '
            'prouver une fraude, et peut les transmettre aux autorités sur '
            'une demande légale.',
        '# Vos droits',
        'Vous pouvez demander la correction ou la suppression de vos '
            'données en contactant le support. Vous pouvez aussi télécharger '
            'vos données et supprimer votre compte vous-même, tout de suite, '
            'depuis Mon profil › Mes données (ou Compte › Mes données si vous '
            'tenez une activité ou en êtes membre) : votre profil, vos '
            'adresses, vos favoris, vos notifications et vos signalements '
            'partent avec lui ; vos commandes restent chez les boutiques, au '
            'nom de « Client supprimé », sans votre numéro ni votre adresse ; '
            'ce que vous avez inscrit pour une activité (une vente, une '
            'écriture) lui reste, sans votre nom. Si vous êtes le seul '
            'propriétaire d\'une activité, elle est supprimée avec votre compte '
            ': ses ventes, son stock, ses comptes et sa vitrine sont effacés de '
            'façon définitive, ses commandes en cours sont annulées et ses '
            'clients prévenus, et ses membres gardent leur propre compte. Un '
            'abonnement Mara Pro pris sur l\'App Store s\'annule dans les '
            'réglages de votre compte Apple : Mara ne peut pas l\'annuler.',
        '# Contact',
        'Pour toute question sur vos données, ou pour demander leur '
            'correction ou leur suppression, écrivez à '
            'hello@kaj-consulting.com, ou contactez le support depuis '
            'l\'écran Compte › Aide. Mara est édité par KAJ Consulting LLC.',
      ],
    );
  }
}

/// The Conditions d'utilisation, version 2 (147): who runs Mara, its role,
/// accounts, businesses, customers, payments, couriers, cauris, trainers,
/// Mara's rights, reporting, liability, data, changes, the law (« [à valider
/// par un avocat] ») and the language. The version is [termsTextVersion]:
/// a new text is a new version in 142's terms_versions, accepted again by
/// everyone (the gate, terms_gate.dart).
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

/// The version of the words below; 142's terms_versions.terms says which
/// version the server asks to accept.
const termsTextVersion = 2;

class _TermsScreenState extends State<TermsScreen> {
  @override
  void initState() {
    super.initState();
    // The e-mail the terms name is the platform's: asked once, ahead.
    final client = AppScope.read(context)?.auth.client;
    if (client != null) unawaited(Support.warm(client));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Support.contacts,
      builder: (context, _, _) => _terms(context),
    );
  }

  Widget _terms(BuildContext context) {
    return _DocScaffold(
      title: context.tr('Conditions d\'utilisation'),
      legal: true,
      blocks: [
        'Version 2 — en vigueur le 14 octobre 2026.',
        'Ces conditions s\'appliquent à toute personne qui utilise Mara : '
            'l\'application, le site marakaj.com et les vitrines. En créant '
            'un compte, ou en continuant à utiliser Mara, vous les acceptez.',
        '# Qui exploite Mara',
        'Mara (« propulsé par Kaj ») est un service exploité par KAJ '
            'Consulting LLC, une société des États-Unis. Dans ces '
            'conditions, « Mara » et « nous » désignent KAJ Consulting LLC ; '
            '« vous » désigne la personne qui utilise Mara.',
        '# Le rôle de Mara',
        'Mara est une plateforme et un intermédiaire : elle aide des '
            'entreprises (boutiques, fermes, associations) à tenir leurs '
            'comptes, à montrer leurs articles et à recevoir des commandes, '
            'et elle les met en relation avec des clients et des livreurs.',
        'Chaque entreprise est le vendeur. Elle seule répond de ses articles '
            'et de ses services, de ses prix, de ses livraisons, de ses '
            'reçus, de ses impôts et de ses taxes. Mara n\'est pas partie à '
            'la vente entre une entreprise et son client : Mara n\'achète '
            'pas, ne revend pas et ne garantit pas ce qui est vendu.',
        '# Votre compte',
        'Vous donnez des informations vraies et à jour : votre nom, votre '
            'numéro de téléphone. Un compte appartient à une seule personne '
            ': ne le prêtez pas, ne le vendez pas, et n\'ouvrez pas de '
            'compte au nom de quelqu\'un d\'autre.',
        'Âge minimum : 16 ans pour commander ; 18 ans pour ouvrir une '
            'entreprise ou devenir livreur. Avant 18 ans, utilisez Mara avec '
            'l\'accord d\'un parent ou d\'un tuteur.',
        'Gardez secrets votre mot de passe, votre code (PIN) et les codes '
            'que vous recevez par SMS ou WhatsApp : Mara ne vous les '
            'demandera jamais. Ce qui est fait avec votre compte est réputé '
            'fait par vous ; si quelqu\'un d\'autre y a accès, prévenez-nous '
            'tout de suite.',
        'Mara peut vous demander de vérifier votre numéro de téléphone (un '
            'code envoyé sur WhatsApp), notamment avant de commander, de '
            'créer une entreprise ou de devenir livreur.',
        '# Les entreprises',
        'Une entreprise sur Mara doit exister vraiment et avoir une activité '
            'légale là où elle vend. La personne qui la crée en répond, et '
            'accepte les « Engagements du vendeur », qui résument cette '
            'partie.',
        'Vous publiez seulement des photos et des textes qui sont à vous, ou '
            'que vous avez le droit d\'utiliser. Vos prix, vos stocks et vos '
            'délais sont exacts et tenus à jour. Une commande acceptée est '
            'honorée ; si ce n\'est pas possible, vous prévenez le client '
            'tout de suite et vous l\'annulez dans Mara.',
        'Il est interdit de vendre ou de proposer sur Mara : armes, '
            'munitions et explosifs ; drogues ; médicaments sans '
            'l\'autorisation que la loi exige ; contrefaçons ; objets volés '
            'ou d\'origine douteuse ; contenus pour adultes et services '
            'sexuels ; animaux sauvages vivants, espèces protégées et leurs '
            'parties ; produits dangereux (produits chimiques, pesticides '
            'interdits, gaz) ; faux documents ; montages financiers (« '
            'doublement d\'argent », ventes pyramidales, loteries ou prêts '
            'sans autorisation) ; et tout ce que la loi du pays interdit.',
        'Il est interdit de se faire passer pour une marque, une entreprise '
            'ou une personne, d\'utiliser leur nom ou leur logo sans en '
            'avoir le droit, ou de copier la vitrine d\'une autre entreprise.',
        'Pour une commande passée sur Mara, ne demandez jamais au client de '
            'payer autrement que par les moyens convenus dans la commande '
            '(par exemple sur un autre numéro, ou un acompte en dehors de '
            'Mara).',
        'Mara peut vérifier l\'identité d\'une personne ou l\'existence '
            'd\'une entreprise, et demander des pièces : pièce d\'identité, '
            'registre de commerce, autorisation, justificatif d\'adresse. '
            'Sans réponse, ou si les pièces ne suffisent pas, Mara peut '
            'limiter, suspendre ou fermer l\'entreprise.',
        '# Les clients',
        'Vous commandez de bonne foi, pour vous ou pour quelqu\'un qui vous '
            'l\'a demandé. Vous êtes présent, ou joignable, pour recevoir la '
            'commande et la payer comme convenu. Les fausses commandes, les '
            'commandes pour rire et les commandes passées pour nuire à une '
            'entreprise sont interdites.',
        'Une réclamation sur un article (qualité, quantité, retour, '
            'remboursement) se règle d\'abord avec l\'entreprise, qui en '
            'répond. Si cela ne s\'arrange pas, signalez-le à Mara.',
        '# Les paiements',
        'En espèces : le client paie l\'entreprise, ou son livreur, à la '
            'remise. Cet argent ne passe pas par Mara, qui n\'en répond pas.',
        'Par Wave ou par carte, quand l\'entreprise le propose : le client '
            'paie en ligne, par Mara et son prestataire de paiement, puis '
            'Mara reverse le montant à l\'entreprise, moins la commission '
            'annoncée. Un remboursement est décidé par l\'entreprise, sauf '
            'erreur de Mara.',
        'Mara Pro et « Mettre en avant » sont des services numériques que '
            'Mara vend aux entreprises. Ils se paient dans l\'application '
            '(Google Play ou App Store), par carte (Stripe) ou par les '
            'autres moyens que Mara indique. Achetés sur Google Play ou '
            'l\'App Store, ils suivent les règles de remboursement du store.',
        'Une mise en avant déjà montrée, même en partie, n\'est pas '
            'remboursée, sauf si la loi l\'exige ou si Mara n\'a pas pu la '
            'montrer.',
        '# Mara Pro',
        'Mara Pro est un abonnement, au mois ou à l\'année, pour une '
            'activité : il vaut pour celle pour laquelle il a été pris. Pris '
            'dans l\'application iPhone ou Android, il est facturé et géré '
            'par l\'App Store ou Google Play : le prix est celui que le '
            'store affiche, le paiement est débité sur votre compte du store '
            'à la confirmation de l\'achat, l\'abonnement se renouvelle '
            'automatiquement sauf s\'il est annulé au moins 24 heures avant '
            'la fin de la période en cours, et il s\'annule dans les '
            'réglages de votre compte du store, selon ses règles.',
        '# Les livreurs',
        'Les livreurs sont indépendants : ils ne sont employés ni par Mara '
            'ni par les entreprises. Avant d\'être acceptés, ils acceptent '
            'la charte du livreur.',
        'L\'argent encaissé à la porte appartient à l\'entreprise : le '
            'livreur le lui remet le jour même, sans rien garder d\'autre '
            'que ce que Mara affiche comme lui revenant.',
        'Le code de livraison prouve que la commande a été remise. Le client '
            'le donne au livreur à la remise, et seulement à ce moment-là : '
            'ne le donnez jamais avant d\'avoir reçu votre commande. Un '
            'livreur ne le demande jamais à l\'avance.',
        '# Cauris, ligues, prix et parrainage',
        'Les cauris sont des points de Mara. Ils n\'ont aucune valeur en '
            'argent : ils ne s\'achètent pas, ne se vendent pas, ne '
            's\'échangent pas contre de l\'argent et ne se transfèrent pas.',
        'Mara peut annuler des cauris, un classement, un prix ou un '
            'parrainage obtenus par la fraude : faux comptes ou comptes '
            'multiples, fausses commandes, commandes entre proches pour '
            'gagner des points, ou tout autre contournement des règles. Ces '
            'règles peuvent changer ; l\'application montre toujours celles '
            'du moment.',
        '# Formateurs et aide',
        'Un formateur Mara ne voit les données d\'une entreprise qu\'avec '
            'l\'accord de son propriétaire ou d\'un administrateur, en '
            'lecture seule et pour une durée limitée. Il ne peut rien '
            'modifier ni rien vendre au nom de l\'entreprise.',
        '# Les droits de Mara',
        'Mara peut retirer un contenu (photo, texte, article) contraire à '
            'ces conditions ou à la loi.',
        'Mara peut suspendre ou fermer une entreprise ou un compte qui ne '
            'respecte pas ces conditions. En cas de fraude, de risque pour '
            'd\'autres personnes ou de plainte sérieuse, Mara peut le faire '
            'tout de suite ; sinon, Mara prévient d\'abord et dit pourquoi, '
            'quand c\'est possible.',
        'Mara garde les informations dont la loi exige ou permet la '
            'conservation pour régler un litige ou prouver une fraude '
            '(commandes, paiements, signalements, échanges avec l\'aide), y '
            'compris après la fermeture d\'une entreprise ou d\'un compte.',
        'Mara coopère avec les autorités : sur une demande légale, ou pour '
            'protéger une personne, Mara peut leur transmettre les '
            'informations utiles.',
        '# Signaler un problème',
        'Une vitrine, un article, une commande ou une personne vous semble '
            'frauduleux ? Touchez « Signaler cette vitrine » dans le menu ⋮ de la vitrine, '
            'ou écrivez à {email}. Mara examine chaque signalement.',
        '# Responsabilité',
        'Nous faisons de notre mieux pour que le service reste disponible, '
            'mais nous ne pouvons pas le garantir sans interruption. '
            'L\'application continue de fonctionner hors ligne et '
            'synchronise dès que la connexion revient.',
        'Mara ne garantit aucune vente, aucun nombre de visiteurs et aucun '
            'revenu. Mara ne répond pas des articles, des services, des prix '
            'ni du comportement des entreprises, des clients ou des '
            'livreurs, ni des pertes indirectes (manque à gagner, perte de '
            'clientèle).',
        'Si la responsabilité de Mara est engagée, elle est limitée, dans la '
            'mesure où la loi le permet, à ce que vous avez payé à Mara '
            'pendant les 12 derniers mois. Rien dans ces conditions ne vous '
            'retire un droit que la loi vous donne et qu\'un contrat ne peut '
            'pas écarter.',
        'Mara vous aide à tenir vos comptes, mais la responsabilité finale '
            'de vos décisions commerciales et de vos obligations légales '
            'vous revient.',
        '# Vos données',
        'Ce que Mara fait de vos données est expliqué dans la Politique de '
            'confidentialité, qui fait partie de ces conditions.',
        '# Modifications',
        'Mara peut modifier ces conditions. Une nouvelle version porte un '
            'nouveau numéro et une nouvelle date ; l\'application vous la '
            'montre, avec ce qui a changé, et vous demande de l\'accepter '
            'pour continuer à utiliser Mara. Si vous ne l\'acceptez pas, '
            'vous pouvez supprimer votre compte.',
        '# Droit applicable et litiges',
        '[à valider par un avocat] Le droit qui s\'applique à ces conditions '
            'et le tribunal compétent en cas de litige seront précisés ici. '
            'En cas de désaccord, écrivez-nous d\'abord à {email} : nous '
            'cherchons toujours une solution amiable.',
        '# Langue et contact',
        'Ces conditions sont écrites en français, et la version française '
            'fait foi ; la traduction anglaise est donnée pour information. '
            'Pour toute question : {email}, ou l\'aide de l\'application '
            '(Compte › Aide, ou Mon profil › Aide).',
      ],
    );
  }
}

/// « Questions fréquentes ». Opened from a business (`/aide?org=<id>`,
/// 143) it is that business's: a Basic one sees the Pro banner at the top
/// (FaqProBanner — closable, back the next day) and « Réponse sous 48 h »
/// on Mara's card; a Pro one no banner. Opened from anywhere else — signed
/// out, a shopper, an id that is not one of this person's businesses —
/// neither: the questions and Mara's card, as 126 had them.
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key, this.orgId, this.org});

  /// The business it was opened from (the address's ?org=).
  final String? orgId;

  /// The business itself (tests); else looked up by [orgId] in the
  /// person's own list — an id in an address grants nothing.
  final OrgSummary? org;

  @override
  Widget build(BuildContext context) {
    final business = org ??
        (orgId == null ? null : AppScope.maybeOf(context)?.session.orgById(orgId));
    return _DocScaffold(
      title: context.tr('Questions fréquentes'),
      // How to reach Mara first (126): the site's /aide says the same.
      // A business reaches Mara from its Aide page only: here the Pro
      // banner on top (Basic), and at the foot one line that leads there.
      // Someone with no business keeps the contact card itself.
      header: business == null
          ? const SupportCard()
          : FaqProBanner.shownFor(business)
              ? FaqProBanner(org: business)
              : null,
      footer: business == null
          ? null
          : OutlinedButton.icon(
              key: const Key('faq-write-mara'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () => context.push(Routes.inside(business.id, 'aide')),
              icon: const Icon(Icons.chat_outlined),
              label: Text(context.tr('Pas trouvé ? Écrire à Mara')),
            ),
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
        context.tr('Depuis la page Aide de votre entreprise (Compte › Aide), ou Mon profil › Aide : par WhatsApp ou par e-mail.'),
      ],
    );
  }
}

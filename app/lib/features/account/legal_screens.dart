import 'package:flutter/material.dart';

/// The three static pages the app must carry to be publishable: a privacy
/// policy, terms of use, and a short FAQ. They ship inside the app rather than
/// as links, so they open with no signal — a policy nobody can read offline is
/// a policy nobody reads on a two-bar connection.
///
/// The text is plain and in French, the app's primary language. It is written
/// to be true of what the app actually does today (Supabase storage, no resale
/// of data, WhatsApp support); update it when that changes.

class _DocScaffold extends StatelessWidget {
  const _DocScaffold({required this.title, required this.blocks});

  final String title;

  /// Alternating (heading, body) is not assumed; each entry is a paragraph, and
  /// a heading is just a paragraph rendered bold via the leading '#'.
  final List<String> blocks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
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
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScaffold(
      title: 'Politique de confidentialité',
      blocks: [
        'Kaj enregistre les informations que vous saisissez pour faire '
            'fonctionner votre activité : ventes, dépenses, membres, produits, '
            'photos de pièces justificatives, et les personnes de votre équipe.',
        '# Ce que nous collectons',
        'Votre nom et votre numéro de téléphone, les données que vous entrez '
            'dans l\'application, et les photos que vous prenez pour vos reçus '
            'et livraisons.',
        '# Comment elles sont utilisées',
        'Uniquement pour vous fournir le service : afficher vos livres, vos '
            'rapports et vos stocks à vous et aux personnes que vous autorisez. '
            'Nous ne vendons pas vos données et ne les partageons pas à des fins '
            'publicitaires.',
        '# Où elles sont stockées',
        'Sur des serveurs sécurisés (Supabase et Cloudflare). Chaque activité '
            'ne voit que ses propres données ; l\'isolement entre activités est '
            'appliqué par le serveur.',
        '# Vos droits',
        'Vous pouvez demander la correction ou la suppression de vos données en '
            'contactant le support. La suppression d\'une activité efface ses '
            'données de façon définitive.',
        '# Contact',
        'Pour toute question sur vos données, contactez le support depuis '
            'l\'écran Compte › Aide.',
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DocScaffold(
      title: "Conditions d'utilisation",
      blocks: [
        'En utilisant Kaj, vous acceptez ces conditions.',
        '# Votre compte',
        'Vous êtes responsable de l\'exactitude des informations que vous '
            'saisissez et de la confidentialité de votre code (PIN). Ne '
            'partagez pas votre accès avec une personne qui ne devrait pas voir '
            'vos données.',
        '# Utilisation correcte',
        'Kaj est un outil de gestion pour votre activité. N\'utilisez pas '
            'l\'application pour enregistrer des activités illégales ou pour '
            'nuire à autrui.',
        '# Disponibilité',
        'Nous faisons de notre mieux pour que le service reste disponible, mais '
            'nous ne pouvons pas le garantir sans interruption. L\'application '
            'continue de fonctionner hors ligne et synchronise dès que la '
            'connexion revient.',
        '# Responsabilité',
        'Kaj vous aide à tenir vos comptes, mais la responsabilité finale de '
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
    return const _DocScaffold(
      title: 'Questions fréquentes',
      blocks: [
        '# L\'application fonctionne-t-elle sans internet ?',
        'Oui. Vous pouvez enregistrer des ventes et des dépenses hors ligne ; '
            'elles sont envoyées au serveur dès que la connexion revient. '
            'Certains écrans (rapports, historique) ont besoin de la connexion.',
        '# Comment ajouter un employé ?',
        'Dans Compte › Administration › Personnel, puis invitez la personne. '
            'Vous décidez ce que chacun peut voir et modifier.',
        '# Comment changer la monnaie de mon activité ?',
        'Dans Compte › Administration › Paramètres, choisissez la monnaie. Elle '
            's\'applique partout dans l\'application.',
        '# Comment recevoir un paiement Wave ?',
        'Renseignez votre numéro Wave dans Paramètres, puis choisissez « Wave » '
            'au moment de la vente : le client scanne le QR et paie.',
        '# Un client veut payer en dollars ou en euros.',
        'Définissez vos taux dans Compte › Administration › Paramètres › Taux '
            'de change. À la vente, touchez la monnaie du client : '
            'l\'application affiche exactement le montant à encaisser, et le '
            'reçu garde les deux montants et le taux. Vos livres restent dans '
            'votre monnaie.',
        '# Comment imprimer ou envoyer une facture ?',
        'Ouvrez la facture : l\'icône imprimante lance l\'impression, et '
            '« Envoyer » la partage en image (WhatsApp ou autre). Le '
            'propriétaire peut aussi la corriger tant que rien n\'a été payé.',
        '# Où sont les analyses et le carnet de crédit ?',
        'Sous Compte › Mon entreprise, pour garder l\'écran de vente simple. '
            'Les analyses sont réservées au propriétaire.',
        '# J\'ai oublié mon code (PIN).',
        'Reconnectez-vous avec votre mot de passe pour définir un nouveau code.',
        '# Comment contacter quelqu\'un ?',
        'Depuis Compte › Aide › Contacter le support, sur WhatsApp.',
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// What each lesson of Académie Mara shows, step by step (087). The list
/// of lessons — which exist, which are missions, for which kind of
/// business — is the server's; the words and pictures are here, short and
/// in the shopkeeper's own vocabulary, one idea per step.
class LessonStep {
  const LessonStep(this.icon, this.title, this.text, {this.point});

  /// What the phone in the picture shows.
  final IconData icon;
  final String title;
  final String text;

  /// Where on the pictured phone the hand taps (0–1, 0–1); null: no hand.
  final Offset? point;
}

class LessonScript {
  const LessonScript({required this.steps, this.tryIt, this.tryLabel});

  final List<LessonStep> steps;

  /// The page where the mission is lived, inside the business ('produits').
  final String? tryIt;
  final String? tryLabel;
}

const lessonScripts = <String, LessonScript>{
  'welcome': LessonScript(steps: [
    LessonStep(Icons.waving_hand_outlined, 'Bienvenue sur Mara',
        'Mara tient votre boutique dans votre poche : la caisse, le stock, '
            'et une vitrine où les clients du quartier commandent.'),
    LessonStep(Icons.home_outlined, 'L\'accueil',
        'Chaque matin, l\'accueil vous dit votre journée : ce qui est vendu, '
            'ce qui manque, les commandes à traiter.',
        point: Offset(0.5, 0.35)),
    LessonStep(Icons.menu, 'Le menu « Plus »',
        'Tout le reste est dans « Plus », en bas à droite : vos articles, '
            'votre vitrine, vos cauris.',
        point: Offset(0.85, 0.92)),
    LessonStep(Icons.savings_outlined, 'Des cauris pour chaque progrès',
        'Chaque leçon de l\'Académie et chaque bonne vente vous rapportent '
            'des cauris, à dépenser en outils Pro.'),
  ]),
  'first_article': LessonScript(
    tryIt: 'produits',
    tryLabel: 'Ouvrir mes articles',
    steps: [
      LessonStep(Icons.inventory_2_outlined, 'Vos articles',
          'Ouvrez « Articles » : c\'est votre rayon.',
          point: Offset(0.3, 0.92)),
      LessonStep(Icons.add_circle_outline, 'Ajoutez-en un',
          'Le bouton « + » : un nom, un prix, combien vous en avez.',
          point: Offset(0.82, 0.82)),
      LessonStep(Icons.storefront_outlined, 'Sur la vitrine',
          'Cochez « Sur la vitrine » : les clients le voient et peuvent le '
              'commander.',
          point: Offset(0.7, 0.55)),
    ],
  ),
  'vitrine_open': LessonScript(
    tryIt: 'administration/parametres',
    tryLabel: 'Ouvrir ma vitrine',
    steps: [
      LessonStep(Icons.settings_outlined, 'Les paramètres',
          'Compte › Administration › Paramètres › Vitrine.'),
      LessonStep(Icons.toggle_on_outlined, 'Ouvrez-la',
          '« Ouvrir la vitrine » : votre boutique a sa page, à partager sur '
              'WhatsApp.',
          point: Offset(0.8, 0.4)),
      LessonStep(Icons.place_outlined, 'Dites où vous êtes',
          'Adresse, téléphone, position sur la carte : les clients vous '
              'trouvent, et votre vitrine monte vers 100 %.',
          point: Offset(0.5, 0.65)),
    ],
  ),
  'photos': LessonScript(
    tryIt: 'produits',
    tryLabel: 'Prendre mes photos',
    steps: [
      LessonStep(Icons.photo_camera_outlined, 'Une photo vend',
          'Un article en photo se vend bien mieux qu\'un nom tout seul.'),
      LessonStep(Icons.touch_app_outlined, 'Touchez l\'article',
          'Dans Articles, touchez-en un, puis le carré de la photo.',
          point: Offset(0.3, 0.4)),
      LessonStep(Icons.wb_sunny_outlined, 'À la lumière du jour',
          'Sur un fond simple, l\'article bien au centre. Trois photos et '
              'votre vitrine fait envie.'),
    ],
  ),
  'first_sale': LessonScript(
    tryIt: '',
    tryLabel: 'Aller à la caisse',
    steps: [
      LessonStep(Icons.point_of_sale_outlined, 'La caisse',
          'Le gros bouton « Vente » de l\'accueil.',
          point: Offset(0.5, 0.82)),
      LessonStep(Icons.add_shopping_cart, 'Choisissez les articles',
          'Touchez ce que le client prend ; le total se fait tout seul.',
          point: Offset(0.4, 0.45)),
      LessonStep(Icons.payments_outlined, 'Encaissez',
          'Espèces, Wave ou à crédit : touchez, c\'est noté, le stock '
              'descend.',
          point: Offset(0.6, 0.85)),
    ],
  ),
  'farm_log': LessonScript(
    tryIt: 'bandes',
    tryLabel: 'Ouvrir mes bandes',
    steps: [
      LessonStep(Icons.pets_outlined, 'Vos bandes',
          'Ouvrez « Bandes » : chaque lot d\'animaux a sa fiche.',
          point: Offset(0.5, 0.92)),
      LessonStep(Icons.edit_note, 'Chaque jour, une ligne',
          'Mortalité, pesée, vaccin : notez ce qui s\'est passé.',
          point: Offset(0.7, 0.5)),
      LessonStep(Icons.savings_outlined, 'Un cahier qui rapporte',
          'Un cahier tenu chaque jour rapporte des cauris, et vous dit tôt '
              'quand une bande va mal.'),
    ],
  ),
  'first_order': LessonScript(
    tryIt: 'commandes',
    tryLabel: 'Voir mes commandes',
    steps: [
      LessonStep(Icons.notifications_active_outlined, 'Une commande arrive',
          'La vitrine vous prévient : « Nouvelle commande ».'),
      LessonStep(Icons.check_circle_outline, 'Acceptez vite',
          'Ouvrez-la et touchez « Accepter ». En moins de 15 minutes, elle '
              'vous rapporte des cauris.',
          point: Offset(0.7, 0.75)),
      LessonStep(Icons.inventory_outlined, 'Préparez, remettez',
          '« Prête », puis « Remise » quand le client l\'a : la commande est '
              'terminée.',
          point: Offset(0.5, 0.85)),
    ],
  ),
  'cauris': LessonScript(
    tryIt: 'cauris',
    tryLabel: 'Voir mes cauris',
    steps: [
      LessonStep(Icons.savings_outlined, 'Les cauris',
          'Comme autrefois au marché, les cauris sont une monnaie : la vôtre '
              'sur Mara.'),
      LessonStep(Icons.trending_up, 'On les gagne en vendant bien',
          'Commandes terminées, clients qui reviennent, vitrine complète, '
              'caisse tenue : chaque bonne habitude rapporte.'),
      LessonStep(Icons.lock_open_outlined, 'On les dépense en outils',
          'Un outil Pro grisé ? Débloquez-le 30 jours avec vos cauris, sans '
              'payer.',
          point: Offset(0.75, 0.5)),
    ],
  ),
  'league': LessonScript(
    tryIt: 'classement',
    tryLabel: 'Voir le classement',
    steps: [
      LessonStep(Icons.emoji_events_outlined, 'Votre ligue',
          'Vous courez avec les boutiques de votre ville et de votre taille.'),
      LessonStep(Icons.leaderboard_outlined, 'Chaque semaine',
          'Les cauris gagnés du lundi au dimanche font votre place. Dépenser '
              'ne la fait jamais perdre.'),
      LessonStep(Icons.workspace_premium_outlined, 'Le podium',
          'Les 3 premiers gagnent des cauris et le badge « Top 3 » sur leur '
              'vitrine ; le premier est mis en avant.'),
    ],
  ),
};

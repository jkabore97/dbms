# Marakaj — textes pour les stores et YouTube

Brouillon à relire. Ne citez que des fonctions déjà disponibles dans l'app, et visibles
par le compte de test des stores. Les lignes sur les événements valent une fois
l'Événementiel ouvert à tous (Console), ou visible du compte de test. Les lignes entre
crochets [ ] dépendent d'un interrupteur : la billetterie (`events_tickets`) à citer
seulement une fois ouverte. Mis à jour pour 182 : l'Événementiel gratuit, Pro pour les
modèles Premium, l'album des invités et les billets au-delà des gratuits.

**Slogan** : Au Service du Peuple

## Google Play

**Nom (30 car. max)**
Marakaj – Boutiques proches

**Description courte (80 car. max)**
Boutiques près de chez vous, caisse et stock, cartes d'invitation animées.

**Description complète**
Marakaj rapproche les boutiques de leurs clients, et les organisateurs de leurs invités.

Pour les clients :
• Découvrez les boutiques près de chez vous et leurs vitrines en ligne
• Consultez les articles et les prix avant de vous déplacer
• Commandez à emporter ou en livraison

Pour les commerçants :
• Une caisse simple sur votre téléphone
• La gestion de votre stock
• Une vitrine en ligne, mise à jour avec votre stock

Pour les organisateurs d'événements (mariage, dot, baptême, anniversaire, gala, concert…) :
• Des cartes d'invitation en ligne, classiques ou animées, envoyées par un simple lien — avec un bel aperçu dans WhatsApp
• Studio : composez votre carte au doigt, bloc par bloc — textes, couleurs, polices, photos, fonds animés, pétales qui tombent
• Vos invités confirment leur présence d'un geste, et vous suivez les réponses au fur et à mesure ; la veille, un rappel sur WhatsApp
• L'album de la fête : chaque invité ajoute ses photos depuis l'app, tout le monde les voit et les télécharge
• La carte en PDF, à imprimer
[Seulement une fois `events_tickets` ouvert :]
• La billetterie : vos invités réservent sur la carte et paient directement chez vous (Orange Money, Moov…) ; billets avec QR code, contrôle à l'entrée même sans réseau

Gratuit pour l'essentiel. Marakaj Pro (abonnement mensuel ou annuel) ajoute :
• Pour les commerces : la livraison, le paiement en ligne, l'équipe, la comptabilité et plus
• Pour les événements : les modèles et décors animés Premium, et l'album photo des invités[, et la billetterie sans limite — seulement si la billetterie est ouverte]

Marakaj est conçue pour l'Afrique de l'Ouest : en français, sur téléphone, pour le commerce de quartier comme pour les grands jours.

**Catégorie** Shopping (ou Entreprise)

**Nouveautés (500 car. max)** — envoyées pour 1.0.2 (sur Play, entre `<fr-FR>` et `</fr-FR>`)
• Confirmez votre présence d'un geste, puis ajoutez vos photos dans « Mes invitations » (5 par invité), du jour de l'événement à 7 jours après
• Studio : polices visibles avant de choisir, pétales sur toute la carte, chaque section animée
• Un bel aperçu de votre carte sur WhatsApp
• L'heure de vos événements toujours à l'heure du lieu
• L'Événementiel gratuit ; Marakaj Pro pour les modèles Premium et l'album des invités

## App Store

**Nom (30 car. max)** Marakaj
**Sous-titre (30 car. max)** Boutiques, caisse, invitations
**Mots-clés (100 car. max, sans accent pour tenir aussi en octets)**
boutique,commerce,caisse,stock,livraison,vitrine,invitation,mariage,carte,evenement,Burkina,FCFA
**Texte promotionnel (170 car. max)** Au Service du Peuple : les boutiques près de vous, et des cartes d'invitation animées que vous composez au doigt avec Studio.
**Description** : reprendre la description complète Google Play, mêmes lignes (Apple et Google doivent dire la même chose ; ce qui est écrit doit être visible par le compte de test).
**Nouveautés de la version** : reprendre les Nouveautés Google Play.
**Notes pour la revue (App Review Information › Notes)**
Compte de démonstration : celui de `store_review_account`. Il ouvre une boutique (Review Shop), une ferme (Farm Review), une association (Association Review) et un Événementiel (Event Review) avec une carte d'exemple publiée, « Awa & Paul » (https://marakaj.com/e/awa-paul-322c), et trois réponses d'invités. Dans l'app : Changer d'activité › Event Review › Cartes. Les cartes d'invitation s'ouvrent dans le navigateur (lien https://marakaj.com/e/…) : aucune connexion n'est demandée aux invités. Marakaj Pro s'achète dans l'app par l'abonnement de l'App Store.

## Avant d'envoyer aux stores (à cocher)

1. **Ce que la description promet, le compte de test le voit.** Fait le 13 novembre 2026 : le compte de test a un Événementiel, « Event Review » (ouvert à lui seul, `events_allowed`, l'Événementiel restant fermé au public), avec la carte « Awa & Paul » publiée et trois réponses. Ne pas le supprimer avant la fin de la revue.
2. **La billetterie** : ne la citer que si `events_tickets` est ouvert (Console › Événementiel l'indique).
3. **Marakaj Pro** : l'abonnement des stores (`store_billing_on`) est ouvert ; les prix des produits d'abonnement dans App Store Connect et la Play Console doivent correspondre à ceux de la Console › Pro.
4. **Captures d'écran** : refaire celles des cartes (nouvelle liste « Cartes », Studio, aperçu WhatsApp) — elles doivent montrer l'app actuelle.
5. **Version** : 1.0.2 (`app/pubspec.yaml`, `appVersion` dans main.dart) — fait le 14 novembre 2026 ; le numéro de build vient de Codemagic.
6. **iPhone** : Associated Domains (applinks:marakaj.com) dans le profil de l'identifiant bf.kaj.app, sinon les liens de billets n'ouvrent pas l'app (ce n'est pas bloquant pour la revue).
7. **Assistant d'écriture** : la clé `ANTHROPIC_API_KEY` doit être ajoutée dans Cloudflare (par vous) ; sans elle Studio répond « pas disponible » — retirer « assistant » des textes tant qu'elle manque.
8. **Notifications du compte de test** : pendant la revue, les testeurs se connectent et envoient des notifications test ; c'est normal.

## YouTube

**Nom de la chaîne** Marakaj
**Identifiant (handle)** @marakaj — vérifier la disponibilité, sinon @marakaj.app
**Description**
Marakaj, l'app des boutiques près de vous. Tutoriels pour les commerçants (caisse, stock, vitrine), nouveautés de l'app et histoires de commerçants d'Afrique de l'Ouest.

**Idées de premières vidéos**
1. Marakaj en 60 secondes
2. Créer sa boutique et sa vitrine
3. Encaisser une vente et suivre son stock
4. Commander dans une boutique près de chez vous

## Tailles des fichiers fournis

| Fichier | Où l'utiliser |
|---|---|
| app-store/app-icon-1024.png | App Store Connect › Icône |
| app-store/screenshot-template-1320x2868.png | Captures iPhone 6,9" (en faire au moins 3) |
| play-store/app-icon-512.png | Play Console › Icône |
| play-store/feature-graphic-1024x500.png | Play Console › Image de présentation |
| play-store/screenshot-template-1080x1920.png | Captures téléphone (au moins 2) |
| play-store/adaptive-icon/ | Icône adaptative Android (avant-plan + arrière-plan) |
| youtube/profile-picture-800.png | Photo de profil |
| youtube/banner-2560x1440.png | Bannière (texte dans la zone sûre 1546×423) |
| youtube/watermark-150.png | Filigrane de la vidéo |
| youtube/thumbnail-template-1280x720.png | Modèle de miniature |
| web/icons/, web/favicon.* | Remplacent les icônes de l'app web Flutter (mêmes noms) |
| logo/ | Logo maître (SVG + PNG transparent) |

## Logos (dossier de chaque couleur › logo/)

Le sceau porte toujours MMXXVI.

| Dossier | Contenu |
|---|---|
| clair/ | Pour fonds blancs ou clairs |
| sombre/ | Pour fonds noirs ou foncés |
| indigo/ | Pour fond bleu indigo |
| terracotta/ | Pour fond terre cuite |
| monochrome/blanc, noir, or | Une seule couleur : tampons, gravure, broderie, sur photos |

Dans chaque logo/ : seal (sceau seul, 256 à 2048 px), horizontal (sceau + marakaj), stacked (sceau au-dessus de marakaj).
-transparent.png = sans fond · -on-background.png = avec fond · .svg et .pdf = vectoriel pour l'impression et les grandes tailles.

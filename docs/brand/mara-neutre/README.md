# Mara — kit de marque, noir · blanc · brun · gris

Le sceau de lumière, dans une palette sans rouge ni bleu. Le sceau porte
toujours **MMXXVI** (2026 en chiffres romains, l'année de fondation) — sur
chaque version, à chaque taille.

Ces fichiers sont générés : `python3 ../build_mara_neutre.py` les refait
(voir l'en-tête du script pour les dépendances).

## Un dossier par fond

| Dossier | Usage |
|---|---|
| `blanc/` | Fonds blancs ou clairs |
| `noir/` | Fonds noirs |
| `brun/` | Fond brun |
| `gris/` | Fond gris foncé |
| `monochrome/blanc, noir, brun, gris` | Une seule couleur : tampons, gravure, broderie, sur photos |

## Dans chaque dossier de couleur

| Fichier | Où l'utiliser |
|---|---|
| `app-store/app-icon-1024.png` | App Store Connect › Icône |
| `app-store/screenshot-template-1320x2868.png` | Captures iPhone 6,9" (au moins 3) |
| `play-store/app-icon-512.png` | Play Console › Icône |
| `play-store/feature-graphic-1024x500.png` | Play Console › Image de présentation |
| `play-store/screenshot-template-1080x1920.png` | Captures téléphone (au moins 2) |
| `play-store/adaptive-icon/` | Icône adaptative Android (avant-plan + arrière-plan) |
| `youtube/profile-picture-800.png` | Photo de profil |
| `youtube/banner-2560x1440.png` | Bannière (texte dans la zone sûre 1546×423) |
| `youtube/watermark-150.png` | Filigrane des vidéos |
| `youtube/thumbnail-template-1280x720.png` | Modèle de miniature |
| `web/icons/`, `web/favicon.*` | Mêmes noms que les icônes de `app/web/` |
| `logo/seal`, `logo/horizontal`, `logo/stacked` | Sceau seul, sceau + mara, sceau au-dessus de mara |

`-transparent.png` = sans fond · `-on-background.png` = avec fond ·
`.svg` / `.pdf` = vectoriel, pour l'impression et les grandes tailles.

Ce kit n'est pas encore branché dans l'app : `app/assets/brand/`,
`app/web/icons/` et `app/web/manifest.json` gardent les fichiers actuels.

## Couleurs

| Nom | Hex |
|---|---|
| Noir | `#0E0D0C` |
| Blanc cassé | `#F4F2EE` |
| Brun foncé | `#4A3122` |
| Brun | `#8B5A3C` |
| Caramel | `#C49A6C` |
| Gris | `#A3A09B` |
| Gris foncé | `#3B3A38` |

Polices : Unbounded (mot « mara »), Cinzel (MMXXVI), Space Grotesk (textes).

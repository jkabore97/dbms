# Documents de présentation

Two French documents, generated rather than hand-written so the figures can be
re-measured and the files regenerated.

| Fichier | Rôle | Longueur |
|---|---|---|
| `Kaj_Comprendre_le_projet.docx` | Version courte — faire comprendre le projet | ~3 pages |
| `Kaj_Dossier_Presentation.docx` | Dossier complet — architecture, modèle, feuille de route, risques | ~9 pages |

Send the short one first. The dossier follows once the project is understood.

## Regenerating

    npm install docx mammoth
    node build_intro.js      # version courte
    node build_dossier.js    # dossier complet

`kit.js` holds the shared formatting helpers — colours, headings, tables,
callouts — so the two documents stay visually consistent.

## Register

The short document uses **tu** (father to son). The dossier uses **vous**, as
it is written for any potential partner and may be shown to third parties.
Align them if you prefer one register throughout.

## Before each send

Section 4 of the dossier quotes figures from the repository. Re-measure them:

    grep -rh "^create policy" database/migrations/*.sql database/schema.sql | wc -l
    grep -rh "PASS:" database/tests/*.sql | wc -l
    cd app && flutter test | tail -1

LibreOffice is unavailable in this sandbox, so both files were verified by
reading them back with `mammoth` rather than by rendering to PDF. Open them in
Word once before sending.

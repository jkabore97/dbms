# Plans

Three planning documents, published as artifacts. Each is a self-contained
HTML page: the fonts are inlined as data URIs because the artifact host
blocks font CDNs, and a linked webfont fails silently to whatever the reader
happens to have installed.

| Source | Built | Document |
|---|---|---|
| `src_app.html` | `app_plan.html` | Kaj Build Sequence — product roadmap |
| `src_hr.html`  | `hr_plan.html`  | Staffing Kaj — hiring and the agent network |
| `src_biz.html` | `biz_plan.html` | Kaj Burkina Launch — company and go-to-market |

## Editing

Edit the `src_*.html` file, never the built one, then rebuild:

    python3 plans/build.py plans/src_app.html plans/app_plan.html

`build.py` substitutes two markers: `/*@FONTS@*/` with the `@font-face`
rules, and `/*@SHARED@*/` with `_shared.css`. Colour tokens live in each
source file — the three documents deliberately share a skeleton and differ
only in palette, taken from the app's own `kaj_theme.dart`.

Republishing the same built file path from the conversation that created it
updates the existing artifact and keeps its URL.

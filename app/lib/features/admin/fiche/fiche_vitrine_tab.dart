import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/models.dart';
import '../../../core/console/fiche_repository.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/nav/router.dart';
import '../../../core/storefront/storefront_repository.dart';
import '../../../core/theme/kaj_card.dart';
import '../../../core/theme/mara_mark.dart';
import '../../storefront/storefront_screen.dart';
import '../org_settings_screen.dart';
import 'fiche_widgets.dart';
import 'look_only_view.dart';

/// Vitrine: where the business's window stands, and the owner's own editor
/// opened as Mara. The editor is the very screen the owner uses
/// (OrgSettingsScreen, at its « Vitrine » part) — its functions already
/// let a platform admin in (is_org_admin) — and every change Mara makes
/// through it is written in the journal with its undo, the owner told
/// « Mara a modifié votre vitrine » (106's trigger on the vitrine's
/// columns; one line per editing session).
class FicheVitrineTab extends StatelessWidget {
  const FicheVitrineTab({
    super.key,
    required this.overview,
    required this.org,
    required this.onChanged,
  });

  final OrgOverview overview;
  final OrgSummary org;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MaraAsBanner(
          title: context.tr('Vous modifiez la vitrine de {name} en tant que Mara',
              {'name': o.name}),
          line: context.tr('C\'est l\'éditeur du propriétaire. Il est prévenu, et chaque changement va au journal, avec « Annuler ».'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FicheFigure(
              value: o.vitrineOpen ? context.tr('Ouverte') : context.tr('Fermée'),
              label: context.tr('Vitrine'),
              colour: o.vitrineOpen ? maraGreen : maraGrey,
            ),
            FicheFigure(
              value: '${o.published}',
              label: o.isAssociation ? context.tr('en ligne') : context.tr('en vente'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        KajCard(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.link),
            title: SelectableText(publicShopUrl(o.slug)),
            subtitle: Text(context.tr('Le lien que le propriétaire partage')),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            key: const Key('fiche-vitrine-edit'),
            style: FilledButton.styleFrom(
                backgroundColor: maraDeep, foregroundColor: maraPaper),
            onPressed: () async {
              await MaraVitrineEditor.open(context, org: org, slug: o.slug);
              onChanged();
            },
            icon: const Icon(Icons.edit_outlined, color: maraCaramel),
            label: Text(context.tr('Ouvrir l\'éditeur de la vitrine'),
                style: const TextStyle(fontSize: 17)),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('fiche-vitrine-public'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => context.push(Routes.storefront(o.slug)),
          icon: const Icon(Icons.open_in_new),
          label: Text(context.tr('Voir la vitrine publique')),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('Les articles et les services, leurs photos et leurs prix, se changent dans l\'activité elle-même.'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
    return ListView(
      key: const Key('fiche-vitrine'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        FicheWidth(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: status),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 400,
                      height: 640,
                      child: LiveVitrine(slug: o.slug),
                    ),
                  ],
                )
              : status,
        ),
      ],
    );
  }
}

/// The owner's editor of the vitrine, opened as Mara: the banner on top,
/// the editor itself, and — on a computer — the street's view of the
/// vitrine beside it, drawn again after each save.
class MaraVitrineEditor extends StatefulWidget {
  const MaraVitrineEditor({super.key, required this.org, required this.slug});

  final OrgSummary org;
  final String slug;

  static Future<void> open(BuildContext context,
          {required OrgSummary org, required String slug}) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
        builder: (_) => MaraVitrineEditor(org: org, slug: slug),
      ));

  @override
  State<MaraVitrineEditor> createState() => _MaraVitrineEditorState();
}

class _MaraVitrineEditorState extends State<MaraVitrineEditor> {
  int _saved = 0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final editor = OrgSettingsScreen(
      admin: scope.admin,
      orgId: widget.org.id,
      plan: widget.org.plan,
      suspended: widget.org.suspended,
      retail: scope.retail,
      capture: scope.capture,
      initialPart: 'vitrine',
      onSaved: () {
        setState(() => _saved++);
        unawaited(scope.session.refresh(force: true));
      },
    );
    return Scaffold(
      key: const Key('mara-vitrine-editor'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: maraDeep,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, color: maraCaramel),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.tr('Vous modifiez la vitrine de {name} en tant que Mara',
                            {'name': widget.org.name}),
                        style: const TextStyle(
                            color: maraCaramel, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: maraPaper),
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(context.tr('Terminé')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: editor),
                        const VerticalDivider(width: 1),
                        SizedBox(
                          width: 420,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: LiveVitrine(
                              key: ValueKey('live-$_saved'),
                              slug: widget.slug,
                            ),
                          ),
                        ),
                      ],
                    )
                  : editor,
            ),
          ),
        ],
      ),
    );
  }
}

/// The vitrine as the street sees it, live, on a phone's width — the very
/// page a shopper opens, which shows what is saved. To look at only: no
/// basket, no order from here.
class LiveVitrine extends StatelessWidget {
  const LiveVitrine({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('Aperçu en direct'),
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            key: const Key('live-vitrine'),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: maraGrey.withValues(alpha: 0.6), width: 5),
            ),
            child: scope == null
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, box) => LookOnlyView(
                      width: box.maxWidth,
                      child: StorefrontScreen(
                        slug: slug,
                        storefront: StorefrontRepository(scope.auth.client),
                        capture: scope.capture,
                        session: scope.session,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/kaj_card.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// « Vitrines d'exemple » (094): the platform's own shops on the street —
/// Rowan Bike Shop, Tony Pizza and the others — that show a shopper what a
/// full vitrine looks like. Never on the map, « Pas à proximité », no
/// orders. From here the platform admin puts one on or off the street,
/// opens it as a shopper sees it, and « Gérer » takes the keys: the
/// ordinary business screens then edit its articles, photos, prices and
/// dressing.
class ShowcaseScreen extends StatefulWidget {
  const ShowcaseScreen({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ShowcaseScreenState extends State<ShowcaseScreen> {
  List<Showcase> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.admin.showcases();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _visible(Showcase s, bool on) async {
    setState(() => _busy = s.orgId);
    try {
      await widget.admin.setShowcaseVisible(s.orgId, on);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Takes the keys if needed, then opens the business like any other.
  Future<void> _manage(Showcase s) async {
    setState(() => _busy = s.orgId);
    final scope = AppScope.maybeOf(context);
    try {
      if (!s.managing) {
        await widget.admin.joinShowcase(s.orgId);
        await scope?.session.refresh(force: true);
      }
      if (!mounted) return;
      context.go(Routes.org(s.orgId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _seed() async {
    setState(() => _busy = 'seed');
    try {
      final made = await widget.admin.seedShowcases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            made == 0
                ? context.tr('Les sept vitrines existent déjà.')
                : context.tr('{n} vitrine(s) recréée(s).', {'n': made}),
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Vitrines d\'exemple'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: Text(context.tr('Réessayer')),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  context.tr(
                    'Des boutiques de la plateforme, pour montrer à quoi ressemble une vitrine pleine. Elles ne sont pas sur la carte, affichent « Pas à proximité » et ne prennent aucune commande.',
                  ),
                  style: muted,
                ),
                const SizedBox(height: 14),
                for (final s in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: KajCard(
                      key: Key('showcase-${s.slug}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.name,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                Switch(
                                  key: Key('showcase-visible-${s.slug}'),
                                  value: s.visible,
                                  onChanged: _busy != null
                                      ? null
                                      : (on) => _visible(s, on),
                                ),
                              ],
                            ),
                            Text(
                              context.tr(
                                '{items} articles · {photos} avec photo · {state}',
                                {
                                  'items': s.items,
                                  'photos': s.photos,
                                  'state': s.visible
                                      ? context.tr('sur la rue')
                                      : context.tr('cachée'),
                                },
                              ),
                              style: muted,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  key: Key('showcase-manage-${s.slug}'),
                                  onPressed: _busy != null
                                      ? null
                                      : () => _manage(s),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: Text(context.tr('Gérer')),
                                ),
                                TextButton.icon(
                                  onPressed: () =>
                                      context.push(Routes.storefront(s.slug)),
                                  icon: const Icon(
                                    Icons.storefront_outlined,
                                    size: 18,
                                  ),
                                  label: Text(context.tr('Voir la vitrine')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_rows.length < 7) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    key: const Key('showcase-seed'),
                    onPressed: _busy != null ? null : _seed,
                    icon: const Icon(Icons.add_business_outlined),
                    label: Text(context.tr('Recréer les vitrines manquantes')),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    '« Gérer » vous en donne les clés : articles, photos, prix et « Habiller ma vitrine » s\'y modifient comme dans toute entreprise.',
                  ),
                  style: muted,
                ),
              ],
            ),
    );
  }
}

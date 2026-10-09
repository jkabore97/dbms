import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/notify/push_client.dart';
import '../../core/notify/push_setup.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../storefront/shop_style.dart';

/// « Mes vitrines favorites » (113): the vitrines followed with ♥, each
/// opening its window, each with its own news switch, and the switch for
/// all of them. The news is one ring per vitrine per day at most (the
/// server coalesces it); with the app closed it rings where the browser
/// agreed to carry it.
class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key, required this.shopper});

  final ShopperRepository shopper;

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  List<FollowedVitrine>? _follows;
  bool _news = true;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.shopper.isConfigured) {
      setState(() => _error = context.tr('Votre compte a besoin d\'une connexion.'));
      return;
    }
    try {
      final results = await Future.wait([widget.shopper.follows(), widget.shopper.profile()]);
      if (!mounted) return;
      setState(() {
        _follows = results[0] as List<FollowedVitrine>;
        _news = (results[1] as ShopperProfile).news;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('Vos vitrines n\'ont pas pu être chargées. Vérifiez le réseau.'));
      }
    }
  }

  void _say(String text, {SnackBarAction? action}) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));

  Future<void> _act(String key, Future<void> Function() act) async {
    setState(() => _busy = key);
    try {
      await act();
      await _load();
    } catch (e) {
      _say(describeError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _unfollow(FollowedVitrine f) async {
    final again = context.tr('Suivre à nouveau');
    final said = context.tr('Vous ne suivez plus {name}.', {'name': f.name});
    await _act(f.orgId, () => widget.shopper.unfollow(f.orgId));
    if (!mounted) return;
    _say(said,
        action: f.open
            ? SnackBarAction(
                label: again,
                onPressed: () => _act(f.orgId, () async {
                  final id = await widget.shopper.follow(f.slug);
                  if (!f.news) await widget.shopper.setFollowNews(id, false);
                }),
              )
            : null);
  }

  /// The browser carries the ring with the app closed (060), once asked
  /// from a tap — as the shop's « Activer les alertes ».
  Future<void> _enablePush() async {
    final notify = AppScope.maybeOf(context)?.notify;
    final saved = notify != null && await PushSetup.enable(notify);
    if (!mounted) return;
    _say(saved
        ? context.tr('Activé : les nouveautés sonneront même l\'application fermée.')
        : context.tr('Le navigateur a refusé les alertes. Elles s\'activent dans ses paramètres de notifications.'));
  }

  @override
  Widget build(BuildContext context) {
    final follows = _follows;
    return ShopPage(
      title: context.tr('Mes vitrines favorites'),
      leading: IconButton(
        tooltip: context.tr('Retour'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go(Routes.shopperProfile),
      ),
      body: follows == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : ShopNotice(
                  text: _error!,
                  action: OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                ))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                ShopWidth(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        if (follows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Column(
                              children: [
                                const Icon(Icons.favorite_border, size: 40, color: ShopStyle.mist),
                                const SizedBox(height: 12),
                                Text(
                                  context.tr('Touchez ♥ sur une vitrine pour la suivre : ses nouveautés et ses offres vous seront dites, une fois par jour au plus.'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, color: ShopStyle.ink),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: () => context.go(Routes.directory),
                                  child: Text(context.tr('Voir les vitrines')),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          // The switch for all of them.
                          Material(
                            color: ShopStyle.stone,
                            borderRadius: BorderRadius.circular(14),
                            clipBehavior: Clip.antiAlias,
                            child: SwitchListTile(
                              key: const Key('news-all'),
                              secondary: const Icon(Icons.campaign_outlined, color: ShopStyle.ink),
                              title: Text(context.tr('Nouveautés et offres'),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(_news
                                  ? context.tr('Une notification par vitrine et par jour au plus')
                                  : context.tr('Aucune vitrine ne vous écrit')),
                              value: _news,
                              onChanged: _busy != null
                                  ? null
                                  : (on) => _act('all', () => widget.shopper.setSettings(news: on)),
                            ),
                          ),
                          if (_news && PushClient.available) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                key: const Key('news-push'),
                                onPressed: _enablePush,
                                icon: const Icon(Icons.notifications_active_outlined),
                                label: Text(context.tr('Être prévenu même l\'application fermée')),
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          ShopSectionLabel(context.tr('Suivies'), note: '${follows.length}'),
                          const SizedBox(height: 10),
                          for (final f in follows)
                            _FollowCard(
                              follow: f,
                              allNews: _news,
                              busy: _busy == f.orgId,
                              onOpen: () => context.go(Routes.storefront(f.slug)),
                              onNews: (on) => _act(f.orgId, () => widget.shopper.setFollowNews(f.orgId, on)),
                              onUnfollow: () => _unfollow(f),
                            ),
                        ],
                        const ShopFooter(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FollowCard extends StatelessWidget {
  const _FollowCard({
    required this.follow,
    required this.allNews,
    required this.busy,
    required this.onOpen,
    required this.onNews,
    required this.onUnfollow,
  });

  final FollowedVitrine follow;
  final bool allNews;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<bool> onNews;
  final VoidCallback onUnfollow;

  @override
  Widget build(BuildContext context) {
    final f = follow;
    final kind = switch (f.profile) {
      'farm' => context.tr('Ferme'),
      'association' || 'church' => context.tr('Association'),
      _ => context.tr('Boutique'),
    };
    final icon = switch (f.profile) {
      'farm' => Icons.agriculture_outlined,
      'association' || 'church' => Icons.groups_outlined,
      _ => Icons.storefront_outlined,
    };
    return Container(
      key: Key('follow-${f.slug}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: ShopStyle.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          ListTile(
            minTileHeight: 64,
            onTap: f.open ? onOpen : null,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: ShopStyle.stone, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: ShopStyle.ink),
            ),
            title: Text(f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ShopStyle.ink)),
            subtitle: Text(
              f.open ? kind : '$kind · ${context.tr('fermée pour le moment')}',
              style: const TextStyle(fontSize: 13.5, color: ShopStyle.mist),
            ),
            trailing: IconButton(
              key: Key('unfollow-${f.slug}'),
              tooltip: context.tr('Ne plus suivre'),
              onPressed: busy ? null : onUnfollow,
              icon: const Icon(Icons.favorite, color: maraBrown),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            key: Key('news-${f.slug}'),
            dense: true,
            title: Text(context.tr('Me dire ses nouveautés'), style: const TextStyle(fontSize: 14.5)),
            value: f.news && allNews,
            onChanged: busy || !allNews ? null : onNews,
          ),
        ],
      ),
    );
  }
}

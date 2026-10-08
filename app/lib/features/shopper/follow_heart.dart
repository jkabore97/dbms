import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../storefront/shop_style.dart';

/// Which vitrines the signed-in shopper follows (113), for the hearts of
/// one page — the street's cards or a vitrine's band. Unknown (no server,
/// nobody signed in, no answer) draws no heart at all: a stranger's street
/// is the street as it was.
class Follows extends ChangeNotifier {
  Follows(this.shopper);

  final ShopperRepository? shopper;

  Set<String>? _slugs;
  final Set<String> _busy = {};

  /// Known: the hearts can be drawn.
  bool get ready => _slugs != null;

  bool isFollowed(String slug) => _slugs?.contains(slug) ?? false;
  bool isBusy(String slug) => _busy.contains(slug);

  /// Asked once per page, and again when somebody signs in or out.
  Future<void> load() async {
    final s = shopper;
    if (s == null || !s.isConfigured) {
      if (_slugs != null) {
        _slugs = null;
        notifyListeners();
      }
      return;
    }
    try {
      _slugs = await s.followedSlugs();
    } catch (_) {
      _slugs = null;
    }
    notifyListeners();
  }

  /// ♥ tapped: followed, or let go. Answers what to say.
  Future<String> toggle(BuildContext context, String slug) async {
    final s = shopper;
    final slugs = _slugs;
    if (s == null || slugs == null || _busy.contains(slug)) return '';
    final following = slugs.contains(slug);
    final saidOn = context.tr('Vitrine suivie : ses nouveautés et ses offres vous seront dites.');
    final saidOff = context.tr('Vous ne suivez plus cette vitrine.');
    _busy.add(slug);
    notifyListeners();
    try {
      if (following) {
        await s.unfollowSlug(slug);
        slugs.remove(slug);
      } else {
        await s.follow(slug);
        slugs.add(slug);
      }
      return following ? saidOff : saidOn;
    } catch (e) {
      return describeError(e);
    } finally {
      _busy.remove(slug);
      notifyListeners();
    }
  }
}

/// ♥ on a vitrine (its band) or on its card in the street.
class FollowHeart extends StatelessWidget {
  const FollowHeart({
    super.key,
    required this.follows,
    required this.slug,
    this.onCard = false,
  });

  final Follows follows;
  final String slug;

  /// On a card's photograph: a white disc under the heart, so it reads on
  /// any picture.
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: follows,
      builder: (context, _) {
        if (!follows.ready) return const SizedBox.shrink();
        final on = follows.isFollowed(slug);
        final busy = follows.isBusy(slug);
        final heart = Icon(
          on ? Icons.favorite : Icons.favorite_border,
          color: on ? maraBrown : ShopStyle.ink,
          size: onCard ? 20 : 26,
        );
        Future<void> tap() async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final said = await follows.toggle(context, slug);
          if (said.isNotEmpty) {
            messenger
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(said)));
          }
        }

        return Semantics(
          button: true,
          toggled: on,
          label: on ? context.tr('Ne plus suivre') : context.tr('Suivre cette vitrine'),
          excludeSemantics: true,
          child: onCard
              ? Material(
                  key: Key('heart-$slug'),
                  color: ShopStyle.paper,
                  shape: const CircleBorder(),
                  elevation: 1,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: busy ? null : tap,
                    child: Padding(padding: const EdgeInsets.all(8), child: heart),
                  ),
                )
              : IconButton(
                  key: Key('heart-$slug'),
                  tooltip: on ? context.tr('Ne plus suivre') : context.tr('Suivre cette vitrine'),
                  onPressed: busy ? null : tap,
                  icon: heart,
                ),
        );
      },
    );
  }
}

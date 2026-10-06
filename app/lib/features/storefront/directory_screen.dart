import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import '../../core/nav/session.dart';
import '../../core/storefront/storefront_repository.dart';
import 'directory_map.dart';
import 'shop_skeleton.dart';
import 'shop_style.dart';

/// The front door: every open vitrine, the articles à la une, a map with the
/// shops on it, and one way in for whoever is holding the phone.
///
/// A stranger lands here first (the router sends a signed-out visit to this
/// page, not to a gate) and sees the shops, the paid spots, and "Se
/// connecter". A signed-in shopper with no business of their own lands here
/// too, with a small account menu: their profile, the way to become a
/// seller, the way out. A shop owner passing through finds their businesses
/// behind the same icon. Nothing on the page needs an account to look.
///
/// Ouagadougou has no street addresses a stranger can follow, which is why
/// the pin matters: "près de moi" asks the phone where it is once, the
/// directory comes back nearest first, and every pin on the map carries the
/// shop's name and hands over an itinerary to the maps app the phone
/// already has. The map is OpenStreetMap through flutter_map — no key, no
/// bill; the directions are Google's, by link, for the same reason.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({
    super.key,
    required this.storefront,
    required this.capture,
    required this.session,
  });

  final StorefrontRepository storefront;

  /// For the featured photos, served publicly by the uploads Worker per key.
  final CaptureRepository capture;

  /// Who is holding the phone, if anyone: decides what the account corner
  /// offers. Listened to, so signing in or out repaints it.
  final SessionController session;

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  List<DirectoryEntry> _entries = const [];

  /// Three articles per shop for the cards (070). Loaded after the list and
  /// never in its way: a card without previews still names the shop.
  Map<String, List<ShopPreview>> _previews = const {};
  List<FeaturedItem> _featured = const [];

  /// The shops paying for the top of the list right now (071).
  Set<String> _spotlights = const {};
  bool _loading = true;
  bool _locating = false;
  String? _error;

  /// Where the shopper is, once they said so. Null until "près de moi".
  LatLng? _here;

  /// Ouagadougou's centre: where the map opens with nothing better to show.
  static const _ouaga = LatLng(12.3714, -1.5197);

  // The search across every window (059). `_query` is the trimmed text the
  // hits answer; while it is two letters or more the results replace the
  // street. The stamp drops an answer that arrives after a newer question.
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  int _searchStamp = 0;
  String _query = '';
  List<ProductHit> _hits = const [];
  bool _hunting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _query = q;
        _hits = const [];
        _hunting = false;
      });
      return;
    }
    // A breath between keystrokes, so the network sees words, not letters.
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  void _clearSearch() {
    _search.clear();
    _onSearchChanged('');
  }

  Future<void> _runSearch(String q) async {
    final stamp = ++_searchStamp;
    setState(() {
      _query = q;
      _hunting = true;
    });
    try {
      final hits = await widget.storefront.searchProducts(
        q,
        lat: _here?.latitude,
        lng: _here?.longitude,
      );
      if (!mounted || stamp != _searchStamp) return;
      setState(() {
        _hits = hits;
        _hunting = false;
      });
    } catch (_) {
      if (!mounted || stamp != _searchStamp) return;
      setState(() {
        _hits = const [];
        _hunting = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.storefront.isConfigured) {
      setState(() {
        _error = "L'annuaire a besoin d'une connexion.";
        _loading = false;
      });
      return;
    }
    try {
      final here = _here;
      // The paid spots are a strip, not the page: if they fail to load the
      // shops still show, and the strip is simply absent.
      final results = await Future.wait([
        widget.storefront.directory(lat: here?.latitude, lng: here?.longitude),
        widget.storefront
            .featured()
            .catchError((_) => const <FeaturedItem>[]),
        widget.storefront.spotlights(),
      ]);
      if (!mounted) return;
      final spotlights = results[2] as Set<String>;
      final entries = results[0] as List<DirectoryEntry>;
      setState(() {
        // A paid shop leads the list, the rest keep the server's order
        // (nearest first, or by name).
        _entries = [
          ...entries.where((e) => spotlights.contains(e.slug)),
          ...entries.where((e) => !spotlights.contains(e.slug)),
        ];
        _spotlights = spotlights;
        _featured = results[1] as List<FeaturedItem>;
        _loading = false;
      });
      // The strip is what a spot buys: count it as seen, in one call.
      unawaited(widget.storefront
          .recordSeen([for (final f in _featured) f.id]));
      unawaited(_loadPreviews());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "L'annuaire n'a pas pu être chargé. Vérifiez le réseau.";
        _loading = false;
      });
    }
  }

  Future<void> _loadPreviews() async {
    try {
      final previews = await widget.storefront
          .previews([for (final e in _entries) e.slug]);
      if (mounted) setState(() => _previews = previews);
    } catch (_) {
      // The cards keep their names; the goods simply do not show.
    }
  }

  /// Ask the phone where it is, once, then reload nearest first. Every way
  /// this can fail — refused, switched off, no fix — is said in words; the
  /// tiles are still there in name order, so nothing is lost by refusing.
  Future<void> _nearMe() async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(const SnackBar(
          content: Text("Sans votre position, l'annuaire reste par nom."),
        ));
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      _here = LatLng(position.latitude, position.longitude);
      await _load();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Position introuvable. Vérifiez que le GPS est activé.'),
      ));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _open(DirectoryEntry entry) =>
      context.go(Routes.storefront(entry.slug));

  Future<void> _directions(double lat, double lng) async {
    final uri = Uri.tryParse(directionsUrl(lat, lng));
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// A pin was tapped: the shop's name, where it is, how far, and the two
  /// things to do about it — look in the window, or go there.
  /// The map, full screen (package 3): the list stays the page, the map is
  /// a place you go and come back from.
  Future<void> _openMap() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DirectoryMapPage(
        entries: _entries,
        previews: _previews,
        here: _here,
        fallback: _ouaga,
        onOpen: (e) {
          Navigator.of(context).pop();
          _open(e);
        },
        onDirections: (e) => _directions(e.lat!, e.lng!),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ShopPage(
      title: 'Mara — les vitrines',
      brand: const MaraWordmark(key: Key('mara-header'), height: 34),
      announcements: ShopPage.street,
      trailing: _AccountCorner(session: widget.session),
      body: _loading
          ? const ShopSkeleton.street()
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : _Street(
                  entries: _entries,
                  previews: _previews,
                  featured: _featured,
                  spotlights: _spotlights,
                  capture: widget.capture,
                  here: _here,
                  fallback: _ouaga,
                  locating: _locating,
                  onNearMe: _nearMe,
                  onToggleMap: _openMap,
                  onOpen: _open,
                  search: _search,
                  query: _query,
                  hits: _hits,
                  hunting: _hunting,
                  onSearchChanged: _onSearchChanged,
                  onClearSearch: _clearSearch,
                ),
    );
  }
}

/// The account corner of the header: what it offers depends on who is here.
///
/// A stranger gets "Se connecter". Somebody locked out gets the way back in.
/// A shopper with no business gets their profile, the way to become a seller
/// (or to join a business with a code), and the way out. A member of a
/// business gets their businesses, their profile, and the way out.
class _AccountCorner extends StatelessWidget {
  const _AccountCorner({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        switch (session.phase) {
          case SessionPhase.booting:
          case SessionPhase.resolving:
            return const SizedBox.shrink();
          case SessionPhase.signedOut:
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => context.go(Routes.signIn),
                child: const Text('Se connecter'),
              ),
            );
          case SessionPhase.locked:
          case SessionPhase.choosingPin:
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => context.go(Routes.pin),
                child: const Text('Ouvrir'),
              ),
            );
          case SessionPhase.twoStep:
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => context.go(Routes.twoStep),
                child: const Text('Ouvrir'),
              ),
            );
          case SessionPhase.noOrg:
          case SessionPhase.picking:
          case SessionPhase.ready:
            // The three doors the owner asked for, in a row: the boutique,
            // the livraison, the person. A member's boutique button opens
            // their business (or the picker when several and none is
            // remembered); a shopper's opens the way to have one.
            final member = session.phase != SessionPhase.noOrg;
            final open = session.lastOrgId;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: member ? 'Ma boutique' : 'Ouvrir ma boutique',
                  icon: Icon(member
                      ? Icons.store_outlined
                      : Icons.add_business_outlined),
                  // `replace`, not `go`: entering the business world takes
                  // the street's place in history, so back from the picker,
                  // the console or a store never falls out onto the public
                  // page — the owner found that jarring, and it was.
                  onPressed: () => context.replace(member
                      ? (open != null ? Routes.org(open) : Routes.picker)
                      : Routes.join),
                ),
                IconButton(
                  tooltip: 'Espace livreur',
                  icon: const Icon(Icons.sports_motorsports_outlined),
                  onPressed: () => context.go(Routes.courier),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mon compte',
                  icon: const Icon(Icons.person_outline),
                  onSelected: (choice) async {
                    switch (choice) {
                      case 'orders':
                        context.go(Routes.myOrders);
                      case 'profile':
                        context.go(Routes.myProfile);
                      case 'out':
                        await session.signOut();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'orders',
                      child: ListTile(
                        leading: Icon(Icons.receipt_long_outlined),
                        title: Text('Mes commandes'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'profile',
                      child: ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text('Mon profil'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'out',
                      child: ListTile(
                        leading: Icon(Icons.logout),
                        title: Text('Se déconnecter'),
                      ),
                    ),
                  ],
                ),
              ],
            );
        }
      },
    );
  }
}

class _Street extends StatelessWidget {
  const _Street({
    required this.entries,
    required this.previews,
    required this.featured,
    this.spotlights = const {},
    required this.capture,
    required this.here,
    required this.fallback,
    required this.locating,
    required this.onNearMe,
    required this.onToggleMap,
    required this.onOpen,
    required this.search,
    required this.query,
    required this.hits,
    required this.hunting,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  final List<DirectoryEntry> entries;
  final Map<String, List<ShopPreview>> previews;
  final List<FeaturedItem> featured;
  final Set<String> spotlights;
  final CaptureRepository capture;
  final LatLng? here;
  final LatLng fallback;
  final bool locating;
  final VoidCallback onNearMe;
  final VoidCallback onToggleMap;
  final void Function(DirectoryEntry) onOpen;

  final TextEditingController search;
  final String query;
  final List<ProductHit> hits;
  final bool hunting;
  final void Function(String) onSearchChanged;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 560;
    final columns = ShopStyle.columnsFor(width);
    final located = here != null;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // The hero settles in as the page opens.
        Reveal(
          child: ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            // Compact (package 3): the audit measured this band at 480 px
            // on a phone — with the map open, the shops started below the
            // fold. One line of title, one of explanation, then the tools.
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: wide ? 36 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mara's slogan, then what the street is.
                Text(
                  'Au Service du Peuple',
                  key: const Key('street-slogan'),
                  style: TextStyle(
                    fontSize: wide ? 32 : 24,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: ShopStyle.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Les boutiques près de vous : articles, prix et numéro, '
                  'tenus par chaque boutique.',
                  style: TextStyle(fontSize: 14, color: ShopStyle.mist),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: locating ? null : onNearMe,
                      icon: locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: ShopStyle.paper),
                            )
                          : Icon(located ? Icons.near_me : Icons.my_location,
                              size: 18),
                      label: Text(located ? 'Actualiser' : 'Près de moi'),
                    ),
                    OutlinedButton.icon(
                      onPressed: entries.isEmpty ? null : onToggleMap,
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Voir la carte'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // The search across every window: an article by its name,
                // wherever it is on the street.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: TextField(
                    controller: search,
                    onChanged: onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Chercher un article — savon, riz, café…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: onClearSearch,
                            ),
                      filled: true,
                      fillColor: ShopStyle.paper,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: ShopStyle.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: ShopStyle.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(
                            color: ShopStyle.ink, width: 1.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
        // While a search is live the results are the page; the strip, the
        // map and the list wait behind the cross that clears it.
        if (query.length >= 2)
          ShopWidth(
            child: _SearchResults(
              query: query,
              hits: hits,
              hunting: hunting,
              located: here != null,
              capture: capture,
            ),
          )
        else
        ShopWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The paid spots, when there are any: a strip, not the page.
              if (featured.isNotEmpty) ...[
                const SizedBox(height: 32),
                const ShopSectionLabel('À la une', note: 'Sponsorisé'),
                const SizedBox(height: 14),
                SizedBox(
                  height: 244,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: featured.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => ScrollReveal(
                      delay: KajMotion.stagger(i),
                      child: Lift(
                        // The photograph leans in (ZoomOnHover); the tile holds still.
                        scale: 1.0,
                        child: _FeaturedTile(
                          item: featured[i],
                          capture: capture,
                          onTap: () => context
                              .go(Routes.storefront(featured[i].shopSlug)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              ShopSectionLabel(
                located ? 'Les plus proches' : 'Toutes les vitrines',
                note: entries.isEmpty
                    ? null
                    : '${entries.length} vitrine${entries.length > 1 ? 's' : ''}',
              ),
              const SizedBox(height: 18),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Aucune vitrine ouverte pour le moment.',
                      style: TextStyle(fontSize: 15, color: ShopStyle.mist)),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: wide ? 24 : 14,
                    mainAxisSpacing: wide ? 36 : 26,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => ScrollReveal(
                    delay: KajMotion.stagger(i),
                    child: Lift(
                      // The photograph leans in (ZoomOnHover); the tile holds still.
                      scale: 1.0,
                      child: _ShopTile(
                        entry: entries[i],
                        located: located,
                        previews: previews[entries[i].slug] ?? const [],
                        sponsored: spotlights.contains(entries[i].slug),
                        capture: capture,
                        onOpen: () => onOpen(entries[i]),
                      ),
                    ),
                  ),
                ),
              const ShopFooter(),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the search found: articles from every window, each naming its shop.
/// Empty is said in words, with the query echoed so the shopper sees what
/// the street actually heard.
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.hits,
    required this.hunting,
    required this.located,
    required this.capture,
  });

  final String query;
  final List<ProductHit> hits;
  final bool hunting;
  final bool located;
  final CaptureRepository capture;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 560;
    final columns = ShopStyle.columnsFor(width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        ShopSectionLabel(
          'Résultats',
          note: hunting
              ? null
              : '${hits.length} article${hits.length > 1 ? 's' : ''}',
        ),
        const SizedBox(height: 18),
        if (hunting)
          ShopSkeleton.grid(tiles: 3)
        else if (hits.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Aucun article ne répond à « $query ». Essayez un autre mot.',
              style: const TextStyle(fontSize: 15, color: ShopStyle.mist),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: wide ? 24 : 14,
              mainAxisSpacing: wide ? 36 : 26,
              childAspectRatio: wide ? 0.66 : 0.58,
            ),
            itemCount: hits.length,
            itemBuilder: (context, i) => ScrollReveal(
              delay: KajMotion.stagger(i),
              child: Lift(
                // The photograph leans in (ZoomOnHover); the tile holds still.
                scale: 1.0,
                child: _HitTile(
                  hit: hits[i],
                  located: located,
                  capture: capture,
                  onTap: () =>
                      context.go(Routes.storefront(hits[i].shopSlug)),
                ),
              ),
            ),
          ),
        const ShopFooter(),
      ],
    );
  }
}

/// One found article: the photograph, the name, the price, and — because the
/// answer spans the whole street — the shop it is in and how far that is.
class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.located,
    required this.capture,
    required this.onTap,
  });

  final ProductHit hit;
  final bool located;
  final CaptureRepository capture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(hit.currency);
    final distance = distanceLabel(hit.distanceKm);
    final shopLine = distance == null ? hit.shopName : '${hit.shopName} · $distance';
    // One button to a screen reader, read in the order a sighted shopper
    // reads it: the article, its price, whether there is any, the shop.
    return Semantics(
      button: true,
      label: [
        hit.name,
        money.format(hit.price),
        if (!hit.inStock) 'épuisé',
        'chez ${hit.shopName}',
        if (distance != null) 'à $distance',
      ].join(', '),
      hint: 'Ouvrir la vitrine',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ColoredBox(
                  color: ShopStyle.stone,
                  child: Opacity(
                    opacity: hit.inStock ? 1 : 0.45,
                    child: _Photo(photoKey: hit.photoKey, capture: capture),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(hit.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: ShopStyle.ink)),
            const SizedBox(height: 2),
            Text(
              hit.inStock
                  ? money.format(hit.price)
                  : '${money.format(hit.price)} · Épuisé',
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
            ),
            Text(shopLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ShopStyle.mist)),
          ],
        ),
      ),
    );
  }
}

/// One paid spot: the photograph on its square, the name, the price, and
/// the shop it comes from — because the spot sells the shop, not the app.
class _FeaturedTile extends StatelessWidget {
  const _FeaturedTile({
    required this.item,
    required this.capture,
    required this.onTap,
  });

  final FeaturedItem item;
  final CaptureRepository capture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(item.currency);
    return SizedBox(
      width: 156,
      child: Semantics(
        button: true,
        label: [
          item.name,
          money.format(item.price),
          if (!item.inStock) 'épuisé',
          'chez ${item.shopName}',
          'à la une',
        ].join(', '),
        hint: 'Ouvrir la vitrine',
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: ColoredBox(
                    color: ShopStyle.stone,
                    child: Opacity(
                      opacity: item.inStock ? 1 : 0.45,
                      child: _Photo(photoKey: item.photoKey, capture: capture),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: ShopStyle.ink)),
              const SizedBox(height: 2),
              Text(money.format(item.price),
                  style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
              Text(item.shopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ShopStyle.mist)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A photo, fetched once through the public read and held for the life of
/// the tile — a rebuild must not refetch a picture on a slow link.
class _Photo extends StatefulWidget {
  const _Photo({required this.photoKey, required this.capture});

  final String? photoKey;
  final CaptureRepository capture;

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  late final Future<Uint8List>? _bytes = widget.photoKey == null
      ? null
      : widget.capture.publicObjectBytes(widget.photoKey!);

  @override
  Widget build(BuildContext context) {
    const placeholder = Center(
      child: Icon(Icons.image_outlined, size: 30, color: ShopStyle.line),
    );
    final future = _bytes;
    if (future == null) return placeholder;
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        // The picture leans in under the pointer; its frame holds still.
        return ClipRect(
          child: ZoomOnHover(
            child: Image.memory(bytes,
                fit: BoxFit.cover, semanticLabel: "Photo de l'article"),
          ),
        );
      },
    );
  }
}

/// One shop: a square showing what it sells (_ShopFace), the name, one line
/// about it, and — once the shopper said where they are — how far.
class _ShopTile extends StatelessWidget {
  const _ShopTile({
    required this.entry,
    required this.located,
    required this.onOpen,
    required this.capture,
    this.previews = const [],
    this.sponsored = false,
  });

  final DirectoryEntry entry;

  /// Paid for the top of the list (071), and said so on the card.
  final bool sponsored;
  final bool located;
  final VoidCallback onOpen;
  final CaptureRepository capture;

  /// Up to three of the shop's articles (070), photographed first.
  final List<ShopPreview> previews;

  @override
  Widget build(BuildContext context) {
    final line = (entry.address ?? '').trim().isNotEmpty
        ? entry.address!.trim()
        : (entry.blurb ?? '').trim();
    final distance = distanceLabel(entry.distanceKm);
    final second = line.isNotEmpty
        ? line
        : (located && !entry.hasLocation
            ? 'Position non renseignée'
            : _labelFor(entry.profile));

    return Semantics(
      button: true,
      label: [
        entry.name,
        if (line.isNotEmpty) _labelFor(entry.profile),
        second,
        if (distance != null) 'à $distance',
        if (sponsored) 'sponsorisé',
        // What the square shows a sighted shopper (070), said too.
        if (previews.isNotEmpty)
          'vend ${previews.map((p) => p.name).join(', ')}',
      ].join(', '),
      hint: 'Ouvrir la vitrine',
      onTap: onOpen,
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ColoredBox(
                  color: ShopStyle.stone,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // What the shop sells, not its initial (070): its
                      // photographs when it has some, else its articles
                      // and prices like a menu board.
                      _ShopFace(
                          previews: previews,
                          capture: capture,
                          profileIcon: _iconFor(entry.profile)),
                      if (sponsored)
                        const Positioned(
                          left: 10,
                          top: 10,
                          child: SponsoredTag(),
                        ),
                      if (distance != null)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: ShopStyle.ink,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(distance,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: ShopStyle.paper)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: ShopStyle.ink),
            ),
            const SizedBox(height: 3),
            Text(
              second,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String profile) => switch (profile) {
        'farm' => Icons.agriculture_outlined,
        'association' || 'church' => Icons.groups_outlined,
        _ => Icons.storefront_outlined,
      };

  static String _labelFor(String profile) => switch (profile) {
        'farm' => 'Ferme',
        'association' || 'church' => 'Association',
        _ => 'Boutique',
      };
}


/// A directory card's square (070). Photographs: the first large, two
/// small beside it. No photographs: the articles and their prices, set
/// like a menu board. Nothing at all: the kind of place, quietly.
class _ShopFace extends StatelessWidget {
  const _ShopFace({
    required this.previews,
    required this.capture,
    required this.profileIcon,
  });

  final List<ShopPreview> previews;
  final CaptureRepository capture;
  final IconData profileIcon;

  @override
  Widget build(BuildContext context) {
    final photos = previews.where((p) => p.photoKey != null).toList();
    if (photos.isNotEmpty) {
      final rest = previews.where((p) => p != photos.first).take(2).toList();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: _Photo(photoKey: photos.first.photoKey, capture: capture),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rest.length; i++) ...[
                    if (i > 0) const SizedBox(height: 2),
                    Expanded(
                      child: rest[i].photoKey != null
                          ? _Photo(photoKey: rest[i].photoKey, capture: capture)
                          : _MiniLabel(name: rest[i].name),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    }
    if (previews.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final p in previews)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: ShopStyle.ink)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p.price == p.price.roundToDouble()
                          ? '${p.price.toStringAsFixed(0)} F'
                          : '${p.price} F',
                      style:
                          const TextStyle(fontSize: 13, color: ShopStyle.mist),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Center(child: Icon(profileIcon, size: 34, color: ShopStyle.line));
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ShopStyle.line,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Align(
          alignment: Alignment.bottomLeft,
          // One line, shrunk to fit rather than broken mid-word.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Text(name,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ShopStyle.ink)),
          ),
        ),
      ),
    );
  }
}


/// "Sponsorisé" on a paid place (071): a spot is bought, and the street
/// says which ones are.
class SponsoredTag extends StatelessWidget {
  const SponsoredTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ShopStyle.paper.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text('Sponsorisé',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: ShopStyle.ink)),
    );
  }
}

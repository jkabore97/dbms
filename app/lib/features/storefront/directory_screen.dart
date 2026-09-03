import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/nav/session.dart';
import '../../core/storefront/storefront_repository.dart';
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
  List<FeaturedItem> _featured = const [];
  bool _loading = true;
  bool _locating = false;
  bool _map = false;
  String? _error;

  /// Where the shopper is, once they said so. Null until "près de moi".
  LatLng? _here;

  /// Ouagadougou's centre: where the map opens with nothing better to show.
  static const _ouaga = LatLng(12.3714, -1.5197);

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
      ]);
      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<DirectoryEntry>;
        _featured = results[1] as List<FeaturedItem>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "L'annuaire n'a pas pu être chargé. Vérifiez le réseau.";
        _loading = false;
      });
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
  Future<void> _showShop(DirectoryEntry entry) async {
    final line = (entry.address ?? '').trim().isNotEmpty
        ? entry.address!.trim()
        : (entry.blurb ?? '').trim();
    final distance = distanceLabel(entry.distanceKm);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => Theme(
        data: ShopStyle.theme(sheet),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: ShopStyle.ink)),
              if (line.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(line,
                    style: const TextStyle(
                        fontSize: 15, color: ShopStyle.mist)),
              ],
              if (distance != null) ...[
                const SizedBox(height: 4),
                Text('À $distance',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink)),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      _open(entry);
                    },
                    child: const Text('Voir la vitrine'),
                  ),
                  if (entry.hasLocation)
                    OutlinedButton.icon(
                      onPressed: () => _directions(entry.lat!, entry.lng!),
                      icon: const Icon(Icons.directions_outlined, size: 18),
                      label: const Text('Itinéraire'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShopPage(
      title: 'Les vitrines',
      trailing: _AccountCorner(session: widget.session),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : _Street(
                  entries: _entries,
                  featured: _featured,
                  capture: widget.capture,
                  here: _here,
                  fallback: _ouaga,
                  map: _map,
                  locating: _locating,
                  onNearMe: _nearMe,
                  onToggleMap: () => setState(() => _map = !_map),
                  onOpen: _open,
                  onPin: _showShop,
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
    required this.featured,
    required this.capture,
    required this.here,
    required this.fallback,
    required this.map,
    required this.locating,
    required this.onNearMe,
    required this.onToggleMap,
    required this.onOpen,
    required this.onPin,
  });

  final List<DirectoryEntry> entries;
  final List<FeaturedItem> featured;
  final CaptureRepository capture;
  final LatLng? here;
  final LatLng fallback;
  final bool map;
  final bool locating;
  final VoidCallback onNearMe;
  final VoidCallback onToggleMap;
  final void Function(DirectoryEntry) onOpen;
  final void Function(DirectoryEntry) onPin;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 560;
    final columns = ShopStyle.columnsFor(width);
    final placed = entries.where((e) => e.hasLocation).toList();
    final located = here != null;
    final unplaced = entries.length - placed.length;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: EdgeInsets.symmetric(
                horizontal: 20, vertical: wide ? 56 : 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Les boutiques,\nprès de vous.',
                  style: TextStyle(
                    fontSize: wide ? 40 : 30,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: ShopStyle.ink,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const Text(
                    'Chaque vitrine est tenue par la boutique elle-même : '
                    'ses articles, ses prix, son numéro. Dites où vous êtes '
                    'et les plus proches passent en premier.',
                    style: TextStyle(
                        fontSize: 17, height: 1.45, color: ShopStyle.ink),
                  ),
                ),
                const SizedBox(height: 22),
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
                      icon: Icon(
                          map ? Icons.grid_view_outlined : Icons.map_outlined,
                          size: 18),
                      label: Text(map ? 'Masquer la carte' : 'Voir la carte'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ShopWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The paid spots, when there are any: a strip, not the page.
              if (featured.isNotEmpty) ...[
                const SizedBox(height: 32),
                const ShopSectionLabel('À la une', note: 'Sélection'),
                const SizedBox(height: 14),
                SizedBox(
                  height: 244,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: featured.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => _FeaturedTile(
                      item: featured[i],
                      capture: capture,
                      onTap: () =>
                          context.go(Routes.storefront(featured[i].shopSlug)),
                    ),
                  ),
                ),
              ],
              if (map) ...[
                const SizedBox(height: 24),
                SizedBox(
                  height: wide ? 460 : 340,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: placed.isEmpty
                        ? const ColoredBox(
                            color: ShopStyle.stone,
                            child: ShopNotice(
                              text: "Aucune vitrine n'a encore indiqué sa "
                                  'position. Les boutiques la renseignent '
                                  'dans leurs paramètres.',
                            ),
                          )
                        : _MapView(
                            entries: placed,
                            here: here,
                            fallback: fallback,
                            onPin: onPin,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  placed.isEmpty
                      ? 'Touchez un repère pour voir la boutique et y aller.'
                      : unplaced == 0
                          ? 'Touchez un repère pour voir la boutique et y aller.'
                          : 'Touchez un repère pour voir la boutique et y aller. '
                              '$unplaced vitrine${unplaced > 1 ? 's' : ''} sans '
                              "position n'apparaî${unplaced > 1 ? 'ssent' : 't'} "
                              'que dans la liste.',
                  style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
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
                  itemBuilder: (context, i) => _ShopTile(
                    entry: entries[i],
                    located: located,
                    onOpen: () => onOpen(entries[i]),
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
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}

/// One shop: a warm square with its initial, the name, one line about it,
/// and — once the shopper said where they are — how far.
class _ShopTile extends StatelessWidget {
  const _ShopTile({
    required this.entry,
    required this.located,
    required this.onOpen,
  });

  final DirectoryEntry entry;
  final bool located;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final line = (entry.address ?? '').trim().isNotEmpty
        ? entry.address!.trim()
        : (entry.blurb ?? '').trim();
    final distance = distanceLabel(entry.distanceKm);
    final initial =
        entry.name.trim().isEmpty ? '·' : entry.name.trim()[0].toUpperCase();

    return InkWell(
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
                  children: [
                    Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w700,
                          color: ShopStyle.line,
                          height: 1,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: Icon(_iconFor(entry.profile),
                          size: 18, color: ShopStyle.mist),
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
            line.isNotEmpty
                ? line
                : (located && !entry.hasLocation
                    ? 'Position non renseignée'
                    : _labelFor(entry.profile)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: ShopStyle.mist),
          ),
        ],
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

class _MapView extends StatelessWidget {
  const _MapView({
    required this.entries,
    required this.here,
    required this.fallback,
    required this.onPin,
  });

  final List<DirectoryEntry> entries;
  final LatLng? here;
  final LatLng fallback;
  final void Function(DirectoryEntry) onPin;

  @override
  Widget build(BuildContext context) {
    final centre = here ??
        (entries.isNotEmpty
            ? LatLng(entries.first.lat!, entries.first.lng!)
            : fallback);

    return FlutterMap(
      options: MapOptions(initialCenter: centre, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kaj.app',
        ),
        MarkerLayer(
          markers: [
            if (here != null)
              Marker(
                point: here!,
                width: 22,
                height: 22,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ShopStyle.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: ShopStyle.paper, width: 3),
                  ),
                ),
              ),
            // Each pin carries the shop's name under it. The widget is 68px
            // tall with the 34px icon at the top, so the widget's centre —
            // where flutter_map puts the point — is the tip of the pin, and
            // the label hangs below the spot rather than covering it.
            for (final e in entries)
              Marker(
                point: LatLng(e.lat!, e.lng!),
                width: 150,
                height: 68,
                child: GestureDetector(
                  onTap: () => onPin(e),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on,
                          size: 34, color: ShopStyle.ink),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 146),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: ShopStyle.paper,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: ShopStyle.line),
                        ),
                        child: Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: ShopStyle.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}

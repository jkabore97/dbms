import 'package:flutter/material.dart';

import '../../core/theme/motion.dart';
import 'shop_style.dart';

/// The page before its content: the shape of what is coming, in the paper
/// colours, breathing slowly. A spinner in the middle of a blank page says
/// "wait"; a skeleton says "here is where the shops go, they are on their
/// way" — and on a 3G link in Ouagadougou the second is the difference
/// between a shopper who stays and one who leaves.
///
/// One pulse for the whole block, not one per bone: everything breathes
/// together, which reads as calm, and costs one animation instead of
/// twenty. A device asked for less motion gets the shapes still. To a
/// screen reader the block is one word — "Chargement…" — and nothing more.
class ShopSkeleton extends StatelessWidget {
  /// The street: the search band and the grid of shop tiles.
  const ShopSkeleton.street({super.key})
      : child = const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 36),
            Bone(width: 220, height: 30, radius: 8),
            SizedBox(height: 12),
            Bone(width: 300, height: 14),
            SizedBox(height: 22),
            Bone(width: 420, height: 46, radius: 999),
            SizedBox(height: 14),
            Row(children: [
              Bone(width: 120, height: 36, radius: 999),
              SizedBox(width: 10),
              Bone(width: 96, height: 36, radius: 999),
            ]),
            SizedBox(height: 40),
            Bone(width: 150, height: 12),
            SizedBox(height: 18),
            _Grid(tiles: 6, aspectRatio: 1.15),
            SizedBox(height: 48),
          ],
        );

  /// One shop: its name and blurb, the buttons, then the shelf.
  const ShopSkeleton.shelf({super.key})
      : child = const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 36),
            Bone(width: 260, height: 34, radius: 8),
            SizedBox(height: 14),
            Bone(width: 380, height: 16),
            SizedBox(height: 8),
            Bone(width: 200, height: 14),
            SizedBox(height: 22),
            Row(children: [
              Bone(width: 180, height: 50, radius: 999),
              SizedBox(width: 12),
              Bone(width: 110, height: 50, radius: 999),
            ]),
            SizedBox(height: 40),
            Bone(width: 110, height: 12),
            SizedBox(height: 18),
            _Grid(tiles: 6),
            SizedBox(height: 48),
          ],
        );

  /// Search results: a grid of article tiles under the "Résultats" label.
  ShopSkeleton.grid({super.key, int tiles = 6})
      : child = Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 48),
          child: _Grid(tiles: tiles),
        );

  /// A list of cards: orders, deliveries.
  ShopSkeleton.list({super.key, int rows = 4}) : child = _Rows(rows: rows);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement…',
      liveRegion: true,
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: _Pulse(child: ShopWidth(child: child)),
        ),
      ),
    );
  }
}

/// One grey shape where a thing will be.
class Bone extends StatelessWidget {
  const Bone({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// A square the photo will fill, with a name and a price under it.
class _TileBone extends StatelessWidget {
  const _TileBone({this.aspectRatio = 1});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: aspectRatio,
          child: const Bone(height: double.infinity, radius: 6),
        ),
        const SizedBox(height: 10),
        const Bone(width: 120, height: 14),
        const SizedBox(height: 8),
        const Bone(width: 64, height: 12),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.tiles, this.aspectRatio = 1});

  final int tiles;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 560;
    final columns = ShopStyle.columnsFor(width);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: wide ? 24 : 14,
        mainAxisSpacing: wide ? 36 : 26,
        childAspectRatio: wide ? 0.70 : 0.62,
      ),
      itemCount: tiles,
      itemBuilder: (_, _) => _TileBone(aspectRatio: aspectRatio),
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Bone(width: 110, height: 12),
        const SizedBox(height: 16),
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(child: Bone(height: 16)),
                    const SizedBox(width: 40),
                    Bone(width: i.isEven ? 72 : 56, height: 16),
                  ]),
                  const SizedBox(height: 10),
                  const Bone(width: 220, height: 12),
                  const SizedBox(height: 8),
                  const Bone(width: 140, height: 12),
                ],
              ),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// A slow breath: the block fades between full and a little more than half,
/// over and over, until the content replaces it. Held still when the device
/// asked for less motion.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (KajMotion.reduced(context)) {
      _controller.stop();
      return widget.child;
    }
    if (!_controller.isAnimating) _controller.repeat(reverse: true);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.55).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// A street photo that is only asked for when its tile comes near the
/// screen, and at the size it is drawn.
///
/// A vitrine laid out its whole shelf at once (a shrink-wrapped grid), so
/// every photograph was requested the moment the page opened: forty
/// articles, forty downloads sharing one 3G line, and the four on screen
/// arrived last. Now a tile further than a screen away waits until the
/// shopper scrolls toward it, and [load] is told how many pixels wide the
/// picture is drawn, so the uploads Worker can answer a small copy
/// (`?w=`, workers/uploads) instead of the 2000 px original.
///
/// Once started, the download is held for the life of the tile — a rebuild
/// must not refetch a picture on a slow link.
class LazyPhoto extends StatefulWidget {
  const LazyPhoto({
    super.key,
    required this.load,
    required this.builder,
    required this.placeholder,
  });

  /// Fetches the picture for a tile [pixelWidth] device pixels wide.
  final Future<Uint8List> Function(int pixelWidth) load;

  /// Draws it; [pixelWidth] is what [load] was given, for decoding at that
  /// size rather than the original's.
  final Widget Function(BuildContext context, Uint8List bytes, int pixelWidth)
      builder;

  final Widget placeholder;

  /// How far outside the visible area a tile starts its download: one
  /// screen ahead, so a picture is usually there by the time it scrolls in.
  static const double lookAhead = 1.0;

  @override
  State<LazyPhoto> createState() => _LazyPhotoState();
}

class _LazyPhotoState extends State<LazyPhoto> {
  Future<Uint8List>? _bytes;
  int _pixelWidth = 0;
  final _watched = <ScrollPosition>[];
  bool _checkPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _unwatch();
    super.dispose();
  }

  void _unwatch() {
    for (final p in _watched) {
      p.removeListener(_scrolled);
    }
    _watched.clear();
  }

  // A scroll moves the tile on the next frame's layout: look then.
  void _scrolled() {
    if (_checkPending) return;
    _checkPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPending = false;
      _check();
    });
  }

  void _check() {
    if (!mounted || _bytes != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
      return;
    }
    if (_near(box)) {
      _unwatch();
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      // The longer side: a square photo covering a wide or a tall frame
      // must be at least that wide to stay sharp.
      _pixelWidth = (box.size.longestSide * ratio).ceil().clamp(1, 4096);
      // A picture that cannot come shows the placeholder; its failure is
      // the builder's to hear, even before the next frame listens.
      final bytes = widget.load(_pixelWidth)..ignore();
      setState(() {
        _bytes = bytes;
      });
      return;
    }
    // Further away: wait for the shopper to scroll toward it — in any of
    // the lists around it (a vitrine's shelf is a grid inside a list).
    if (_watched.isEmpty) {
      BuildContext? at = context;
      while (at != null && _watched.length < 8) {
        final scrollable = Scrollable.maybeOf(at);
        if (scrollable == null || _watched.contains(scrollable.position)) break;
        _watched.add(scrollable.position..addListener(_scrolled));
        at = scrollable.context;
      }
    }
  }

  /// Whether the tile is on the screen, or within [LazyPhoto.lookAhead]
  /// screens of it in any direction.
  bool _near(RenderBox box) {
    final screen = MediaQuery.maybeSizeOf(context);
    if (screen == null) return true;
    final Offset at;
    try {
      at = box.localToGlobal(Offset.zero);
    } catch (_) {
      return true;
    }
    final area = (Offset.zero & screen).inflate(
        screen.longestSide * LazyPhoto.lookAhead);
    return area.overlaps(at & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final future = _bytes;
    if (future == null) return widget.placeholder;
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return widget.placeholder;
        return widget.builder(context, bytes, _pixelWidth);
      },
    );
  }
}

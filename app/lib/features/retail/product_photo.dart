import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/capture/capture_repository.dart';

/// An article's picture on the Articles page — the list's thumbnail and the
/// card's square.
///
/// Fetched as bytes through the uploads Worker with the caller's token
/// (CaptureRepository.objectBytes, which remembers what it already fetched),
/// because every read of the bucket is authorised and an `<img>` tag cannot
/// carry one. An article with no photograph, a build with no uploads, or a
/// fetch that fails all show the same thing: the name's first letter on a
/// soft square, so the page never shows a broken image.
class ProductPhoto extends StatefulWidget {
  const ProductPhoto({
    super.key,
    required this.name,
    this.photoKey,
    this.capture,
    this.letterSize = 22,
    this.fit = BoxFit.cover,
  });

  final String name;
  final String? photoKey;
  final CaptureRepository? capture;
  final double letterSize;

  /// Cover for an article's square; contain for a logo, shown whole.
  final BoxFit fit;

  /// How wide to decode a photograph drawn in [box] (freeze audit). The
  /// photos are up to 2000 px (capture_action.dart): decoded whole, each
  /// 60 px thumbnail of the Articles list cost 12 MB and a decode on the
  /// UI's raster thread — a list of them stalled a low-end phone's
  /// scrolling, and on some ran it out of memory. Twice the box's longer
  /// side, so a photo twice as wide as tall still covers its square; null
  /// (the whole picture) where the box has no size.
  static int? decodeWidth(BoxConstraints box, double devicePixelRatio) {
    final w = box.maxWidth.isFinite ? box.maxWidth : 0.0;
    final h = box.maxHeight.isFinite ? box.maxHeight : 0.0;
    final side = w > h ? w : h;
    if (side <= 0) return null;
    return (side * devicePixelRatio * 2).ceil();
  }

  @override
  State<ProductPhoto> createState() => _ProductPhotoState();
}

class _ProductPhotoState extends State<ProductPhoto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(ProductPhoto old) {
    super.didUpdateWidget(old);
    if (old.photoKey != widget.photoKey) {
      _bytes = null;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final key = widget.photoKey;
    final capture = widget.capture;
    if (key == null || capture == null || !capture.isConfigured) return;
    try {
      final bytes = await capture.objectBytes(key);
      if (mounted && widget.photoKey == key) setState(() => _bytes = bytes);
    } catch (_) {
      // The letter stays.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return LayoutBuilder(
        builder: (context, box) => Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          semanticLabel: widget.name,
          cacheWidth: ProductPhoto.decodeWidth(box, MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
          errorBuilder: (_, _, _) => _letter(context),
        ),
      );
    }
    return _letter(context);
  }

  Widget _letter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.name.trim();
    return Container(
      color: scheme.secondaryContainer,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: widget.letterSize,
          fontWeight: FontWeight.w600,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

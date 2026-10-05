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
  });

  final String name;
  final String? photoKey;
  final CaptureRepository? capture;
  final double letterSize;

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
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        semanticLabel: widget.name,
        errorBuilder: (_, _, _) => _letter(context),
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

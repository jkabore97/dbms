import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/capture/models.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/theme/mara_mark.dart';

/// « Choisir dans Photos » (114): the business's own photographs — the
/// gallery « Photos » — to give one to an article or a service instead of
/// taking it again. Only pictures: a delivery note, a receipt, a logo or a
/// PDF is never an article's photo (100's doc_is_photo, [CapturedDocument.
/// isPicture]). A photo another article already wears is offered too, and
/// said: it can serve both.
///
/// Returns the chosen document, or null when the sheet is closed.
Future<CapturedDocument?> showPhotoLibrary(
  BuildContext context, {
  required String orgId,
  required CaptureRepository capture,
}) =>
    showModalBottomSheet<CapturedDocument>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PhotoLibrarySheet(orgId: orgId, capture: capture),
    );

class PhotoLibrarySheet extends StatefulWidget {
  const PhotoLibrarySheet({super.key, required this.orgId, required this.capture});

  final String orgId;
  final CaptureRepository capture;

  @override
  State<PhotoLibrarySheet> createState() => _PhotoLibrarySheetState();
}

class _PhotoLibrarySheetState extends State<PhotoLibrarySheet> {
  List<CapturedDocument>? _photos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _photos = null;
      _error = null;
    });
    try {
      // The newest first, as the gallery shows them; a few screens' worth.
      final docs = await widget.capture.documents(widget.orgId, limit: 120);
      if (!mounted) return;
      setState(() => _photos = docs.where((d) => d.isPicture).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos = _photos;
    final Widget body;
    if (_error != null) {
      body = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
        ],
      );
    } else if (photos == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (photos.isEmpty) {
      body = Column(
        key: const Key('photo-library-empty'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 48, color: theme.disabledColor),
          const SizedBox(height: 12),
          Text(context.tr('Aucune photo dans Photos pour le moment.'),
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(context.tr('Prenez-la avec « Prendre une photo » : elle y sera gardée.'),
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      );
    } else {
      body = GridView.builder(
        key: const Key('photo-library-grid'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: photos.length,
        itemBuilder: (_, i) => _Tile(
          document: photos[i],
          capture: widget.capture,
          onTap: () => Navigator.of(context).pop(photos[i]),
        ),
      );
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('Choisir dans Photos'), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(context.tr('Les photos de votre activité. Touchez celle à mettre.'),
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// One photo, square; the article that already wears it said underneath.
class _Tile extends StatefulWidget {
  const _Tile({required this.document, required this.capture, required this.onTap});

  final CapturedDocument document;
  final CaptureRepository capture;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      // Through the authorised route, as the gallery reads them; held once
      // read, so the one chosen is not fetched twice.
      final bytes = await widget.capture.objectBytes(widget.document.key);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = widget.document.productName;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('photo-library-${widget.document.id}'),
        // A photo that would not load cannot be checked first: not offered.
        onTap: _bytes == null ? null : widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_bytes != null)
              Image.memory(_bytes!, fit: BoxFit.cover, semanticLabel: widget.document.title)
            else
              Center(
                child: _failed
                    ? Icon(Icons.image_not_supported_outlined, color: theme.disabledColor)
                    : const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (on != null && on.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: maraDeep.withValues(alpha: 0.72),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    context.tr('Sur : {name}', {'name': on.trim()}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: maraPaper),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

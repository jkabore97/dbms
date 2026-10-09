import 'dart:typed_data';

import '../../core/theme/kaj_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/capture/invoice_reading.dart';
import '../../core/capture/models.dart';
import '../../core/capture/text_reader.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import 'capture_action.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// Everything this business has photographed.
///
/// Two lists, and the order is the argument. The pile that is about nothing
/// yet comes first — not because it is more important, but because it is the
/// only thing in the app that asks for a minute of somebody's time, and a
/// queue nobody can see going down is a queue nobody works.
///
/// A photograph that stays unfiled forever is a success, not a failure: the
/// picture of the delivery note exists, which it would not have if the app
/// had asked for a category first.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.org,
    required this.capture,
    this.retail,
  });

  final OrgSummary org;
  final CaptureRepository capture;

  /// Only a shop has products to attach a photograph to. Null everywhere
  /// else, and the product picker is then not offered at all.
  final RetailRepository? retail;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<CapturedDocument> _documents = const [];
  List<Product> _products = const [];
  ({int waiting, int stuck}) _queue = (waiting: 0, stuck: 0);

  bool _loading = true;
  String? _error;

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
      // Send anything the phone is still holding before reading the list,
      // otherwise a photograph taken with no signal is invisible on the very
      // screen that exists to show it.
      await widget.capture.drain();

      final documents = await widget.capture.documents(widget.org.id);
      final queue = await widget.capture.queueHealth(widget.org.id);
      final products = widget.retail == null
          ? const <Product>[]
          : await widget.retail!.products(widget.org.id);

      if (!mounted) return;
      setState(() {
        _documents = documents;
        _products = products;
        _queue = queue;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _capture() async {
    final taken = await CaptureAction.choose(
      context,
      orgId: widget.org.id,
      capture: widget.capture,
    );
    if (taken) await _load();
  }

  /// The handwriting reader: photograph a page of the paper carnet, let the
  /// AI read it, and land on the same confirm-before-save screen the invoice
  /// capture uses. Online-only, and honest about it — the sheet the person
  /// edits is the safety net, not the reading.
  Future<void> _readNotebook() async {
    final picked = await CaptureAction.pick(context);
    if (picked == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        SnackBar(content: Text(context.tr('Lecture de la page…'))));
    try {
      final lines = await widget.capture.readNotebookPage(
        orgId: widget.org.id,
        bytes: picked.bytes,
        contentType: picked.contentType,
      );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (lines.isEmpty) {
        messenger.showSnackBar(SnackBar(
            content: Text(context.tr('Rien de lisible sur cette page. Reprenez la photo de plus près, bien éclairée.'))));
        return;
      }
      final added = await context.push<bool>(
        Routes.inside(widget.org.id, 'photos/produits'),
        extra: ConfirmProductsArg(lines: lines),
      );
      if (added == true && mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _open(CapturedDocument document) async {
    // The document itself travels as `extra` rather than being refetched by
    // id: it is already loaded here, and a second round trip to draw a
    // photograph somebody just tapped would be a visible delay on a bad line.
    final changed = await context.push<bool>(
      Routes.inside(widget.org.id, 'photos/document'),
      extra: DocumentArg(document: document, products: _products),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unfiled = _documents.where((d) => !d.isFiled).toList();
    final filed = _documents.where((d) => d.isFiled).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Photos')),
        actions: [
          // Only a shop stocks products, so only a shop reads carnets — an
          // association keeps no stock.
          if (widget.retail != null &&
              !widget.org.isAssociation &&
              widget.capture.isConfigured)
            IconButton(
              onPressed: _readNotebook,
              icon: const Icon(Icons.auto_stories_outlined),
              tooltip: context.tr('Lire une page de carnet'),
            ),
          bellRoom,
        ],
      ),
      // Same posture as the store home: the camera is drawn only in a build
      // compiled with the upload Worker's address (UPLOADS_URL).
      floatingActionButton: widget.capture.isConfigured
          ? FloatingActionButton.extended(
              onPressed: _capture,
              icon: const Icon(Icons.photo_camera),
              label: Text(context.tr('Photo')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (_loading) const LinearProgressIndicator(),

            if (_error != null) ...[
              _Banner(
                colour: theme.colorScheme.errorContainer,
                icon: Icons.error_outline,
                text: _error!,
                action: TextButton(
                  onPressed: _load,
                  child: Text(context.tr('Réessayer')),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Photographs still on this phone. Never phrased as a failure
            // while they have not been tried: no signal is the normal state.
            if (_queue.waiting > 0) ...[
              _Banner(
                colour: _queue.stuck > 0
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.secondaryContainer,
                icon: _queue.stuck > 0
                    ? Icons.sync_problem
                    : Icons.cloud_upload_outlined,
                text: _queue.stuck > 0
                    ? context.tr('{n} photo(s) sur cet appareil. Le serveur en a refusé {stuck}.',
                        {'n': _queue.waiting, 'stuck': _queue.stuck})
                    : context.tr('{n} photo(s) en attente de réseau.', {'n': _queue.waiting}),
                action: TextButton(
                  onPressed: _load,
                  child: Text(context.tr('Envoyer')),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (unfiled.isNotEmpty) ...[
              Text(context.tr('À classer'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                context.tr('Une photo sans nom reste une preuve. La classer la rend trouvable.'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ...unfiled.map((d) => _DocumentTile(
                    document: d,
                    capture: widget.capture,
                    onTap: () => _open(d),
                  )),
              const SizedBox(height: 24),
            ],

            if (filed.isNotEmpty) ...[
              Text(context.tr('Classées'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...filed.map((d) => _DocumentTile(
                    document: d,
                    capture: widget.capture,
                    onTap: () => _open(d),
                  )),
            ],

            if (!_loading && _documents.isEmpty && _queue.waiting == 0)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(Icons.photo_camera_outlined,
                        size: 48, color: theme.disabledColor),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('Aucune photo pour le moment.'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('Photographiez une facture, une livraison, une étiquette. Rien d’autre n’est demandé.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One row: the thumbnail, what it is about, and when it was taken.
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.capture,
    required this.onTap,
  });

  final CapturedDocument document;
  final CaptureRepository capture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = document.capturedAt;

    return KajCard(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: _Thumbnail(document: document, capture: capture),
        ),
        title: Text(document.title),
        subtitle: Text(
          [
            if (when != null) DateFormat('d MMM y', intlLocale()).format(when),
            if (document.kind != null) document.kind!,
            if (document.barcode != null) document.barcode!,
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: document.isFiled
            ? null
            : Icon(Icons.label_outline, color: theme.colorScheme.primary),
        onTap: onTap,
      ),
    );
  }
}

/// Fetched as bytes rather than given to `Image.network`.
///
/// Every read of the bucket is authorised — the request carries the caller's
/// access token — and a browser's `<img>` tag cannot send one. So the bytes
/// come back through the same authorised path as everything else and are
/// rendered from memory.
class _Thumbnail extends StatefulWidget {
  const _Thumbnail({required this.document, required this.capture});

  final CapturedDocument document;
  final CaptureRepository capture;

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (widget.document.isPdf) {
      setState(() => _failed = true);
      return;
    }
    try {
      final bytes = await widget.capture.objectBytes(widget.document.key);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_bytes != null) {
      return Image.memory(_bytes!,
          fit: BoxFit.cover, semanticLabel: widget.document.title);
    }
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: _failed
          ? Icon(
              widget.document.isPdf
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_not_supported_outlined,
              color: theme.disabledColor,
            )
          : const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}

/// One photograph, full size, and everything anybody has said about it.
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({
    super.key,
    required this.org,
    required this.document,
    required this.capture,
    this.retail,
    this.products = const [],
  });

  final OrgSummary org;
  final CapturedDocument document;
  final CaptureRepository capture;

  /// Needed to turn a read delivery note into stock. Null outside a shop,
  /// where there are no products for an invoice to be about.
  final RetailRepository? retail;

  final List<Product> products;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late final TextEditingController _caption =
      TextEditingController(text: widget.document.caption ?? '');

  Uint8List? _bytes;
  String? _imageError;
  String? _productId;
  String? _kind;
  bool _saving = false;
  bool _changed = false;

  late final ReadingSuggestions _suggestions =
      ReadingSuggestions.parse(widget.document.ocrText);

  /// The same text read a second way: as a delivery note with many lines
  /// rather than one label. A photograph is usually one or the other, and
  /// which one it is is obvious from whether this comes back empty.
  late final List<InvoiceLine> _invoiceLines =
      InvoiceReading.parse(widget.document.ocrText);

  @override
  void initState() {
    super.initState();
    _productId = widget.document.productId;
    _kind = widget.document.kind;
    _fetch();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (widget.document.isPdf) {
      setState(
          () => _imageError = context.tr('PDF — ouvrez-le depuis le lien de partage.'));
      return;
    }
    try {
      final bytes = await widget.capture.objectBytes(widget.document.key);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _imageError = describeError(error));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.capture.file(
        documentId: widget.document.id,
        caption: _caption.text,
        kind: _kind,
        productId: _productId,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _changed = true;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('Classée.'))));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _addToStock() async {
    final retail = widget.retail;
    if (retail == null) return;

    final added = await context.push<bool>(
      Routes.inside(widget.org.id, 'photos/produits'),
      extra: ConfirmProductsArg(
        lines: _invoiceLines,
        documentId: widget.document.id,
      ),
    );
    if (added == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final document = widget.document;
    final canReadInvoice = widget.retail != null &&
        !widget.org.isAssociation &&
        _invoiceLines.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          actions: const [bellRoom],
          title: Text(document.title),
          leading:
              BackButton(onPressed: () => Navigator.of(context).pop(_changed)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: _bytes != null
                    ? InteractiveViewer(
                        child: Image.memory(_bytes!,
                            semanticLabel: document.title))
                    : _imageError != null
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_imageError!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall),
                          )
                        : const CircularProgressIndicator(),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _caption,
              decoration: InputDecoration(
                labelText: context.tr('Nom (facultatif)'),
                helperText: context.tr('Ce que c’est, en vos mots.'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: InputDecoration(
                labelText: context.tr('Type (facultatif)'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'receipt', child: Text(context.tr('Reçu'))),
                DropdownMenuItem(value: 'invoice', child: Text(context.tr('Facture'))),
                DropdownMenuItem(
                    value: 'product_photo', child: Text(context.tr('Photo d’article'))),
                DropdownMenuItem(value: 'photo', child: Text(context.tr('Autre'))),
              ],
              onChanged: (value) => setState(() => _kind = value),
            ),

            if (widget.products.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _productId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Article (facultatif)'),
                  border: const OutlineInputBorder(),
                ),
                items: widget.products
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _productId = value),
              ),
            ],

            // The one thing M5's demo is about, and so the first thing
            // offered: a photographed delivery note becoming stock. Above the
            // single-label suggestions because a picture that has lines on it
            // is a delivery, and naming it is not what she wants to do next.
            if (canReadInvoice) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('{n} article(s) lu(s) sur cette photo', {'n': _invoiceLines.length}),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _invoiceLines.take(3).map((l) => l.name).join(' · '),
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _addToStock,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: Text(context.tr('Vérifier et ajouter au stock')),
                    ),
                  ],
                ),
              ),
            ],

            if (document.ocrText != null) ...[
              const SizedBox(height: 20),
              // What the reading suggests, offered as buttons that fill the
              // form above. Suggestions, never applied: the person taps one
              // and can then edit it, which is the difference between an
              // accelerator and the app inventing an expiry date.
              if (!_suggestions.isEmpty) ...[
                Text(context.tr('Suggestions'), style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_suggestions.name != null)
                      ActionChip(
                        avatar: const Icon(Icons.label_outline, size: 16),
                        label: Text(_suggestions.name!),
                        onPressed: () =>
                            setState(() => _caption.text = _suggestions.name!),
                      ),
                    if (_suggestions.price != null)
                      Chip(
                        avatar: const Icon(Icons.sell_outlined, size: 16),
                        label: Text(context.tr('Prix lu : {price}',
                            {'price': _suggestions.price!.toStringAsFixed(0)})),
                      ),
                    if (_suggestions.expiresOn != null)
                      Chip(
                        avatar: const Icon(Icons.event_outlined, size: 16),
                        label: Text(context.tr('Péremption lue : {date}', {
                          'date': DateFormat('d MMM y', intlLocale()).format(_suggestions.expiresOn!),
                        })),
                      ),
                    if (_suggestions.barcode != null)
                      Chip(
                        avatar: const Icon(Icons.qr_code_2, size: 16),
                        label: Text(_suggestions.barcode!),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('Lecture automatique. Rien n’est appliqué : touchez un nom pour le reprendre, vérifiez le reste vous-même.'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
              Text(context.tr('Ce que le téléphone a lu'),
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              // Shown, never applied. A misread date that silently became a
              // product's expiry is the exact loss this module exists to
              // prevent, with the app's name on it.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  document.ocrText!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('Lecture automatique, à vérifier. Rien n’est modifié tant que vous ne le faites pas.'),
                style: theme.textTheme.bodySmall,
              ),
            ],

            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(context.tr('Enregistrer')),
            ),
            const SizedBox(height: 8),
            Text(
              document.uploadedName == null
                  ? context.tr('Aucune photo n’est supprimée : une preuve qui disparaît ne se distingue pas d’une preuve qui n’a jamais existé.')
                  : context.tr('Prise par {uploadedName}. Aucune photo n’est supprimée.', {'uploadedName': document.uploadedName}),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.colour,
    required this.icon,
    required this.text,
    this.action,
  });

  final Color colour;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          ?action,
        ],
      ),
    );
  }
}

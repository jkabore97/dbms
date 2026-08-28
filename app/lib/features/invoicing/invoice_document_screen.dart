import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/models.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/invoicing/models.dart';
import '../../core/nav/router.dart';
import '../accounting/report_shell.dart';
import 'invoice_paper.dart';
import '../../core/errors.dart';

/// The invoice as a document somebody can actually be handed.
///
/// This is the part that was missing. `outstanding_invoices()` has always
/// answered "who has not paid", which is the collections question; nothing
/// answered "what does invoice 2026-0007 say", which is the question you have
/// to answer to put it in a customer's hand. A receivable in a ledger is not
/// a document, and a business whose app cannot produce one goes back to the
/// carbon-copy book it was using before.
///
/// It leaves as a PNG rather than a PDF, and that is a considered choice.
/// The destination is WhatsApp — that is where these conversations happen
/// here — and an image opens in the chat while a PDF is an attachment the
/// recipient has to decide to download. A PDF renderer would also be a new
/// dependency on both ship targets for a document that is one page of text.
///
/// Painted at 3x for the same reason the weekly summary is: WhatsApp
/// re-compresses whatever it is given, and a blurred invoice is worse than
/// none.
class InvoiceDocumentScreen extends StatefulWidget {
  const InvoiceDocumentScreen({
    super.key,
    required this.org,
    required this.invoicing,
    required this.invoiceId,
  });

  final OrgSummary org;
  final InvoicingRepository invoicing;
  final String invoiceId;

  @override
  State<InvoiceDocumentScreen> createState() => _InvoiceDocumentScreenState();
}

class _InvoiceDocumentScreenState extends State<InvoiceDocumentScreen> {
  final _paperKey = GlobalKey();

  InvoiceDocument? _doc;
  bool _loading = true;
  Object? _error;
  bool _sharing = false;
  bool _working = false;

  bool get _canWrite => !widget.org.isObserverOnly;

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
      final doc = await widget.invoicing.document(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// The paper as pixels — the one capture behind both sending and printing,
  /// so what leaves the shop is always exactly what is on screen.
  Future<Uint8List> _capturePaper() async {
    final boundary = _paperKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) throw StateError("La facture n'est pas prête.");

    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError("L'image n'a pas pu être créée.");
    return data.buffer.asUint8List();
  }

  Future<void> _share() async {
    final doc = _doc;
    if (doc == null || _sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final png = await _capturePaper();
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            png,
            mimeType: 'image/png',
            name: 'facture-${doc.number}.png',
          ),
        ],
        text: '${doc.orgName} — facture ${doc.number}',
      ));
    } catch (error) {
      if (!mounted) return;
      // Sharing a file is not available everywhere this build runs; on the
      // web it depends on the browser. Say so rather than failing mute.
      messenger.showSnackBar(SnackBar(
        content: Text("Partage impossible sur cet appareil. $error"),
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// One page, A4, wrapping the same capture the share button sends — the one
  /// source behind both printing and the downloadable file, so the shop's paper,
  /// its print-out and its saved PDF are pixel-for-pixel the same document.
  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final png = await _capturePaper();
    final image = pw.MemoryImage(png);
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Center(
        child: pw.Image(image, fit: pw.BoxFit.contain),
      ),
    ));
    return pdf.save();
  }

  /// The system print dialog (the browser's, on the web), fed the one-page PDF.
  Future<void> _print() async {
    final doc = _doc;
    if (doc == null || _sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await Printing.layoutPdf(
        name: 'facture-${doc.number}',
        onLayout: (format) => _buildPdf(format),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text("Impression impossible sur cet appareil. $error"),
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Save the invoice as a PDF file. On the web this downloads
  /// `facture-<n°>.pdf`; on the phone it opens the system save/share sheet, so
  /// the same document can be kept, e-mailed or printed from a computer later.
  /// Deliberately a PDF, not the WhatsApp image: a file to keep, not to chat.
  Future<void> _download() async {
    final doc = _doc;
    if (doc == null || _sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = await _buildPdf(PdfPageFormat.a4);
      await Printing.sharePdf(bytes: bytes, filename: 'facture-${doc.number}.pdf');
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text("Téléchargement impossible sur cet appareil. $error"),
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// The owner corrects the document: the server withdraws this invoice and
  /// issues a replacement in one transaction, and the screen lands on the new
  /// one. Offered only while nothing has been paid — after money has moved,
  /// the answer is a refund or credit note, and the server says so too.
  Future<void> _revise() async {
    final doc = _doc;
    if (doc == null) return;

    final newId = await context.push<String>(
      Routes.inside(widget.org.id, 'factures/corriger'),
      extra: doc,
    );
    if (newId != null && mounted) {
      context.pushReplacement(
          Routes.inside(widget.org.id, 'factures/$newId'));
    }
  }

  Future<void> _recordPayment() async {
    final doc = _doc;
    if (doc == null) return;
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _PaymentDialog(
        outstanding: doc.outstanding,
        money: moneyFormat(doc.currency),
      ),
    );
    if (amount == null || !mounted) return;

    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.invoicing.recordPayment(
        invoiceId: doc.id,
        amount: amount,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel() async {
    final doc = _doc;
    if (doc == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Annuler la facture ${doc.number} ?'),
        content: const Text(
          "L'écriture comptable sera contre-passée, pas effacée : la facture "
          'reste dans l’historique et la créance disparaît du bilan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler la facture'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.invoicing.cancel(doc.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      // The server refuses a part-paid invoice, and its message says why.
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc == null ? 'Facture' : 'Facture ${doc.number}'),
        actions: [
          if (doc != null)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Télécharger (PDF)',
              onPressed: _sharing ? null : _download,
            ),
          if (doc != null)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer',
              onPressed: _sharing ? null : _print,
            ),
          if (doc != null && _canWrite && !doc.isCancelled)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'payment') _recordPayment();
                if (v == 'revise') _revise();
                if (v == 'cancel') _cancel();
              },
              itemBuilder: (_) => [
                if (doc.outstanding > 0)
                  const PopupMenuItem(
                    value: 'payment',
                    child: Text('Enregistrer un paiement'),
                  ),
                // The owner's pen: withdraws this document and issues a
                // corrected one. Gone once money has arrived — from there the
                // path is a refund or credit note.
                if (widget.org.isAdmin && doc.paid == 0)
                  const PopupMenuItem(
                    value: 'revise',
                    child: Text('Modifier la facture'),
                  ),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text('Annuler la facture'),
                ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Failed(error: _error!, onRetry: _load)
              : Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                      child: Center(
                        // The boundary wraps only the paper, so what is shared
                        // is the document and not the app around it.
                        child: RepaintBoundary(
                          key: _paperKey,
                          child: InvoicePaper(doc: doc!),
                        ),
                      ),
                    ),
                    if (_working)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x33000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
      floatingActionButton: doc == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('Envoyer'),
            ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.outstanding, required this.money});

  final double outstanding;
  final NumberFormat money;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _controller =
      TextEditingController(text: widget.outstanding.round().toString());

  double get _amount =>
      double.tryParse(_controller.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // More than is owed is a typo, not a tip. Refusing it here means the
    // ledger never carries a negative receivable.
    final tooMuch = _amount > widget.outstanding;
    return AlertDialog(
      title: const Text('Paiement reçu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reste à payer : ${widget.money.format(widget.outstanding)}'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Montant',
              border: const OutlineInputBorder(),
              errorText: tooMuch ? 'Plus que ce qui est dû.' : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _amount > 0 && !tooMuch
              ? () => Navigator.pop(context, _amount)
              : null,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(describeError(error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

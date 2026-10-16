import 'package:flutter/material.dart';

import '../../core/export/file_out.dart';
import '../../core/export/report_export.dart';
import '../../core/l10n/tr.dart';

/// « Télécharger » on an accounting report (153): PDF or CSV (Excel), for
/// the period on screen. On the web a real download; on Android and iOS
/// the share sheet (save to Files, Drive, send) — as the invoice's PDF.
///
/// [build] makes the file's content from what the screen was given (it may
/// read the rest of a paged list first); null [build] — nothing loaded
/// yet, or no signal — greys the button.
class ReportDownloadButton extends StatefulWidget {
  const ReportDownloadButton({super.key, required this.build, this.csvOnly = false});

  final Future<ReportExport> Function()? build;

  /// The members' list: a table to sort, not a page to print.
  final bool csvOnly;

  @override
  State<ReportDownloadButton> createState() => _ReportDownloadButtonState();
}

class _ReportDownloadButtonState extends State<ReportDownloadButton> {
  bool _busy = false;

  Future<void> _go(String format) async {
    final build = widget.build;
    if (build == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final lang = trCurrent;
    try {
      final export = await build();
      final name = '${export.baseName}.$format';
      if (format == 'pdf') {
        await handOutFile(await export.toPdf(), filename: name, mime: 'application/pdf');
      } else {
        await handOutFile(export.csvBytes(), filename: name, mime: 'text/csv');
      }
      messenger.showSnackBar(SnackBar(content: Text(translate(lang, 'Fichier prêt : {name}', {'name': name}))));
    } catch (error) {
      messenger.showSnackBar(SnackBar(
          content: Text(translate(lang, 'Téléchargement impossible sur cet appareil. {error}', {'error': error}))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return PopupMenuButton<String>(
      key: const Key('report-download'),
      tooltip: context.tr('Télécharger'),
      enabled: widget.build != null,
      icon: const Icon(Icons.download_outlined),
      onSelected: _go,
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          height: 36,
          child: Text(context.tr('Télécharger'),
              style: Theme.of(context).textTheme.labelLarge),
        ),
        if (!widget.csvOnly)
          PopupMenuItem(
            key: const Key('download-pdf'),
            value: 'pdf',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(context.tr('PDF')),
              subtitle: Text(context.tr('Pour imprimer ou envoyer')),
            ),
          ),
        PopupMenuItem(
          key: const Key('download-csv'),
          value: 'csv',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(context.tr('CSV (Excel)')),
            subtitle: Text(context.tr('Pour un tableur')),
          ),
        ),
      ],
    );
  }
}

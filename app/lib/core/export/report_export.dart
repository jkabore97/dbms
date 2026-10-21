import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../association/members.dart' show foldText;
import '../format/money.dart';
import '../l10n/tr.dart';

/// An accounting report as a file (153): « Télécharger » › PDF or CSV.
///
/// The screen builds one of these from exactly what it was given by the
/// server — never more — so a summary observer, whose reports arrive as
/// totals only (006, income_statement, account_ledger…), downloads totals
/// only: the file cannot hold a line the screen was not sent.
///
/// CSV, for Excel (French Excel first): « ; » between fields, UTF-8 with a
/// BOM so the accents open right, CRLF line ends, amounts as plain numbers
/// in the business's money — its own decimals (144: none for the franc
/// CFA), a comma for the decimal mark, no thousands separator — and dates
/// ISO (2026-10-16). A short preamble names the report, the business, the
/// period, the day it was made and the money; then each section: its
/// title, its header, its rows and its totals. A text cell that starts
/// like a formula (= + - @) is written after a « ' » so a spreadsheet
/// never runs a name somebody typed.
///
/// PDF: A4 (on its side for a table wider than six columns), the business's name, the report's title, the period and the
/// day it was made at the top; each section a table, amounts in the
/// business's money as every screen writes them (moneyFormat, 140/144);
/// « Marakaj » and the page number at the foot of every page. Roboto is
/// embedded (assets/fonts) so every accent, « œ » and « — » prints.

/// One column: its title, and how its cells are written.
class ExportColumn {
  const ExportColumn(this.title, {this.money = false, this.date = false, this.number = false});
  final String title;
  final bool money;
  final bool date;

  /// A count (entries): written as a whole number.
  final bool number;
}

/// One table of the report.
class ExportSection {
  const ExportSection({
    this.title,
    required this.columns,
    this.rows = const [],
    this.totals = const [],
  });

  final String? title;
  final List<ExportColumn> columns;

  /// Cells: a String, a num (an amount, or a count), a DateTime, or null.
  final List<List<Object?>> rows;

  /// Rows drawn bold under the others.
  final List<List<Object?>> totals;
}

class ReportExport {
  ReportExport({
    required this.title,
    required this.fileStem,
    required this.orgName,
    required this.currency,
    required this.sections,
    this.from,
    this.to,
    this.asOf = false,
    DateTime? generatedAt,
    this.notice,
    String? lang,
  })  : generatedAt = generatedAt ?? DateTime.now(),
        lang = lang ?? trCurrent;

  final String title;

  /// The file's name before the business, the period and the extension:
  /// « compte-de-resultat ».
  final String fileStem;
  final String orgName;
  final String currency;
  final List<ExportSection> sections;

  /// The period on screen; null [from] is « since the beginning ».
  final DateTime? from;
  final DateTime? to;

  /// A position at a date (the balance sheet): « Au … » rather than a range.
  final bool asOf;
  final DateTime generatedAt;

  /// Said under the title — « Totaux seulement » for a summary reader.
  final String? notice;
  final String lang;

  String _t(String fr, [Map<String, Object?> args = const {}]) => translate(lang, fr, args);

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime get _end => to ?? generatedAt;

  /// « Du 1 octobre 2026 au 16 octobre 2026 », « Depuis le début, jusqu'au
  /// 16 octobre 2026 », « Au 16 octobre 2026 ».
  String get periodLabel {
    final f = DateFormat('d MMMM y', intlLocale(lang));
    if (asOf) return _t('Au {date}', {'date': f.format(_end)});
    if (from == null) return _t('Depuis le début, jusqu\'au {date}', {'date': f.format(_end)});
    return _t('Du {from} au {to}', {'from': f.format(from!), 'to': f.format(_end)});
  }

  String get generatedLabel => _t('Généré le {date}', {
        'date': DateFormat('d MMMM y, HH:mm', intlLocale(lang)).format(generatedAt),
      });

  /// « compte-de-resultat_cercle-horizon_2026-10-01_2026-10-16 ».
  String get baseName {
    final org = foldText(orgName).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final range = asOf
        ? iso(_end)
        : from == null
            ? 'tout_${iso(_end)}'
            : '${iso(from!)}_${iso(_end)}';
    return [fileStem, if (org.isNotEmpty) org, range].join('_');
  }

  // ----------------------------------------------------------------
  // CSV
  // ----------------------------------------------------------------

  static const bom = '﻿';

  /// The CSV as text (with its BOM); [csvBytes] is what is handed out.
  String toCsv() {
    final out = StringBuffer(bom);
    void line(List<String> cells) => out.write('${cells.map(_csvField).join(';')}\r\n');
    line([title, orgName]);
    line([
      _t('Période'),
      if (asOf) iso(_end) else (from == null ? '' : iso(from!)),
      if (!asOf) iso(_end),
    ]);
    line([_t('Généré le'), iso(generatedAt)]);
    line([_t('Monnaie'), currencySymbol(currency)]);
    if (notice != null) line([notice!]);
    for (final s in sections) {
      out.write('\r\n');
      if (s.title != null) line([s.title!]);
      line([
        for (final c in s.columns)
          c.money ? '${c.title} (${currencySymbol(currency)})' : c.title,
      ]);
      for (final r in [...s.rows, ...s.totals]) {
        line([for (var i = 0; i < s.columns.length; i++) _csvCell(s.columns[i], i < r.length ? r[i] : null)]);
      }
    }
    return out.toString();
  }

  Uint8List csvBytes() => Uint8List.fromList(utf8.encode(toCsv()));

  String _csvCell(ExportColumn c, Object? v) {
    if (v == null) return '';
    if (v is DateTime) return iso(v);
    if (v is num) {
      if (c.number) return v.round().toString();
      final decimals = currencyDecimals(currency);
      return v.toStringAsFixed(decimals).replaceAll('.', ',');
    }
    final s = '$v';
    // A typed name that starts like a formula is never run (CSV injection).
    // A phone number (« +226 70 00 00 01 ») or a plain signed number is not
    // one.
    if (RegExp(r'^[+\-][\d\s]+$').hasMatch(s)) return s;
    return RegExp(r'^[=+\-@\t\r]').hasMatch(s) ? "'$s" : s;
  }

  static String _csvField(String s) {
    if (s.contains(';') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  // ----------------------------------------------------------------
  // PDF
  // ----------------------------------------------------------------

  static ByteData? _regular, _bold;

  /// Roboto's bytes, once; false when the asset cannot be read (Helvetica
  /// then, with the few characters it lacks replaced).
  static Future<bool> _fonts() async {
    if (_regular != null && _bold != null) return true;
    try {
      _regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      _bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether [toPdf] lays the document out on a background isolate. On by
  /// default off the web (the web has one thread: compute() would run it
  /// in place anyway); a test may turn it off.
  @visibleForTesting
  static bool inBackground = !kIsWeb;

  /// Helvetica holds Latin-1 only.
  static String _latin1(String s) => s
      .replaceAll('œ', 'oe')
      .replaceAll('Œ', 'OE')
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll('…', '...')
      .replaceAll(RegExp('[  ]'), ' ')
      .replaceAll(RegExp(r'[^\u0000-ÿ]'), '?');

  String _money(num v) => moneyFormat(currency).format(v).replaceAll(' ', ' ');

  String _pdfCell(ExportColumn c, Object? v) {
    if (v == null) return '';
    if (v is DateTime) return DateFormat('dd/MM/y', intlLocale(lang)).format(v);
    if (v is num) return c.number ? '${v.round()}' : _money(v);
    return '$v';
  }

  /// [embedFonts] false and [compress] false: Helvetica and plain text
  /// streams, which a test can read.
  ///
  /// Laid out, its fonts subset and its pages compressed off the UI isolate
  /// (freeze audit): a year's journal is thousands of rows, and built in
  /// place it held every frame — the spinner of « Télécharger » included —
  /// for seconds on a phone, the whole app still until the file came.
  Future<Uint8List> toPdf({bool embedFonts = true, bool compress = true}) async {
    final embedded = embedFonts && await _fonts();
    final job = (
      export: this,
      regular: embedded ? _regular : null,
      bold: embedded ? _bold : null,
      compress: compress,
    );
    return inBackground ? compute(_render, job) : _render(job);
  }

  static Future<Uint8List> _render(
      ({ReportExport export, ByteData? regular, ByteData? bold, bool compress}) job) async {
    // A fresh isolate has no locale data yet: the dates are written in the
    // report's language as on the screen.
    await initializeDateFormatting();
    final regular = job.regular, bold = job.bold;
    return job.export._build(
      regular == null || bold == null ? null : (pw.Font.ttf(regular), pw.Font.ttf(bold)),
      job.compress,
    );
  }

  Future<Uint8List> _build((pw.Font, pw.Font)? fonts, bool compress) {
    final embedded = fonts != null;
    String t(String s) => embedded ? s : _latin1(s);
    final theme = embedded
        ? pw.ThemeData.withFont(base: fonts.$1, bold: fonts.$2)
        : pw.ThemeData.base();
    final doc = pw.Document(
        title: '$title — $orgName', author: orgName, creator: 'Marakaj', compress: compress);
    const ink = PdfColor.fromInt(0xFF1F2933);
    const soft = PdfColor.fromInt(0xFF5F6B7A);
    const band = PdfColor.fromInt(0xFFEFF2F5);
    doc.addPage(pw.MultiPage(
      theme: theme,
      // The package's default is 20 pages, past which it throws: a year's
      // journal (a few thousand lines) never downloaded at all.
      maxPages: 2000,
      // A wide table (the journal, a ledger) lies on its side.
      pageFormat: sections.any((x) => x.columns.length > 6) ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(t('$orgName · $title'),
                  style: const pw.TextStyle(fontSize: 8, color: soft)),
            ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(children: [
          pw.Text('Marakaj', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.SizedBox(width: 6),
          pw.Expanded(
              child: pw.Text(t(generatedLabel), style: const pw.TextStyle(fontSize: 8, color: soft))),
          pw.Text(t(_t('Page {n} sur {total}', {'n': ctx.pageNumber, 'total': ctx.pagesCount})),
              style: const pw.TextStyle(fontSize: 8, color: soft)),
        ]),
      ),
      build: (ctx) => [
        pw.Text(t(orgName), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.SizedBox(height: 4),
        pw.Text(t(title), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: ink)),
        pw.SizedBox(height: 2),
        pw.Text(t(periodLabel), style: const pw.TextStyle(fontSize: 10, color: ink)),
        pw.Text(t('${_t('Monnaie : {money}', {'money': currencySymbol(currency)})} · $generatedLabel'),
            style: const pw.TextStyle(fontSize: 8, color: soft)),
        if (notice != null) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            color: band,
            child: pw.Text(t(notice!), style: const pw.TextStyle(fontSize: 9, color: ink)),
          ),
        ],
        for (final s in sections) ...[
          pw.SizedBox(height: 14),
          if (s.title != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(t(s.title!.toUpperCase()),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: ink)),
            ),
          _table(s, t, ink, soft, band),
        ],
      ],
    ));
    return doc.save();
  }

  pw.Widget _table(ExportSection s, String Function(String) t, PdfColor ink, PdfColor soft, PdfColor band) {
    final right = <int, pw.Alignment>{
      for (var i = 0; i < s.columns.length; i++)
        if (s.columns[i].money || s.columns[i].number) i: pw.Alignment.centerRight,
    };
    pw.Widget cell(String text, int i, {bool bold = false, bool head = false}) => pw.Container(
          alignment: right[i] ?? pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(t(text),
              style: pw.TextStyle(
                fontSize: head ? 8 : 9,
                color: head ? soft : ink,
                fontWeight: bold || head ? pw.FontWeight.bold : pw.FontWeight.normal,
              )),
        );
    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < s.columns.length; i++)
        i: s.columns[i].money || s.columns[i].date || s.columns[i].number
            ? const pw.IntrinsicColumnWidth()
            : const pw.FlexColumnWidth(),
    };
    return pw.Table(
      columnWidths: widths,
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: band, width: 0.6)),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: band),
          repeat: true,
          children: [for (var i = 0; i < s.columns.length; i++) cell(s.columns[i].title, i, head: true)],
        ),
        for (final r in s.rows)
          pw.TableRow(children: [
            for (var i = 0; i < s.columns.length; i++)
              cell(_pdfCell(s.columns[i], i < r.length ? r[i] : null), i),
          ]),
        for (final r in s.totals)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColor.fromInt(0xFF9AA5B1), width: 0.8))),
            children: [
              for (var i = 0; i < s.columns.length; i++)
                cell(_pdfCell(s.columns[i], i < r.length ? r[i] : null), i, bold: true),
            ],
          ),
      ],
    );
  }
}

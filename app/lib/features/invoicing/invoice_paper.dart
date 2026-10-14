import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format/money_text.dart';
import '../../core/invoicing/models.dart';
import '../../core/theme/kaj_theme.dart';
import '../accounting/report_shell.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The invoice itself. Deliberately a white sheet with black text whatever the
/// business's palette is: this leaves the app and lands in somebody else's
/// chat, where it has to read as a document rather than as a screenshot.
class InvoicePaper extends StatelessWidget {
  const InvoicePaper({super.key, required this.doc});

  final InvoiceDocument doc;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(doc.currency);
    final date = DateFormat('d MMMM y', intlLocale());
    // The palette's ink, not a hero stop: the hero stops are pale washes for
    // painting behind text, and the invoice is dark type on white paper.
    final accent = KajTheme.of(context).ink;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: DefaultTextStyle(
        // The app's own face, in the paper's ink (I-1: a bare TextStyle
        // drew in whatever font was the default there).
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: const Color(0xFF1A1A1A), fontSize: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Who is billing, and the invoice's number and dates: side by
            // side on a wide sheet; on a phone's narrow one, one under the
            // other, so the business's name and address keep the sheet's
            // width instead of 17 px (UI audit I-1).
            LayoutBuilder(builder: (context, box) {
              final who = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.orgName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                  if ((doc.orgAddress ?? '').trim().isNotEmpty)
                    Text(doc.orgAddress!.trim()),
                  if ((doc.orgPhone ?? '').trim().isNotEmpty)
                    Text(context.tr('Tél. {phone}', {'phone': doc.orgPhone!.trim()})),
                  if ((doc.orgEmail ?? '').trim().isNotEmpty)
                    Text(doc.orgEmail!.trim()),
                  if (doc.taxLine != null) Text(doc.taxLine!),
                ],
              );
              final stacked = box.maxWidth < 340;
              final what = Column(
                key: const Key('invoice-head-number'),
                crossAxisAlignment:
                    stacked ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Text(context.tr('FACTURE'),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                  Text(context.tr('N° {number}', {'number': doc.number}),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(date.format(doc.issuedOn)),
                  if (doc.dueOn != null)
                    Text(context.tr('Échéance {date}', {'date': date.format(doc.dueOn!)})),
                ],
              );
              return stacked
                  ? Column(
                      key: const Key('invoice-head-stacked'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [who, const SizedBox(height: 14), what],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: who),
                        const SizedBox(width: 12),
                        Flexible(child: what),
                      ],
                    );
            }),

            if (doc.isCancelled) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                color: const Color(0xFFFDECEA),
                child: Text(
                  context.tr('FACTURE ANNULÉE'),
                  style: const TextStyle(
                    color: Color(0xFF8C1D18),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
            Text(context.tr('Facturé à'),
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
            Text(doc.customerName,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            if ((doc.customerAddress ?? '').trim().isNotEmpty)
              Text(doc.customerAddress!.trim()),
            if ((doc.customerPhone ?? '').trim().isNotEmpty)
              Text(doc.customerPhone!.trim()),

            const SizedBox(height: 20),
            _LineHeader(accent: accent),
            for (final line in doc.lines) _LineRow(line: line, money: money),

            const Divider(height: 24, color: Color(0xFFDDDDDD)),
            _Total(label: context.tr('Total'), value: money.format(doc.total), bold: true),
            if (doc.paid > 0) ...[
              _Total(label: context.tr('Déjà payé'), value: money.format(doc.paid)),
              _Total(
                label: context.tr('Reste à payer'),
                value: money.format(doc.outstanding),
                bold: true,
                colour: doc.outstanding > 0 ? const Color(0xFFB3261E) : null,
              ),
            ],
            if (doc.isPaid) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                color: const Color(0xFFE6F4EA),
                child: Text(
                  context.tr('PAYÉE'),
                  style: const TextStyle(
                    color: Color(0xFF1E6B3A),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],

            if ((doc.footer ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                doc.footer!.trim(),
                style: const TextStyle(fontSize: 12, color: Color(0xFF4A4A4A)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineHeader extends StatelessWidget {
  const _LineHeader({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: accent,
    );
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: accent, width: 1.5)),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(context.tr('DÉSIGNATION'), style: style)),
          Expanded(
              flex: 2,
              child: Text(context.tr('QTÉ'), style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 3,
              child: MoneyText('P.U.', style: style, alignment: Alignment.centerRight)),
          Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: MoneyText(context.tr('MONTANT'), style: style, alignment: Alignment.centerRight),
              )),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.money});

  final InvoiceLine line;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: Text(line.description)),
          Expanded(
            flex: 2,
            child: Text(_trim(line.quantity), textAlign: TextAlign.right),
          ),
          // Each amount whole on one line, shrunk rather than cut (144: at
          // 320 px × 1.3 « 18,90 BRL » broke into « 18,90 B / RL »).
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: MoneyText(money.format(line.unitPrice),
                  alignment: Alignment.centerRight),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: MoneyText(
                money.format(line.amount),
                alignment: Alignment.centerRight,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 12 rather than 12.0, but 12.5 stays 12.5.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    this.bold = false,
    this.colour,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: colour,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // The label gives way first (I-2).
          Flexible(child: Text(label, textAlign: TextAlign.right, style: style)),
          const SizedBox(width: 16),
          SizedBox(
            width: 130,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(value, maxLines: 1, textAlign: TextAlign.right, style: style),
            ),
          ),
        ],
      ),
    );
  }
}

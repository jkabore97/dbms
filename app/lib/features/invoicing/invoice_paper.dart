import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/invoicing/models.dart';
import '../../core/theme/kaj_theme.dart';
import '../accounting/report_shell.dart';

/// The invoice itself. Deliberately a white sheet with black text whatever the
/// business's palette is: this leaves the app and lands in somebody else's
/// chat, where it has to read as a document rather than as a screenshot.
class InvoicePaper extends StatelessWidget {
  const InvoicePaper({super.key, required this.doc});

  final InvoiceDocument doc;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(doc.currency);
    final date = DateFormat('d MMMM y', 'fr_FR');
    final accent = KajTheme.of(context).hero.first;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF1A1A1A), fontSize: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Who is billing.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
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
                        Text('Tél. ${doc.orgPhone!.trim()}'),
                      if ((doc.orgEmail ?? '').trim().isNotEmpty)
                        Text(doc.orgEmail!.trim()),
                      if (doc.taxLine != null) Text(doc.taxLine!),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('FACTURE',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                    Text('N° ${doc.number}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(date.format(doc.issuedOn)),
                    if (doc.dueOn != null)
                      Text('Échéance ${date.format(doc.dueOn!)}'),
                  ],
                ),
              ],
            ),

            if (doc.isCancelled) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                color: const Color(0xFFFDECEA),
                child: const Text(
                  'FACTURE ANNULÉE',
                  style: TextStyle(
                    color: Color(0xFF8C1D18),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
            const Text('Facturé à',
                style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
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
            _Total(label: 'Total', value: money.format(doc.total), bold: true),
            if (doc.paid > 0) ...[
              _Total(label: 'Déjà payé', value: money.format(doc.paid)),
              _Total(
                label: 'Reste à payer',
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
                child: const Text(
                  'PAYÉE',
                  style: TextStyle(
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
          Expanded(flex: 5, child: Text('DÉSIGNATION', style: style)),
          Expanded(
              flex: 2,
              child: Text('QTÉ', style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 3,
              child: Text('P.U.', style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 3,
              child: Text('MONTANT', style: style, textAlign: TextAlign.right)),
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
          Expanded(
            flex: 3,
            child:
                Text(money.format(line.unitPrice), textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text(
              money.format(line.amount),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
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
          Text(label, style: style),
          const SizedBox(width: 16),
          SizedBox(
            width: 130,
            child: Text(value, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

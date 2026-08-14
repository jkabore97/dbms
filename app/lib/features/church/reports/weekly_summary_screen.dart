import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/reports/models.dart';
import '../../../core/reports/reports_repository.dart';

/// The Sunday summary.
///
/// This is the accountability loop. The books get kept carefully because
/// somebody reads them on Sunday evening, and the person who reads them is in
/// a WhatsApp group, not in this app. So the report is built to leave: it is
/// laid out as a single card that renders to a PNG, because an image forwards
/// and a screenshot of a scrolling list does not.
///
/// The card is deliberately not the screen. What gets shared is a fixed-width
/// composition that reads the same on any phone it lands on, rather than
/// whatever happened to be visible on the sender's.
class WeeklySummaryScreen extends StatefulWidget {
  const WeeklySummaryScreen({
    super.key,
    required this.reports,
    required this.orgId,
    required this.orgName,
    this.currency = 'XOF',
    this.summaryOnly = false,
  });

  final ReportsRepository reports;
  final String orgId;
  final String orgName;
  final String currency;

  /// An observer granted 'summary' visibility sees the totals and not the
  /// lines behind them. See AppRoot, which reads this off the membership.
  final bool summaryOnly;

  @override
  State<WeeklySummaryScreen> createState() => _WeeklySummaryScreenState();
}

class _WeeklySummaryScreenState extends State<WeeklySummaryScreen> {
  final _cardKey = GlobalKey();

  WeeklySummary? _summary;
  DateTime _weekEnding = DateTime.now();
  bool _loading = true;
  bool _sharing = false;
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
      final summary = await widget.reports
          .weeklySummary(widget.orgId, weekEnding: _weekEnding);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loading = false;
      });
    }
  }

  void _shiftWeek(int days) {
    setState(() => _weekEnding = _weekEnding.add(Duration(days: days)));
    _load();
  }

  /// Paints the card offscreen at 3x and hands the PNG to the OS share sheet.
  ///
  /// 3x because the destination is WhatsApp, which re-compresses whatever it
  /// is given; a 1x capture arrives as a blur and a blurred financial report
  /// is worse than none.
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError("Le rapport n'est pas prêt.");

      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError("L'image n'a pas pu être créée.");

      final bytes = data.buffer.asUint8List();
      final label = DateFormat('yyyy-MM-dd').format(_weekEnding);

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: 'resume-$label.png',
            ),
          ],
          text: '${widget.orgName} — résumé de la semaine',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // Sharing a file is not available on every platform this build runs on;
      // on the web it depends on the browser. Say so rather than failing mute.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Le partage a échoué sur cet appareil. '
            "Faites une capture d'écran en attendant. "
            '(${AuthRepository.describeError(error)})',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Résumé de la semaine'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WeekPicker(
                  weekEnding: _weekEnding,
                  onShift: _shiftWeek,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  )
                else if (summary != null) ...[
                  Center(
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: SummaryCard(
                        summary: summary,
                        orgName: widget.orgName,
                        currency: widget.currency,
                        summaryOnly: widget.summaryOnly,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _sharing ? null : _share,
                      icon: _sharing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.share),
                      label: const Text(
                        'Partager (WhatsApp)',
                        style: TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      "Envoie une image du résumé — lisible sans l'application.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

/// The thing that actually gets shared.
///
/// Fixed width so the PNG is the same shape whatever phone rendered it, and
/// built from plain colours rather than theme surfaces so it does not come out
/// dark-on-dark for somebody running a dark theme.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.summary,
    required this.orgName,
    this.currency = 'XOF',
    this.summaryOnly = false,
  });

  final WeeklySummary summary;
  final String orgName;
  final String currency;
  final bool summaryOnly;

  static const _ink = Color(0xFF1B2B24);
  static const _muted = Color(0xFF5F6F68);
  static const _green = Color(0xFF2E5E4E);
  static const _orange = Color(0xFFB35309);

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: currency == 'XOF' ? 'FCFA' : currency,
      decimalDigits: 0,
    );
    final dates = DateFormat('d MMM', 'fr_FR');

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            orgName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Semaine du ${dates.format(summary.weekStarting)} '
            'au ${dates.format(summary.weekEnding)}',
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 20),

          _Total(
            label: 'Total reçu',
            amount: money.format(summary.totalIn),
            color: _green,
          ),
          const SizedBox(height: 10),
          _Total(
            label: 'Total dépensé',
            amount: money.format(summary.totalOut),
            color: _orange,
          ),

          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFE8EEEB)),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Solde de la semaine',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              Text(
                money.format(summary.net),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: summary.net >= 0 ? _green : _orange,
                ),
              ),
            ],
          ),

          // An observer on 'summary' visibility stops here. The totals are
          // the whole of what they were granted.
          if (!summaryOnly) ...[
            if (summary.income.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionHeading('Recettes'),
              ...summary.income.map(
                (l) => _Line(
                  label: l.displayLabel,
                  amount: money.format(l.amount),
                ),
              ),
            ],
            if (summary.expenses.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _SectionHeading('Dépenses'),
              ...summary.expenses.map(
                (l) => _Line(
                  label: l.displayLabel,
                  amount: money.format(l.amount),
                ),
              ),
            ],
          ],

          if (summary.isEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Rien enregistré cette semaine.',
              style: TextStyle(fontSize: 14, color: _muted),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'Kaj · ${DateFormat('d MMMM yyyy', 'fr_FR').format(DateTime.now())}',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: SummaryCard._muted,
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: SummaryCard._ink),
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SummaryCard._ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 15, color: SummaryCard._muted),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _WeekPicker extends StatelessWidget {
  const _WeekPicker({required this.weekEnding, required this.onShift});

  final DateTime weekEnding;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isThisWeek = DateTime.now().difference(weekEnding).inDays < 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () => onShift(-7),
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Semaine précédente',
        ),
        Text(
          isThisWeek
              ? 'Cette semaine'
              : 'Semaine au ${DateFormat('d MMMM', 'fr_FR').format(weekEnding)}',
          style: theme.textTheme.titleSmall,
        ),
        IconButton(
          // Never past today: a report for a week that has not happened is a
          // page of zeros that reads like a collapse in giving.
          onPressed: isThisWeek ? null : () => onShift(7),
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Semaine suivante',
        ),
      ],
    );
  }
}

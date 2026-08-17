import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import 'package:intl/intl.dart';

import '../../core/db/local_db.dart';

/// Closing the day.
///
/// This button records nothing about money. Everything it shows was already
/// true before it was tapped; what it adds is a person saying "I have looked
/// at today and it is right". That is the whole accountability loop in one
/// gesture, and the streak is there because a habit needs a reason to survive
/// the third week.
///
/// It works entirely offline, and the streak lives on the device. A count that
/// reset because a phone had no signal would be a lie about the person keeping
/// the books, not a fact about the books.
class CloseDaySheet extends StatefulWidget {
  const CloseDaySheet({
    super.key,
    required this.db,
    required this.orgId,
    required this.currency,
  });

  final LocalDb db;
  final String orgId;
  final String currency;

  @override
  State<CloseDaySheet> createState() => _CloseDaySheetState();
}

class _CloseDaySheetState extends State<CloseDaySheet> {
  double _moneyIn = 0;
  double _moneyOut = 0;
  int _entries = 0;
  int _pending = 0;
  int _streak = 0;
  bool _alreadyClosed = false;
  bool _loading = true;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final today = DateTime.now();
    final totals = await widget.db.dayTotals(widget.orgId, today);
    final entries = await widget.db.entriesForDay(widget.orgId, today);
    final pending = await widget.db.pendingCount();
    final streak = await widget.db.closureStreak(widget.orgId);
    final closed = await widget.db.isDayClosed(widget.orgId, today);

    if (!mounted) return;
    setState(() {
      _moneyIn = totals.moneyIn;
      _moneyOut = totals.moneyOut;
      _entries = entries.length;
      _pending = pending;
      _streak = streak;
      _alreadyClosed = closed;
      _loading = false;
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);

    await widget.db.closeDay(
      widget.orgId,
      DateTime.now(),
      moneyIn: _moneyIn,
      moneyOut: _moneyOut,
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.currency);

    // Closing again after a late entry updates the figures, so the streak
    // shown is what it will be once this tap lands.
    final streakAfter = _alreadyClosed ? _streak : _streak + 1;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: _loading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Center(
                  child: Text(
                    DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now()),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 20),

                _Row(
                  icon: Icons.arrow_downward,
                  color: Colors.green.shade700,
                  label: 'Reçu',
                  value: money.format(_moneyIn),
                ),
                const SizedBox(height: 12),
                _Row(
                  icon: Icons.arrow_upward,
                  color: Colors.orange.shade800,
                  label: 'Dépensé',
                  value: money.format(_moneyOut),
                ),
                const Divider(height: 28),
                _Row(
                  icon: Icons.functions,
                  color: theme.colorScheme.primary,
                  label: 'Solde du jour',
                  value: money.format(_moneyIn - _moneyOut),
                  emphasis: true,
                ),
                const SizedBox(height: 16),

                _Row(
                  icon: Icons.receipt_long_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                  label: 'Enregistrements',
                  value: '$_entries',
                ),
                const SizedBox(height: 12),

                // Never hidden, never softened. A person who is unsure whether
                // their work has left the device will enter it again.
                _Row(
                  icon: _pending == 0
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  color: _pending == 0
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  label: 'En attente d\'envoi',
                  value: _pending == 0 ? 'Tout est envoyé' : '$_pending',
                ),

                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          streakAfter <= 1
                              ? 'Premier jour clôturé'
                              : '$streakAfter jours clôturés d\'affilée',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _closing ? null : _close,
                    icon: _closing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _alreadyClosed
                          ? 'Mettre à jour la clôture'
                          : 'Clôturer la journée',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _alreadyClosed
                        ? 'Journée déjà clôturée — vous pouvez la revalider.'
                        : 'Fonctionne sans connexion',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyLarge),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasis ? 20 : 17,
            fontWeight: emphasis ? FontWeight.bold : FontWeight.w600,
            color: emphasis ? color : null,
          ),
        ),
      ],
    );
  }
}

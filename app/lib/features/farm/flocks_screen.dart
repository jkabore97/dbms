import 'package:flutter/material.dart';

import '../../core/theme/kaj_card.dart';
import 'farm_corrections.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../accounting/report_shell.dart';
import 'farm_animal_flows.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The batches, and how they are doing.
///
/// Three numbers per flock and they are in order of how early they warn.
///
///   * LAY RATE first. Eggs in the last seven days over birds alive times
///     seven. It moves days before the mortality does and weeks before the
///     money does, and it is the entire argument for making somebody count
///     eggs every single morning.
///   * ALIVE second, against how many arrived — the shape of the loss over the
///     batch's life, which a single "current count" column could never show.
///   * AGE last, because it is context for the other two rather than a
///     finding: a flock at 18 weeks that is not laying is a problem, and one
///     at 14 weeks that is not laying is simply 14 weeks old.
class FlocksScreen extends StatefulWidget {
  const FlocksScreen({
    super.key,
    required this.db,
    required this.org,
    this.farm,
  });

  final LocalDb db;
  final OrgSummary org;
  final FarmRepository? farm;

  @override
  State<FlocksScreen> createState() => _FlocksScreenState();
}

class _FlocksScreenState extends State<FlocksScreen> {
  List<Flock> _flocks = const [];
  bool _loading = true;
  bool _showClosed = false;
  Object? _error;

  bool get _canWrite => !widget.org.isObserverOnly;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final farm = widget.farm;
    if (farm == null || !farm.isConfigured) {
      setState(() {
        _loading = false;
        _error = StateError(
          "Cette version de l'application a été compilée sans serveur.",
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final flocks =
          await farm.flocks(widget.org.id, includeClosed: _showClosed);
      await widget.db.cacheFlocks(
        widget.org.id,
        flocks.map((f) => f.toCache()).toList(),
      );
      if (!mounted) return;
      setState(() {
        _flocks = flocks;
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

  /// « Ajouter des animaux » (115): a batch of birds is one of them. Opening
  /// it needs the server, unlike everything else Ignace records — the code
  /// has to be unique within the business, and two devices inventing
  /// "B-2026-01" offline would split one batch's figures in half.
  Future<void> _openFlock() async {
    final farm = widget.farm;
    if (farm == null) return;
    final added =
        await FarmAnimalFlow.add(context, db: widget.db, org: widget.org, farm: farm);
    if (added == true && mounted) await _load();
  }

  /// Mortality, a weighing, a vaccination, birds sold — offline (115).
  Future<void> _record(Flock flock) async {
    final recorded = await FarmAnimalFlow.flockEvent(context,
        db: widget.db, org: widget.org, flock: flock);
    if (recorded == true && mounted) await _load();
  }

  Future<void> _close(Flock flock) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Clôturer {batchCode} ?', {'batchCode': flock.batchCode})),
        content: Text(
          context.tr('La bande disparaît de l\'écran d\'accueil et garde tout son historique. Rien n\'est supprimé.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Retour')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('Clôturer')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.farm!.closeFlock(flock.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('La bande n\'a pas pu être clôturée.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Bandes')),
        actions: [
          IconButton(
            tooltip: _showClosed
                ? context.tr('Masquer les bandes clôturées')
                : context.tr('Afficher les bandes clôturées'),
            icon: Icon(_showClosed ? Icons.visibility_off : Icons.history),
            onPressed: () {
              setState(() => _showClosed = !_showClosed);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              onPressed: _openFlock,
              icon: const Icon(Icons.add),
              label: Text(context.tr('Ajouter des animaux')),
            )
          : null,
      body: ReportBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        isEmpty: _flocks.isEmpty,
        emptyMessage: widget.org.visibility == 'summary'
            ? context.tr('Votre accès porte sur les totaux. Le détail des bandes ne vous est pas communiqué.')
            : context.tr('Aucune bande ouverte.'),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final flock in _flocks)
              _FlockCard(
                flock: flock,
                canWrite: _canWrite,
                onRecord: () => _record(flock),
                onClose: () => _close(flock),
                onCorrect: widget.farm == null
                    ? null
                    : () => showFarmCorrections(
                          context,
                          title: flock.batchCode,
                          farm: widget.farm!,
                          kind: FarmEntryKind.flock,
                          subjectId: flock.id,
                          canWrite: true,
                        ),
              ),
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }
}

class _FlockCard extends StatelessWidget {
  const _FlockCard({
    required this.flock,
    required this.canWrite,
    required this.onRecord,
    required this.onClose,
    this.onCorrect,
  });

  final Flock flock;
  final bool canWrite;
  final VoidCallback onRecord;
  final VoidCallback onClose;

  /// Null in a build with no server — corrections read and write the server.
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A few percent over a whole cycle is ordinary. The figure earns colour
    // when it is not, and not before — an alarm that is always on is furniture.
    final worrying = flock.mortalityRate > 0.05;

    return KajCard(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        flock.batchCode,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        [
                          if (flock.breed != null) flock.breed!,
                          '${flock.ageDays} jours',
                          'arrivée ${DateFormat('d MMM y', 'fr_FR').format(flock.arrivedOn)}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!flock.isOpen)
                  Chip(
                    label: Text(context.tr('clôturée')),
                    visualDensity: VisualDensity.compact,
                    labelStyle: theme.textTheme.bodySmall,
                  )
                else if (canWrite)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'record') onRecord();
                      if (v == 'close') onClose();
                      if (v == 'correct') onCorrect?.call();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'record',
                        child: Text(context.tr('Enregistrer un événement')),
                      ),
                      if (onCorrect != null)
                        PopupMenuItem(
                          value: 'correct',
                          child: Text(context.tr('Corriger une entrée')),
                        ),
                      PopupMenuItem(
                          value: 'close', child: Text(context.tr('Clôturer'))),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: context.tr('Ponte (7 j)'),
                    value: flock.layRateLabel,
                    hint: '${flock.eggs7d} œufs',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: context.tr('Vivants'),
                    value: '${flock.alive}',
                    hint: 'sur ${flock.started}',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: context.tr('Morts'),
                    value: '${flock.died}',
                    hint: '${(flock.mortalityRate * 100).toStringAsFixed(1)} %',
                    tint: worrying ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
            if (flock.isOpen && canWrite) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.tr('Mortalité, pesée, vaccination')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.hint,
    this.tint,
  });

  final String label;
  final String value;
  final String hint;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          value,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold, color: tint),
        ),
        Text(
          hint,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

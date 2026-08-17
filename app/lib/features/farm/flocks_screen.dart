import 'package:flutter/material.dart';
import 'farm_corrections.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/farm/farm_repository.dart';
import '../../core/farm/models.dart';
import '../accounting/report_shell.dart';
import 'farm_sheets.dart';

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

  /// Opening a batch needs the server, unlike everything else Ignace records.
  ///
  /// The batch code has to be unique within the business: two devices
  /// inventing "B-2026-01" while offline would produce one flock with two
  /// histories that no report could add back together. Better to ask for
  /// signal once, when a batch arrives, than to let a whole cycle's figures
  /// split in half.
  Future<void> _openFlock() async {
    final result =
        await showModalBottomSheet<({String code, int count, String? breed})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewFlockSheet(),
    );
    if (result == null) return;

    try {
      await widget.farm!.openFlock(
        orgId: widget.org.id,
        batchCode: result.code,
        birdCount: result.count,
        breed: result.breed,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      final text = error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.contains('duplicate') || text.contains('unique')
                ? 'Une bande porte déjà ce code.'
                : "La bande n'a pas pu être ouverte. Vérifiez le réseau.",
          ),
        ),
      );
    }
  }

  Future<void> _record(Flock flock) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FlockEventSheet(
        db: widget.db,
        orgId: widget.org.id,
        flockId: flock.id,
        batchCode: flock.batchCode,
        alive: flock.alive,
      ),
    );
    if (recorded == true) await _load();
  }

  Future<void> _close(Flock flock) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clôturer ${flock.batchCode} ?'),
        content: const Text(
          "La bande disparaît de l'écran d'accueil et garde tout son "
          "historique. Rien n'est supprimé.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clôturer'),
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
        const SnackBar(content: Text("La bande n'a pas pu être clôturée.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandes'),
        actions: [
          IconButton(
            tooltip: _showClosed
                ? 'Masquer les bandes clôturées'
                : 'Afficher les bandes clôturées',
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
              label: const Text('Bande'),
            )
          : null,
      body: ReportBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        isEmpty: _flocks.isEmpty,
        emptyMessage: widget.org.visibility == 'summary'
            ? 'Votre accès porte sur les totaux. Le détail des bandes ne vous '
                'est pas communiqué.'
            : 'Aucune bande ouverte.',
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

    return Card(
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
                    label: const Text('clôturée'),
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
                      const PopupMenuItem(
                        value: 'record',
                        child: Text('Enregistrer un événement'),
                      ),
                      if (onCorrect != null)
                        const PopupMenuItem(
                          value: 'correct',
                          child: Text('Corriger une entrée'),
                        ),
                      const PopupMenuItem(
                          value: 'close', child: Text('Clôturer')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Ponte (7 j)',
                    value: flock.layRateLabel,
                    hint: '${flock.eggs7d} œufs',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Vivants',
                    value: '${flock.alive}',
                    hint: 'sur ${flock.started}',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Morts',
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
                  label: const Text('Mortalité, pesée, vaccination'),
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

class _NewFlockSheet extends StatefulWidget {
  const _NewFlockSheet();

  @override
  State<_NewFlockSheet> createState() => _NewFlockSheetState();
}

class _NewFlockSheetState extends State<_NewFlockSheet> {
  final _codeController = TextEditingController();
  final _countController = TextEditingController();
  final _breedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // A default that is already unique and already sorts correctly. Somebody
    // naming batches by hand will invent a scheme; somebody who does not want
    // to should not have to.
    final now = DateTime.now();
    _codeController.text =
        'B-${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _countController.dispose();
    _breedController.dispose();
    super.dispose();
  }

  int get _count => int.tryParse(_countController.text.trim()) ?? 0;
  bool get _valid => _count > 0 && _codeController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nouvelle bande', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Demande le réseau : le code doit être unique dans toute '
            "l'activité.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Code de la bande',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _countController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Nombre d'oiseaux à l'arrivée",
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _breedController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Race (facultatif)',
              hintText: 'Isa Brown',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _valid
                  ? () => Navigator.pop(context, (
                        code: _codeController.text.trim(),
                        count: _count,
                        breed: _breedController.text.trim().isEmpty
                            ? null
                            : _breedController.text.trim(),
                      ))
                  : null,
              child: const Text('Ouvrir la bande'),
            ),
          ),
        ],
      ),
    );
  }
}

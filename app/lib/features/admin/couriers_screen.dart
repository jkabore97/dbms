import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/courier/courier_dossier.dart';
import '../../core/nav/router.dart';
import '../courier/courier_words.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The platform decides who carries (056). Dossiers first (112): « À
/// valider » — sent and waiting, oldest first, each opening its review
/// page — then « À corriger », sent back and waiting on the applicant;
/// then every courier with the two verbs of before — approve, suspend —
/// because handing a stranger goods, addresses and phone numbers is
/// exactly the kind of power that must pass through a person. A courier
/// who registered before dossiers existed keeps « Approuver » here.
class CouriersScreen extends StatefulWidget {
  const CouriersScreen({super.key, required this.admin, this.dossier, this.files});

  final AdminRepository admin;

  /// The dossiers (112); null on a build that has none.
  final CourierDossierRepository? dossier;

  /// The dossiers' photos: what is due is deleted as the page opens.
  final CourierFiles? files;

  @override
  State<CouriersScreen> createState() => _CouriersScreenState();
}

class _CouriersScreenState extends State<CouriersScreen> {
  List<PlatformCourier> _rows = const [];
  List<CourierApplicationRow> _dossiers = const [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    // 30 days after a refusal (and a replaced photo, an unfinished one…),
    // the bytes go now — the platform opening its couriers is the moment.
    final files = widget.files;
    if (files != null) unawaited(files.purge());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.admin.platformCouriers();
      final dossiers = await _applications();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _dossiers = dossiers;
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

  /// The dossiers, or none on a database before 112.
  Future<List<CourierApplicationRow>> _applications() async {
    final repo = widget.dossier;
    if (repo == null) return const [];
    try {
      return await repo.applications();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const [];
      rethrow;
    }
  }

  Future<void> _decide(PlatformCourier row, String status) async {
    setState(() => _busyId = row.userId);
    try {
      await widget.admin.decideCourier(row.userId, status);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthRepository.describeError(error))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _open(String userId) async {
    await context.push(Routes.consoleCourierFile(userId));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = _dossiers.where((d) => d.status == 'pending').toList();
    final toFix = _dossiers.where((d) => d.status == 'refused').toList();
    final withDossier = {for (final d in _dossiers) d.userId};
    final waitingIds = {for (final d in waiting) d.userId};
    // A courier whose dossier waits is reviewed there, not approved here.
    final others = _rows.where((r) => !waitingIds.contains(r.userId)).toList();
    final pending = others.where((r) => r.status == 'pending').length + waiting.length;
    final date = DateFormat('d MMM', Localizations.localeOf(context).toString());

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Livreurs')),
        actions: [
          // What each courier owes for the month (067).
          IconButton(
            tooltip: context.tr('Règlement du mois'),
            onPressed: () => context.push(Routes.consoleSettlement),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: _load, child: Text(context.tr('Réessayer'))),
                      ],
                    ),
                  ),
                )
              : _rows.isEmpty && _dossiers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          context.tr('Personne n\'a encore demandé à devenir livreur. La demande se fait depuis « Devenir livreur », au pied de la page des vitrines.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        Text(
                          'Un livreur approuvé voit les livraisons prêtes, '
                          'les adresses et les numéros des clients. '
                          '$pending inscription${pending > 1 ? 's' : ''} en attente.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (waiting.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(context.tr('À valider'),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          for (final d in waiting)
                            KajCard(
                              key: Key('dossier-${d.userId}'),
                              child: ListTile(
                                leading: Icon(courierVehicleIcon(d.vehicle)),
                                title: Text(d.name),
                                subtitle: Text([
                                  courierVehicleLabel(context, d.vehicle),
                                  if (d.city != null) d.city!,
                                  if (d.sentAt != null)
                                    context.tr('envoyée le {date}', {'date': date.format(d.sentAt!)}),
                                ].join(' · ')),
                                trailing: FilledButton(
                                  onPressed: () => _open(d.userId),
                                  child: Text(context.tr('Examiner')),
                                ),
                                onTap: () => _open(d.userId),
                              ),
                            ),
                        ],
                        if (toFix.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(context.tr('À corriger par le livreur'),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          for (final d in toFix)
                            KajCard(
                              key: Key('dossier-${d.userId}'),
                              child: ListTile(
                                leading: const Icon(Icons.edit_note),
                                title: Text(d.name),
                                subtitle: Text([
                                  courierReasonLabel(context, d.refusalReason),
                                  if (d.decidedAt != null) date.format(d.decidedAt!),
                                ].join(' · ')),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(d.userId),
                              ),
                            ),
                        ],
                        if (others.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          if (_dossiers.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(context.tr('Livreurs'),
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            ),
                          for (final row in others)
                            KajCard(
                              child: ListTile(
                                leading: Icon(
                                  switch (row.status) {
                                    'approved' => Icons.verified_outlined,
                                    'suspended' => Icons.block_outlined,
                                    _ => Icons.hourglass_top_outlined,
                                  },
                                  color: row.status == 'approved'
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                title: Text(row.name),
                                subtitle: Text(
                                  '${row.phone ?? 'Sans numéro'} · '
                                  '${switch (row.status) {
                                    'approved' => 'Approuvé',
                                    'suspended' => 'Suspendu',
                                    _ => 'En attente',
                                  }} · '
                                  'inscrit le ${date.format(row.createdAt)}',
                                ),
                                // A courier with a dossier: it opens from here.
                                onTap: withDossier.contains(row.userId) ? () => _open(row.userId) : null,
                                trailing: _busyId == row.userId
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : row.status == 'approved'
                                        ? TextButton(
                                            onPressed: () =>
                                                _decide(row, 'suspended'),
                                            style: TextButton.styleFrom(
                                                foregroundColor:
                                                    theme.colorScheme.error),
                                            child: Text(context.tr('Suspendre')),
                                          )
                                        : FilledButton(
                                            onPressed: () =>
                                                _decide(row, 'approved'),
                                            child: Text(context.tr('Approuver')),
                                          ),
                              ),
                            ),
                        ],
                      ],
                    ),
    );
  }
}

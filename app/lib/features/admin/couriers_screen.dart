import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';

/// The platform decides who carries (056). Applications first; a switch of
/// two verbs per row — approve, suspend — because handing a stranger goods,
/// addresses and phone numbers is exactly the kind of power that must pass
/// through a person.
class CouriersScreen extends StatefulWidget {
  const CouriersScreen({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<CouriersScreen> createState() => _CouriersScreenState();
}

class _CouriersScreenState extends State<CouriersScreen> {
  List<PlatformCourier> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _busyId;

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
      final rows = await widget.admin.platformCouriers();
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = _rows.where((r) => r.status == 'pending').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Livreurs'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
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
                            onPressed: _load, child: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : _rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          "Personne ne s'est encore inscrit comme livreur. "
                          "L'inscription se fait depuis l'espace livreur "
                          'de la page des vitrines.',
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
                        const SizedBox(height: 12),
                        for (final row in _rows)
                          Card(
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
                                'inscrit le ${DateFormat('d MMM', Localizations.localeOf(context).toString()).format(row.createdAt)}',
                              ),
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
                                          child: const Text('Suspendre'),
                                        )
                                      : FilledButton(
                                          onPressed: () =>
                                              _decide(row, 'approved'),
                                          child: const Text('Approuver'),
                                        ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

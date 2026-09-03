import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/format/money.dart';

/// The paid spots on the welcome page — "à la une" — chosen by the platform.
///
/// Every article currently in a window is listed with its shop; a switch
/// puts it à la une for thirty days or takes it down. The money changes
/// hands outside the app for now (a shop pays the platform, the platform
/// flips the switch); what the app guarantees is that only the platform can
/// flip it (054) and that a spot ends by itself when its date passes.
class FeaturedScreen extends StatefulWidget {
  const FeaturedScreen({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<FeaturedScreen> createState() => _FeaturedScreenState();
}

class _FeaturedScreenState extends State<FeaturedScreen> {
  List<FeaturedCandidate> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  /// How long a spot runs when switched on. One month is what a shop can
  /// reason about and pay for; a finer choice can come when it is asked for.
  static const _spot = Duration(days: 30);

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
      final rows = await widget.admin.featuredCandidates();
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

  Future<void> _toggle(FeaturedCandidate row, bool on) async {
    setState(() => _busyId = row.productId);
    try {
      await widget.admin.setProductFeatured(
          row.productId, on ? DateTime.now().add(_spot) : null);
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
    final live = _rows.where((r) => r.live).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('À la une'),
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
                          'Aucun article en vitrine pour le moment. '
                          'Une boutique doit ouvrir sa vitrine et y afficher '
                          "des articles avant qu'ils puissent passer à la une.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        Text(
                          'Les articles cochés apparaissent sur la page '
                          "d'accueil, toutes boutiques confondues, pendant "
                          '30 jours. $live à la une en ce moment.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        for (final row in _rows)
                          Card(
                            child: SwitchListTile(
                              value: row.live,
                              onChanged: _busyId != null
                                  ? null
                                  : (on) => _toggle(row, on),
                              title: Text(row.name),
                              subtitle: Text(
                                '${row.shopName} · '
                                '${moneyFormat(row.currency).format(row.price)}'
                                '${row.live ? " · jusqu'au ${DateFormat('d MMMM', Localizations.localeOf(context).toString()).format(row.featuredUntil!)}" : ''}',
                              ),
                              secondary: Icon(
                                row.live ? Icons.star : Icons.star_outline,
                                color: row.live
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

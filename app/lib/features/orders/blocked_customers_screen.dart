import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/retail/fraud_guards.dart';
import '../../core/theme/app_bar_title.dart';
import '../../core/theme/kaj_card.dart';

/// « Clients bloqués » (batch 151): the shoppers this business no longer
/// takes orders from, each with « Débloquer ». The same page for a shop, a
/// farm and an association. Its admins only (the server's RLS says so too).
class BlockedCustomersScreen extends StatefulWidget {
  const BlockedCustomersScreen({super.key, required this.org, required this.guards});

  final OrgSummary org;
  final FraudGuardsRepository guards;

  static Route<void> route(OrgSummary org, FraudGuardsRepository guards) =>
      MaterialPageRoute(builder: (_) => BlockedCustomersScreen(org: org, guards: guards));

  @override
  State<BlockedCustomersScreen> createState() => _BlockedCustomersScreenState();
}

class _BlockedCustomersScreenState extends State<BlockedCustomersScreen> {
  List<BlockedCustomer> _rows = const [];
  bool _loading = true;
  bool _missing = false;
  String? _error;
  String? _busy;

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
      final rows = await widget.guards.blockedCustomers(widget.org.id);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _missing = isGuardMissing(error);
        _error = _missing ? null : describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _unblock(BlockedCustomer c) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('{name} peut de nouveau commander chez vous.', {'name': _name(c)});
    setState(() => _busy = c.customerId);
    try {
      await widget.guards.unblockCustomer(widget.org.id, c.customerId);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _name(BlockedCustomer c) => c.name.isEmpty ? context.tr('Client') : c.name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('d MMM y', context.trLocale);
    return Scaffold(
      appBar: AppBar(title: AppBarTitle(context.tr('Clients bloqués')), actions: [bellRoom]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  context.tr(
                      'Un client bloqué ne peut plus commander chez vous. Il n\'est pas prévenu : votre vitrine lui dit seulement qu\'elle ne prend pas sa commande pour le moment.'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (_missing)
                  Text(context.tr('Bloquer un client arrive avec la prochaine mise à jour du serveur.'),
                      key: const Key('blocked-missing'))
                else if (_error != null) ...[
                  Text(_error!),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                  ),
                ] else if (_rows.isEmpty)
                  Text(
                    context.tr('Aucun client bloqué. « Bloquer ce client » est dans le menu ⋮ d\'une commande.'),
                    key: const Key('blocked-empty'),
                  )
                else
                  for (final c in _rows)
                    KajCard(
                      key: Key('blocked-${c.customerId}'),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 8,
                          spacing: 8,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 160),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_name(c),
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700)),
                                  if (c.blockedAt != null)
                                    Text(context.tr('Bloqué le {date}', {'date': date.format(c.blockedAt!)}),
                                        style: theme.textTheme.bodySmall),
                                  if ((c.reason ?? '').isNotEmpty)
                                    Text(c.reason!, style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              key: Key('unblock-${c.customerId}'),
                              onPressed: _busy == null ? () => _unblock(c) : null,
                              child: Text(context.tr('Débloquer')),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

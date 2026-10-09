import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/plan_terms.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/console/command_center.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../cauris/cauri_icon.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The platform's cauris (084): the rules — what each act earns, and its
/// daily cap — changed here, never by a deploy; and the week's top earners,
/// each with the share of its orders that came from one customer, flagged
/// when that share is the shape of an abuse.
class CaurisConsoleCard extends StatefulWidget {
  const CaurisConsoleCard({super.key, required this.cauris});

  final CaurisRepository cauris;

  @override
  State<CaurisConsoleCard> createState() => _CaurisConsoleCardState();
}

class _CaurisConsoleCardState extends State<CaurisConsoleCard> {
  List<CaurisRule> _rules = const [];
  List<CaurisWatchRow> _watch = const [];
  List<({String feature, int cost, int minDays})> _costs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await widget.cauris.rules();
      final watch = await widget.cauris.watch();
      final costs = await widget.cauris.costs();
      if (!mounted) return;
      setState(() {
        _costs = costs;
        _rules = rules;
        _watch = watch;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit(CaurisRule rule) async {
    final points = TextEditingController(text: '${rule.points}');
    final cap = TextEditingController(
        text: rule.dailyCap == null ? '' : '${rule.dailyCap}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // The keyboard up on a small phone: the dialog scrolls (A6).
        scrollable: true,
        title: Text(rule.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('rule-points'),
              controller: points,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(labelText: context.tr('Cauris')),
            ),
            TextField(
              controller: cap,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: context.tr('Par jour au plus (vide : sans limite)')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Enregistrer'))),
        ],
      ),
    );
    if (ok != true) return;
    final p = int.tryParse(points.text.trim());
    if (p == null) return;
    try {
      await widget.cauris.setRule(rule.key, p,
          dailyCap: int.tryParse(cap.text.trim()));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  /// A tool's price, and the days a new business waits before cauris
  /// open it (108) — accounting and tontines wait so their books mean
  /// something; a photo slot never waits.
  Future<void> _editCost(String feature, int cost, int minDays) async {
    final c = TextEditingController(text: '$cost');
    final d = TextEditingController(text: '$minDays');
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('Prix enregistré.');
    final undoLabel = context.tr('Annuler');
    final client = AppScope.read(context)?.auth.client;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // The keyboard up on a small phone: the dialog scrolls (A6).
        scrollable: true,
        title: Text(context.tr('Prix en cauris')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('cost-value'),
              controller: c,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.tr('Cauris, pour 30 jours')),
            ),
            if (feature != 'photo_slot')
              TextField(
                key: const Key('cost-wait'),
                controller: d,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('Attente, en jours'),
                  helperText: context.tr('Jours sur Mara avant de pouvoir l\'acheter. 0 : dès le premier jour.'),
                  helperMaxLines: 3,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Enregistrer'))),
        ],
      ),
    );
    final v = int.tryParse(c.text.trim());
    final wait = feature == 'photo_slot' ? 0 : int.tryParse(d.text.trim());
    if (ok != true || v == null || wait == null) return;
    try {
      final id = await widget.cauris.setCost(feature, v, minDays: wait);
      await _load();
      // Journaled (108): « Annuler » takes it back, as in the Journal.
      messenger.showSnackBar(SnackBar(
        content: Text(saved),
        action: id == null || client == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () async {
                  try {
                    await CommandCenterRepository(client).undo(id);
                    await _load();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
                  }
                },
              ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const CauriIcon(size: 22),
            const SizedBox(width: 8),
            Text(context.tr('Cauris'), style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('Ce que chaque action rapporte. Une valeur changée vaut pour les prochaines ; rien de déjà gagné ne bouge.'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        // The platform's gifts (100): to any business, by name.
        OutlinedButton.icon(
          key: const Key('cauris-gifts'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => context.push(Routes.consoleCaurisGifts),
          icon: const Icon(Icons.redeem_outlined),
          label: Text(context.tr('Offrir à une entreprise')),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const LinearProgressIndicator()
        else if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error))
        else ...[
          for (final r in _rules)
            ListTile(
              key: Key('rule-${r.key}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(r.label),
              subtitle:
                  r.dailyCap == null ? null : Text(context.tr('au plus {dailyCap} par jour', {'dailyCap': r.dailyCap})),
              trailing: Text(r.points > 0 ? context.tr('+{points}', {'points': r.points}) : context.tr('{points}', {'points': r.points}),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => _edit(r),
            ),
          if (_costs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(context.tr('Prix des outils, pour 30 jours'), style: theme.textTheme.titleSmall),
            for (final c in _costs)
              ListTile(
                key: Key('cost-${c.feature}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(c.feature == 'pro_all'
                    ? context.tr('Mara Pro complet')
                    : PlanTerms.labelOf(c.feature)),
                subtitle: c.minDays > 0
                    ? Text(context.tr('après {minDays} jours sur Mara', {'minDays': c.minDays}))
                    : null,
                trailing: CaurisAmount(c.cost,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => _editCost(c.feature, c.cost, c.minDays),
              ),
          ],
          const SizedBox(height: 12),
          Text(context.tr('Les plus gros gains de la semaine'),
              style: theme.textTheme.titleSmall),
          if (_watch.isEmpty)
            Text(context.tr('Personne n\'a encore gagné de cauris cette semaine.'),
                style: theme.textTheme.bodySmall)
          else
            for (final w in _watch)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: w.suspicious
                    ? Icon(Icons.flag_outlined,
                        color: theme.colorScheme.error,
                        semanticLabel: 'À vérifier')
                    : null,
                title: Text(w.orgName),
                subtitle: Text('${w.orders} commandes comptées · '
                    '${(w.topCustomerShare * 100).round()} % d\'un seul client'),
                trailing: Text(context.tr('+{week}', {'week': w.week}),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
        ],
      ],
    );
  }
}

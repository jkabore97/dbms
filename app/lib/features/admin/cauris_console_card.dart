import 'package:flutter/material.dart';

import '../../core/cauris/cauris_repository.dart';
import '../../core/errors.dart';
import '../cauris/cauri_icon.dart';

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
      if (!mounted) return;
      setState(() {
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
        title: Text(rule.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('rule-points'),
              controller: points,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(labelText: 'Cauris'),
            ),
            TextField(
              controller: cap,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Par jour au plus (vide : sans limite)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer')),
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
            Text('Cauris', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Ce que chaque action rapporte. Une valeur changée vaut pour les '
          'prochaines ; rien de déjà gagné ne bouge.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  r.dailyCap == null ? null : Text('au plus ${r.dailyCap} par jour'),
              trailing: Text(r.points > 0 ? '+${r.points}' : '${r.points}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => _edit(r),
            ),
          const SizedBox(height: 12),
          Text('Les plus gros gains de la semaine',
              style: theme.textTheme.titleSmall),
          if (_watch.isEmpty)
            Text('Personne n\'a encore gagné de cauris cette semaine.',
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
                trailing: Text('+${w.week}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
        ],
      ],
    );
  }
}

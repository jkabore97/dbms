import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The platform's figures (072), under « À faire » in the command center
/// (104): what came in this month, are we growing, what is unwell — and a
/// word to every business. What must be done is « À faire »'s own count
/// above it (105's platform_todo), each number opening its screen.
class ConsoleToday extends StatefulWidget {
  const ConsoleToday({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<ConsoleToday> createState() => ConsoleTodayState();
}

class ConsoleTodayState extends State<ConsoleToday> {
  PlatformToday? _today;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final today = await widget.admin.platformToday();
      if (!mounted) return;
      setState(() {
        _today = today;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _write() async {
    final sent = await showDialog<int>(
      context: context,
      builder: (_) => _MessageDialog(admin: widget.admin),
    );
    if (sent != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sent > 1
              ? context.tr('Message envoyé à {n} personnes.', {'n': sent})
              : context.tr('Message envoyé à {n} personne.', {'n': sent}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    if (!_loaded || today == null) return const SizedBox.shrink();
    final n = NumberFormat.decimalPattern('fr_FR');
    final money = moneyFormat('XOF');
    final m = today.money, g = today.growth, h = today.health;
    int c(Map<String, num> b, String k) => today.count(b, k);

    final week = c(g, 'orders_week'), last = c(g, 'orders_last_week');
    final trend = week == last
        ? context.tr('comme la semaine dernière')
        : week > last
            ? context.tr('{n} sur la semaine dernière', {'n': '+${week - last}'})
            : context.tr('{n} sur la semaine dernière', {'n': '${week - last}'});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading('Ce mois',
            trailing: context.tr('gagné {amount}', {'amount': money.format(today.earnedMonth)})),
        _Figures([
          _Figure('Mara Pro', money.format(m['pro'] ?? 0)),
          _Figure('Mises en avant', money.format(m['spots'] ?? 0)),
          _Figure('Part livraison', money.format(m['delivery_cut'] ?? 0)),
          _Figure('Vendu par les vitrines', money.format(m['shops_sold'] ?? 0)),
        ]),
        const SizedBox(height: 16),
        const _Heading('Croissance'),
        _Figures([
          _Figure('Entreprises', n.format(c(g, 'businesses')),
              note: context.tr('+{n} ce mois', {'n': c(g, 'new_month')})),
          _Figure('Vitrines garnies', n.format(c(g, 'windows_stocked')),
              note: context.tr('sur {n} ouvertes', {'n': c(g, 'windows_open')})),
          _Figure('Commandes, 7 jours', n.format(week), note: trend),
          _Figure('Nouveaux clients', n.format(c(g, 'shoppers_new')),
              note: 'ce mois'),
          _Figure('Vitrines visitées', n.format(c(g, 'windows_opened_week')),
              note: '7 jours'),
        ]),
        const SizedBox(height: 16),
        const _Heading('Santé'),
        _Figures([
          _Figure('Silencieuses', n.format(c(h, 'silent_30')),
              note: 'rien depuis 30 jours', warn: c(h, 'silent_30') > 0),
          _Figure('Vitrines vides', n.format(c(h, 'empty_windows')),
              note: 'ouvertes sans article', warn: c(h, 'empty_windows') > 0),
          _Figure('Repères loin', n.format(c(h, 'pins_far')),
              note: 'hors de la zone de la monnaie', warn: c(h, 'pins_far') > 0),
          _Figure('Sans photo', n.format(c(h, 'no_photo')),
              note: context.tr('sur {n} articles en vitrine', {'n': c(h, 'published')}),
              warn: c(h, 'no_photo') > 0),
        ]),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _write,
            icon: const Icon(Icons.campaign_outlined),
            label: Text(context.tr('Écrire aux boutiques')),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(context.tr(text), style: theme.textTheme.titleMedium)),
          if (trailing != null)
            Text(trailing!,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}

class _Figure {
  const _Figure(this.label, this.value, {this.note, this.warn = false});

  final String label;
  final String value;
  final String? note;
  final bool warn;
}

/// Figures in a wrap: two to a row on a phone, more on a desk.
class _Figures extends StatelessWidget {
  const _Figures(this.figures);

  final List<_Figure> figures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final per = box.maxWidth >= 720 ? 4 : 2;
      final w = (box.maxWidth - (per - 1) * 8) / per;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in figures)
            Container(
              width: w,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: f.warn
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr(f.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(f.value,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (f.note != null)
                    Text(context.tr(f.note!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _MessageDialog extends StatefulWidget {
  const _MessageDialog({required this.admin});

  final AdminRepository admin;

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await widget.admin.sendPlatformMessage(null, _text.text);
      if (mounted) Navigator.of(context).pop(n);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // The keyboard up on a small phone: the dialog scrolls (A6).
      scrollable: true,
      title: Text(context.tr('Écrire aux boutiques')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              context.tr('Le message arrive dans la cloche des propriétaires et administrateurs de chaque entreprise.')),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            enabled: !_busy,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: context.tr('Nouveau : mettez un article en avant…'),
            ),
          ),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: Text(context.tr('Envoyer')),
        ),
      ],
    );
  }
}

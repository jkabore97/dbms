import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/notify/bell_room.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The Événementiel, from Marakaj's side (182): what a free business gets,
/// and which designs are Marakaj Pro's.
///
/// The owner: « allow me to set number of ticket to be free, the templates
/// that will be free or pro in the admin panel ». Two numbers — the tickets
/// a card sells free, the writing assistant's free texts a day — and every
/// design with its switch. A Premium design's animated scene follows it.
class EventsConsoleScreen extends StatefulWidget {
  const EventsConsoleScreen({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<EventsConsoleScreen> createState() => _EventsConsoleScreenState();
}

class _EventsConsoleScreenState extends State<EventsConsoleScreen> {
  EventsConsole? _console;
  String? _error;
  bool _saving = false;
  final _tickets = TextEditingController();
  final _assist = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tickets.dispose();
    _assist.dispose();
    super.dispose();
  }

  void _show(EventsConsole c) {
    _console = c;
    _tickets.text = '${c.numbers.freeTickets}';
    _assist.text = '${c.numbers.assistFreeDay}';
  }

  Future<void> _load() async {
    try {
      final c = await widget.admin.eventsConsole();
      if (mounted) setState(() => _show(c));
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _saveNumbers() async {
    final t = int.tryParse(_tickets.text.trim()), a = int.tryParse(_assist.text.trim());
    if (t == null || a == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Deux nombres, s’il vous plaît.'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final c = await widget.admin.setEventsNumbers(freeTickets: t, assistFreeDay: a);
      if (!mounted) return;
      setState(() => _show(c));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('Enregistré'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _premium(EventsConsoleTemplate t, bool premium) async {
    try {
      final c = await widget.admin.setEventTemplatePremium(t.key, premium);
      if (mounted) setState(() => _console = c);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _console;
    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Événementiel'))),
      body: c == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(context.tr('Gratuit pour tous'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  context.tr('Cartes, Studio, réponses des invités et PDF sont gratuits. Ces deux nombres fixent ce qu’une entreprise sans Marakaj Pro reçoit ; Pro n’a pas de limite (l’assistant : 40 textes par jour).'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('events-free-tickets'),
                  controller: _tickets,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('Billets gratuits par carte'),
                    helperText: c.ticketsOn
                        ? context.tr('Au-delà, la carte ne vend plus en ligne sans Marakaj Pro.')
                        : context.tr('La vente de billets est encore fermée à tous (réglage events_tickets).'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('events-assist-free'),
                  controller: _assist,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('Textes de l’assistant gratuits par jour et par carte'),
                    helperText: context.tr('0 : l’assistant réservé à Marakaj Pro.'),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('events-numbers-save'),
                    onPressed: _saving ? null : _saveNumbers,
                    child: Text(context.tr('Enregistrer')),
                  ),
                ),
                const SizedBox(height: 22),
                Text(context.tr('Modèles'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  context.tr('Un modèle Premium est réservé à Marakaj Pro, son décor animé aussi. Les cartes déjà faites gardent leur modèle.'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                for (final family in {for (final t in c.templates) t.family}) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Text(
                      family == 'anime' ? context.tr('Animés') : family == 'classique' ? context.tr('Classiques') : family,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  for (final t in c.templates.where((t) => t.family == family))
                    SwitchListTile(
                      key: Key('events-template-${t.key}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.name),
                      subtitle: Text(t.premium ? context.tr('Premium · Marakaj Pro') : context.tr('Gratuit')),
                      value: t.premium,
                      onChanged: (v) => _premium(t, v),
                    ),
                ],
              ],
            ),
    );
  }
}

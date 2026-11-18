import 'package:flutter/material.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_sheet.dart';

/// A section's name, as the console's rail says it (186).
String platformSectionLabel(BuildContext context, String key) => switch (key) {
      'today' => context.tr('Aujourd\'hui'),
      'clients' => context.tr('Clients'),
      'money' => context.tr('Argent'),
      'street' => context.tr('La rue'),
      'settings' => context.tr('Réglages'),
      'admins' => context.tr('Administrateurs'),
      _ => key,
    };

/// What a section opens, in one line.
String platformSectionHint(BuildContext context, String key) => switch (key) {
      'today' => context.tr('Le travail du jour, les analyses.'),
      'clients' => context.tr('Les entreprises, les personnes, les livreurs, les formateurs — et ouvrir n\'importe quelle entreprise.'),
      'money' => context.tr('Pro, Événementiel, paiements, règlements, cauris.'),
      'street' => context.tr('À la une, les exemples, les signalements.'),
      'settings' => context.tr('Les règles de la plateforme, les types d\'activité, le journal.'),
      'admins' => context.tr('Nommer les administrateurs et choisir leurs sections.'),
      _ => '',
    };

/// An admin's access, in words: « Tout », or the sections.
String platformAccessWords(BuildContext context, Set<String>? access) {
  if (access == null) return context.tr('Tout');
  if (access.isEmpty) return context.tr('Aucune section');
  return [for (final s in platformSections) if (access.contains(s)) platformSectionLabel(context, s)].join(' · ');
}

/// Who is admin, with which sections (186): the switch, « Tout » or the
/// sections chosen, and — for an admin who lost their phone — their
/// authenticator removed. Pops true when something changed.
class AdminAccessSheet extends StatefulWidget {
  const AdminAccessSheet({
    super.key,
    required this.console,
    required this.userId,
    required this.label,
    this.current,
    this.mine,
  });

  final ConsoleRepository console;
  final String userId;
  final String label;

  /// Their access now; null when they are no admin.
  final PlatformAdminEntry? current;

  /// The sections the one choosing holds; null: everything. Only those
  /// are offered (the server refuses the rest).
  final Set<String>? mine;

  @override
  State<AdminAccessSheet> createState() => _AdminAccessSheetState();
}

class _AdminAccessSheetState extends State<AdminAccessSheet> {
  late bool _on = widget.current != null;
  late bool _everything = widget.current?.everything ?? widget.mine == null;
  late final Set<String> _chosen = {...?widget.current?.access};
  bool _busy = false;
  String? _error;

  bool _offered(String s) => widget.mine == null || widget.mine!.contains(s);

  /// An admin of a few sections never touches an admin of everything.
  bool get _locked => widget.mine != null && (widget.current?.everything ?? false);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.console.setAdminAccess(
        widget.userId,
        on: _on,
        sections: _on && !_everything ? _chosen : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetTwoStep() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(context.tr('Réinitialiser l\'application de {label} ?', {'label': widget.label})),
        content: Text(context.tr(
            'Son application d\'authentification actuelle ne marchera plus. À sa prochaine connexion, Marakaj lui montrera un nouveau QR code à scanner.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('Réinitialiser'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.console.resetTwoStep(widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.tr('Application réinitialisée : un nouveau QR code à la prochaine connexion.'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = !_locked && !_busy && (!_on || _everything || _chosen.isNotEmpty);
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('admin-access-sheet'),
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Accès à la console'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(widget.label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            if (_locked)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(context.tr('Seul un administrateur complet modifie un administrateur complet.')),
              ),
            SwitchListTile(
              key: const Key('admin-access-on'),
              contentPadding: EdgeInsets.zero,
              value: _on,
              onChanged: _locked || _busy ? null : (v) => setState(() => _on = v),
              title: Text(context.tr('Administrateur Marakaj')),
              subtitle: Text(context.tr('Ouvre la console de la plateforme.')),
            ),
            if (_on) ...[
              if (widget.mine == null)
                RadioGroup<bool>(
                  groupValue: _everything,
                  onChanged: (v) {
                    if (_locked || _busy || v == null) return;
                    setState(() => _everything = v);
                  },
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        key: const Key('admin-access-everything'),
                        contentPadding: EdgeInsets.zero,
                        value: true,
                        title: Text(context.tr('Tout')),
                        subtitle: Text(context.tr('Toutes les sections, et nommer d\'autres administrateurs.')),
                      ),
                      RadioListTile<bool>(
                        key: const Key('admin-access-some'),
                        contentPadding: EdgeInsets.zero,
                        value: false,
                        title: Text(context.tr('Sections choisies')),
                      ),
                    ],
                  ),
                ),
              if (!_everything || widget.mine != null)
                KajCard(
                  margin: const EdgeInsets.only(top: 4),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final s in platformSections)
                        if (_offered(s))
                          CheckboxListTile(
                            key: Key('admin-access-$s'),
                            value: _chosen.contains(s),
                            onChanged: _locked || _busy
                                ? null
                                : (v) => setState(() => v == true ? _chosen.add(s) : _chosen.remove(s)),
                            title: Text(platformSectionLabel(context, s),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(platformSectionHint(context, s)),
                          ),
                    ],
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('admin-access-save'),
              onPressed: canSave ? _save : null,
              child: Text(context.tr('Enregistrer')),
            ),
            if (widget.current != null && !_locked) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('admin-access-reset-two-step'),
                onPressed: _busy ? null : _resetTwoStep,
                icon: const Icon(Icons.phonelink_erase_outlined),
                label: Text(context.tr('Réinitialiser son application d\'authentification')),
              ),
              const SizedBox(height: 4),
              Text(
                widget.current!.twoStep
                    ? context.tr('Pour un téléphone perdu ou changé : un nouveau QR code à la prochaine connexion.')
                    : context.tr('Son application n\'est pas encore configurée : le QR code lui sera montré à la connexion.'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens [AdminAccessSheet] for one account; true when something changed.
Future<bool> openAdminAccess(
  BuildContext context, {
  required ConsoleRepository console,
  required String userId,
  required String label,
  PlatformAdminEntry? current,
  Set<String>? mine,
}) async {
  final changed = await showMaraSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AdminAccessSheet(
      console: console,
      userId: userId,
      label: label,
      current: current,
      mine: mine,
    ),
  );
  return changed == true;
}

/// « Administrateurs » (186): who is admin, with which sections, their
/// authenticator set up or not; a tap to change, « Ajouter » to name one.
class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key, required this.console, this.mine});

  final ConsoleRepository console;

  /// The sections of the one looking; null: everything.
  final Set<String>? mine;

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  List<PlatformAdminEntry>? _admins;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.console.admins();
      if (mounted) setState(() => _admins = list);
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    }
  }

  Future<void> _open(PlatformAdminEntry a) async {
    if (a.me) return;
    final changed = await openAdminAccess(context,
        console: widget.console, userId: a.userId, label: a.label, current: a, mine: widget.mine);
    if (changed) await _load();
  }

  Future<void> _add() async {
    final person = await showDialog<PlatformPerson>(
      context: context,
      builder: (_) => _FindPerson(console: widget.console),
    );
    if (person == null || !mounted) return;
    final known = _admins?.where((a) => a.userId == person.userId).firstOrNull;
    final changed = await openAdminAccess(context,
        console: widget.console, userId: person.userId, label: person.label, current: known, mine: widget.mine);
    if (changed) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final admins = _admins;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Administrateurs')),
        actions: [
          IconButton(tooltip: context.tr('Actualiser'), onPressed: _load, icon: const Icon(Icons.refresh)),
          bellRoom,
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('admins-add'),
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(context.tr('Ajouter')),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            )
          : admins == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  key: const Key('admins-list'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    Text(
                      context.tr('Chaque administrateur ne voit que ses sections ; le serveur refuse le reste. Chaque changement est écrit dans le Journal.'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    KajCard(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final a in admins)
                            ListTile(
                              key: Key('admin-${a.userId}'),
                              minVerticalPadding: 12,
                              leading: CircleAvatar(child: Text(a.label.characters.first.toUpperCase())),
                              title: Text(a.me ? context.tr('{label} (vous)', {'label': a.label}) : a.label,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (a.email != null || a.phone != null) Text(a.email ?? a.phone!),
                                  Text(platformAccessWords(context, a.access)),
                                  Text(
                                    a.twoStep
                                        ? context.tr('Application d\'authentification configurée')
                                        : context.tr('Application d\'authentification pas encore configurée'),
                                    style: TextStyle(
                                        color: a.twoStep ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.error),
                                  ),
                                ],
                              ),
                              trailing: a.me ? null : const Icon(Icons.chevron_right),
                              onTap: a.me ? null : () => _open(a),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// A person, found by name, phone or email.
class _FindPerson extends StatefulWidget {
  const _FindPerson({required this.console});

  final ConsoleRepository console;

  @override
  State<_FindPerson> createState() => _FindPersonState();
}

class _FindPersonState extends State<_FindPerson> {
  final _query = TextEditingController();
  List<PlatformPerson>? _found;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await widget.console.searchPeople(q, limit: 20);
      if (mounted) setState(() => _found = found);
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return AlertDialog(
      scrollable: true,
      title: Text(context.tr('Nommer un administrateur')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('admins-find'),
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: context.tr('Nom, téléphone ou e-mail'),
                suffixIcon: IconButton(
                  tooltip: context.tr('Chercher'),
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (found != null && found.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(context.tr('Personne ne porte ce nom.')),
              ),
            if (found != null)
              for (final p in found)
                ListTile(
                  key: Key('admins-found-${p.userId}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.label),
                  subtitle: Text(p.email ?? p.phone ?? ''),
                  onTap: () => Navigator.of(context).pop(p),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Fermer'))),
      ],
    );
  }
}

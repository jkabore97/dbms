import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';
import '../../core/admin/models.dart' show roleLabel;

/// The platform admin's global directory of people — the other axis to the
/// business console. Search any account across every business, see where they
/// appear and as what, and act: reset a password or delete an account (through
/// the account Worker), or grant and revoke platform access.
///
/// Everything is gated server-side on is_platform_admin (047); the screen is
/// only reachable from the console, which is itself platform-admin only.
class PlatformPeopleScreen extends StatefulWidget {
  const PlatformPeopleScreen({
    super.key,
    required this.console,
    required this.admin,
  });

  final ConsoleRepository console;
  final AdminRepository admin;

  @override
  State<PlatformPeopleScreen> createState() => _PlatformPeopleScreenState();
}

class _PlatformPeopleScreenState extends State<PlatformPeopleScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<PlatformPerson> _people = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await widget.console.searchPeople(_search.text);
      if (!mounted) return;
      setState(() {
        _people = people;
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

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Annuaire des personnes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Nom, téléphone ou e-mail…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            style:
                                TextStyle(color: theme.colorScheme.error)),
                      ),
                    ])
                  : _people.isEmpty && !_loading
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: Text('Aucun compte trouvé.')),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _people.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) =>
                              _tile(context, _people[i]),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, PlatformPerson person) {
    final theme = Theme.of(context);
    final subtitle = [
      person.email ?? person.phone,
      '${person.businessCount} entreprise${person.businessCount > 1 ? 's' : ''}',
    ].whereType<String>().join(' · ');

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: CircleAvatar(
          child: Text(person.label.characters.first.toUpperCase()),
        ),
        title: Text(person.label),
        subtitle: Text(subtitle),
        trailing: person.isPlatformAdmin
            ? Chip(
                label: const Text('Kaj'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.primaryContainer,
              )
            : const Icon(Icons.chevron_right),
        onTap: () => _openPerson(person),
      ),
    );
  }

  Future<void> _openPerson(PlatformPerson person) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PersonSheet(
        person: person,
        console: widget.console,
        admin: widget.admin,
      ),
    );
    if (changed == true) await _load();
  }
}

/// One person, opened: their businesses and roles, and the actions a platform
/// admin may take on the account.
class _PersonSheet extends StatefulWidget {
  const _PersonSheet({
    required this.person,
    required this.console,
    required this.admin,
  });

  final PlatformPerson person;
  final ConsoleRepository console;
  final AdminRepository admin;

  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  List<PersonOrg>? _orgs;
  late bool _isPlatformAdmin = widget.person.isPlatformAdmin;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  bool get _isSelf => widget.person.userId == widget.admin.currentUserId;
  bool get _canWorker => widget.admin.canManageAccounts;

  @override
  void initState() {
    super.initState();
    _loadOrgs();
  }

  Future<void> _loadOrgs() async {
    try {
      final orgs = await widget.console.userOrgs(widget.person.userId);
      if (mounted) setState(() => _orgs = orgs);
    } catch (_) {
      if (mounted) setState(() => _orgs = const []);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = AuthRepository.describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlatform() async {
    final next = !_isPlatformAdmin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(next
            ? 'Donner l\'accès plateforme ?'
            : 'Retirer l\'accès plateforme ?'),
        content: Text(next
            ? '${widget.person.label} pourra voir et gérer toutes les '
                'entreprises de la plateforme.'
            : '${widget.person.label} perdra l\'accès à la plateforme.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.console.setPlatformAdmin(widget.person.userId, next),
      next ? 'Accès plateforme accordé' : 'Accès plateforme retiré',
    );
    if (mounted) setState(() => _isPlatformAdmin = next);
  }

  Future<void> _resetPassword() async {
    final pw1 = TextEditingController();
    final pw2 = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text('Nouveau mot de passe — ${widget.person.label}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pw1,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pw2,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Confirmer', border: OutlineInputBorder()),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error)),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              FilledButton(
                onPressed: () {
                  if (pw1.text.length < 8) {
                    setLocal(() => err = 'Au moins 8 caractères.');
                  } else if (pw1.text != pw2.text) {
                    setLocal(() => err = 'Les mots de passe diffèrent.');
                  } else {
                    Navigator.pop(ctx, pw1.text);
                  }
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        });
      },
    );
    pw1.dispose();
    pw2.dispose();
    if (password == null) return;
    await _run(
      () => widget.admin.setUserPassword(widget.person.userId, password),
      'Mot de passe réinitialisé',
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer le compte de ${widget.person.label} ?'),
        content: const Text(
            'Le compte sera supprimé définitivement et la personne sera '
            'déconnectée. Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.admin.deleteUserAccount(widget.person.userId),
      'Compte supprimé',
    );
    if (mounted && _changed) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.person;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(p.label.characters.first.toUpperCase()),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.label, style: theme.textTheme.titleLarge),
                      if (p.title != null && p.title!.isNotEmpty)
                        Text(p.title!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (_isPlatformAdmin)
                  Chip(
                    label: const Text('Kaj'),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (p.email != null) _row(context, Icons.email_outlined, p.email!),
            if (p.phone != null) _row(context, Icons.phone_outlined, p.phone!),
            const Divider(height: 28),

            Text('Entreprises', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (_orgs == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_orgs!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("N'appartient à aucune entreprise."),
              )
            else
              ..._orgs!.map((o) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(o.archived
                        ? Icons.archive_outlined
                        : Icons.storefront_outlined),
                    title: Text(o.orgName),
                    subtitle: Text(
                        '${roleLabel(o.role)}${o.archived ? ' · archivée' : ''}'),
                  )),
            const Divider(height: 28),

            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
            ],

            // Platform access — never on oneself.
            if (!_isSelf)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPlatformAdmin,
                onChanged: _busy ? null : (_) => _togglePlatform(),
                title: const Text('Accès plateforme (Kaj)'),
                subtitle: const Text(
                    'Voir et gérer toutes les entreprises de la plateforme.'),
              ),

            if (_canWorker) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _busy ? null : _resetPassword,
                icon: const Icon(Icons.password_outlined),
                label: const Text('Réinitialiser le mot de passe'),
              ),
              if (!_isSelf) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: Icon(Icons.delete_forever_outlined,
                      color: theme.colorScheme.error),
                  label: Text('Supprimer le compte',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ] else
              Text(
                'La réinitialisation du mot de passe et la suppression '
                'nécessitent le service de comptes (non configuré).',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(text)),
        ]),
      );
}

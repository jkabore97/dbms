import 'dart:async';

import '../../core/theme/kaj_card.dart';
import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';
import '../../core/admin/models.dart' show roleLabel;
import '../../core/help/help_repository.dart';
import '../../core/nav/app_scope.dart';
import '../../core/phone/country_codes.dart' show displayPhone;
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import 'package:kaj_app/core/theme/mara_sheet.dart';

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
    this.initialQuery,
    this.openUserId,
    this.help,
  });

  final ConsoleRepository console;
  final AdminRepository admin;

  /// « Formateur Mara » (143); the app's own server unless a test gives one.
  final HelpRepository? help;

  /// What the command center's search found (104): the search to start
  /// with, and the person to open at once when the list has them.
  final String? initialQuery;
  final String? openUserId;

  @override
  State<PlatformPeopleScreen> createState() => _PlatformPeopleScreenState();
}

class _PlatformPeopleScreenState extends State<PlatformPeopleScreen> {
  late final _search = TextEditingController(text: widget.initialQuery ?? '');
  Timer? _debounce;
  late String? _toOpen = widget.openUserId;

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
      final open = _toOpen;
      _toOpen = null;
      for (final p in people) {
        if (p.userId == open) {
          await _openPerson(p);
          break;
        }
      }
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
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Annuaire des personnes'))),
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
                hintText: context.tr('Nom, téléphone ou e-mail…'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('Effacer'),
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
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(40),
                            child: Center(child: Text(context.tr('Aucun compte trouvé.'))),
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

    return KajCard(
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
                label: Text(context.tr('Mara')),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.primaryContainer,
              )
            : const Icon(Icons.chevron_right),
        onTap: () => _openPerson(person),
      ),
    );
  }

  Future<void> _openPerson(PlatformPerson person) async {
    final changed = await showMaraSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PersonSheet(
        person: person,
        console: widget.console,
        admin: widget.admin,
        help: widget.help ??
            HelpRepository(AppScope.maybeOf(context)?.auth.client),
      ),
    );
    if (changed == true) await _load();
  }
}

/// One person, opened: their businesses and roles, and the actions a platform
/// admin may take on the account — since 143 « Formateur Mara » too.
class PersonSheet extends StatefulWidget {
  const PersonSheet({
    super.key,
    required this.person,
    required this.console,
    required this.admin,
    required this.help,
  });

  final PlatformPerson person;
  final ConsoleRepository console;
  final AdminRepository admin;
  final HelpRepository help;

  @override
  State<PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<PersonSheet> {
  List<PersonOrg>? _orgs;

  /// « Formateur Mara » (143): null while it is asked, or when it cannot be.
  TrainerSwitch? _trainer;
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
    _loadTrainer();
  }

  Future<void> _loadTrainer() async {
    if (!widget.help.isConfigured) return;
    try {
      final t = await widget.help.trainerState(widget.person.userId);
      if (mounted) setState(() => _trainer = t);
    } catch (_) {}
  }

  /// What turning a trainer off does, said true (138): the requests stop,
  /// the 48 h accesses end and the businesses they are assigned to (038)
  /// are taken from them — how many said. Before 138 the server keeps the
  /// assignments: only the first two are promised.
  static String _offWords(BuildContext context, TrainerSwitch? t) {
    final n = t?.assigned ?? 0;
    if (t == null || !t.installed || n == 0) {
      return context.tr('Cette personne ne recevra plus de demandes d\'aide ; ses accès en lecture seule s\'arrêtent.');
    }
    return n == 1
        ? context.tr('Cette personne ne recevra plus de demandes d\'aide ; ses accès en lecture seule s\'arrêtent, et elle ne verra plus l\'entreprise qui lui est confiée.')
        : context.tr('Cette personne ne recevra plus de demandes d\'aide ; ses accès en lecture seule s\'arrêtent, et elle ne verra plus les {n} entreprises qui lui sont confiées.', {'n': n});
  }

  /// A trainer is 038's profiles.is_trainer: rung for the requests of the
  /// businesses they are assigned to, and every one once escalated (133).
  Future<void> _toggleTrainer(bool on) async {
    final label = widget.person.label;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(on
            ? context.tr('Faire de {label} un formateur Mara ?', {'label': label})
            : context.tr('{label} n\'est plus formateur ?', {'label': label})),
        content: Text(on
            ? context.tr('Cette personne recevra les demandes d\'aide des entreprises Mara Pro, dans l\'app et sur WhatsApp, au numéro de son profil.')
            : _offWords(context, _trainer)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('Annuler'))),
          FilledButton(
              key: const Key('trainer-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('Confirmer'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final t = await widget.help.setTrainer(widget.person.userId, on,
          phone: widget.person.phone);
      if (mounted) setState(() => _trainer = t);
    }, on ? context.tr('Formateur ajouté') : context.tr('Formateur retiré'));
  }

  Widget _trainerSwitch(BuildContext context) {
    final theme = Theme.of(context);
    final t = _trainer;
    if (t == null) return const SizedBox.shrink();
    final phone = t.phone ?? widget.person.phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('trainer-switch'),
          contentPadding: EdgeInsets.zero,
          value: t.isTrainer,
          onChanged: _busy ? null : _toggleTrainer,
          secondary: const Icon(Icons.support_agent_outlined),
          title: Text(context.tr('Formateur Mara')),
          subtitle: Text(t.isTrainer
              ? context.tr('Reçoit les demandes d\'aide des entreprises Mara Pro.')
              : context.tr('Aide les entreprises Mara Pro qui le demandent.')),
        ),
        if (t.isTrainer && (phone == null || phone.trim().isEmpty))
          Container(
            key: const Key('trainer-no-phone'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('Pas de numéro sur son profil : les demandes ne pourront pas le joindre par WhatsApp ni par appel. Ajoutez-en un à son compte.'),
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          )
        else if (t.isTrainer)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.tr('Joint au {phone}', {'phone': displayPhone(phone!)}),
              key: const Key('trainer-phone'),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
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
            .showSnackBar(SnackBar(content: Text(context.tr(done))));
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
        // The keyboard up on a small phone: the dialog scrolls (A6).
        scrollable: true,
        title: Text(next
            ? context.tr('Donner l\'accès plateforme ?')
            : context.tr('Retirer l\'accès plateforme ?')),
        content: Text(next
            ? context.tr('{label} pourra voir et gérer toutes les entreprises de la plateforme.', {'label': widget.person.label})
            : context.tr('{label} perdra l\'accès à la plateforme.', {'label': widget.person.label})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('Annuler'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('Confirmer'))),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    await _run(
      () => widget.console.setPlatformAdmin(widget.person.userId, next),
      next ? context.tr('Accès plateforme accordé') : context.tr('Accès plateforme retiré'),
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
            // The keyboard up on a small phone: the dialog scrolls (A6).
            scrollable: true,
            title: Text(context.tr('Nouveau mot de passe — {label}', {'label': widget.person.label})),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pw1,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: context.tr('Nouveau mot de passe'),
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pw2,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: context.tr('Confirmer'), border: const OutlineInputBorder()),
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
                  child: Text(context.tr('Annuler'))),
              FilledButton(
                onPressed: () {
                  if (pw1.text.length < 8) {
                    setLocal(() => err = context.tr('Au moins 8 caractères.'));
                  } else if (pw1.text != pw2.text) {
                    setLocal(() => err = context.tr('Les mots de passe diffèrent.'));
                  } else {
                    Navigator.pop(ctx, pw1.text);
                  }
                },
                child: Text(context.tr('Enregistrer')),
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
        // The keyboard up on a small phone: the dialog scrolls (A6).
        scrollable: true,
        title: Text(context.tr('Supprimer le compte de {label} ?', {'label': widget.person.label})),
        content: Text(
            context.tr('Le compte sera supprimé définitivement et la personne sera déconnectée. Cette action est irréversible.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('Annuler'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('Supprimer')),
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
                    label: Text(context.tr('Mara')),
                    backgroundColor: theme.colorScheme.primaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (p.email != null) _row(context, Icons.email_outlined, p.email!),
            if (p.phone != null) _row(context, Icons.phone_outlined, p.phone!),
            const Divider(height: 28),

            Text(context.tr('Entreprises'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (_orgs == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_orgs!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(context.tr('N\'appartient à aucune entreprise.')),
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
                        '${roleLabel(o.role)}${o.archived ? context.tr(' · archivée') : ''}'),
                  )),
            const Divider(height: 28),

            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
            ],

            // 143: « Formateur Mara », chosen here by the platform.
            _trainerSwitch(context),

            // Platform access — never on oneself.
            if (!_isSelf)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPlatformAdmin,
                onChanged: _busy ? null : (_) => _togglePlatform(),
                title: Text(context.tr('Accès plateforme (Mara)')),
                subtitle: Text(
                    context.tr('Voir et gérer toutes les entreprises de la plateforme.')),
              ),

            if (_canWorker) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _busy ? null : _resetPassword,
                icon: const Icon(Icons.password_outlined),
                label: Text(context.tr('Réinitialiser le mot de passe')),
              ),
              if (!_isSelf) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: Icon(Icons.delete_forever_outlined,
                      color: theme.colorScheme.error),
                  label: Text(context.tr('Supprimer le compte'),
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ] else
              Text(
                context.tr('La réinitialisation du mot de passe et la suppression nécessitent le service de comptes (non configuré).'),
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

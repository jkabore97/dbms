import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/admin/models.dart';
import '../../core/auth/auth_repository.dart';
import 'invite_sheet.dart';

/// Who belongs to this business, and who has been asked to.
///
/// Both lists on one screen on purpose: "have I invited Esther yet" and "is
/// Esther in" are the same question to the person asking it, and splitting
/// them across two tabs is how an admin ends up sending a second code.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    super.key,
    required this.admin,
    required this.orgId,
    required this.orgName,
    this.callerRoles = const [],
  });

  final AdminRepository admin;
  final String orgId;
  final String orgName;

  /// The signed-in person's own roles in this business, from `my_orgs()`. They
  /// set the ceiling on who this person may manage: an admin reaches the staff
  /// and responsables below them, never a peer or someone above. Empty means
  /// "manage no one" — the server enforces the same, this only hides the
  /// actions it would refuse.
  final List<String> callerRoles;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  List<Member> _members = const [];
  List<Invitation> _invitations = const [];
  List<Entity> _structure = const [];

  bool _loading = true;
  String? _error;

  /// Names for scope ids, so a grant reads "Chorale" rather than a uuid.
  final Map<String, String> _scopeNames = {};

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
      final members = await widget.admin.fetchMembers(widget.orgId);
      final invitations = await widget.admin.fetchInvitations(widget.orgId);
      final structure = await widget.admin.fetchStructure(widget.orgId);

      _scopeNames
        ..clear()
        ..[widget.orgId] = "Toute l'activité";
      for (final entity in structure) {
        _scopeNames[entity.id] = entity.name;
        for (final dept in entity.departments) {
          _scopeNames[dept.id] = '${entity.name} · ${dept.name}';
        }
      }

      if (!mounted) return;
      setState(() {
        _members = members;
        _invitations = invitations;
        _structure = structure;
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

  String _scopeLabel(Member m) =>
      _scopeNames[m.scopeId] ?? scopeKindLabel(m.scopeKind);

  Future<void> _invite() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InviteSheet(
        admin: widget.admin,
        orgId: widget.orgId,
        orgName: widget.orgName,
        structure: _structure,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _revokeMembership(Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer ${member.label} ?'),
        content: Text(
          '${member.label} perdra l\'accès à '
          '${_scopeLabel(member).toLowerCase()} en tant que '
          '${roleLabel(member.role).toLowerCase()}.\n\n'
          "Tout ce que cette personne a enregistré reste dans l'historique : "
          'rien de comptable n\'est supprimé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.admin.revokeMembership(member.membershipId);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthRepository.describeError(error))),
      );
    }
  }

  /// The caller's ceiling, from their roles in this business.
  int get _myRank => accountRankOf(widget.callerRoles);

  /// Whether this person may manage that member at all — the client mirror of
  /// the server's rank rule. The owner is never managed from here, and a member
  /// the caller does not outrank shows no menu. The server refuses the same,
  /// so this only keeps buttons that would 403 off the screen.
  bool _canManage(Member member) =>
      member.role != 'owner' && _myRank > accountRoleRank(member.role);

  /// One member, opened: their information first — which a colleague may read —
  /// then, only for a member this person outranks, the ways to edit or manage
  /// them. The Worker-backed actions (reset password, delete) appear only when
  /// the account Worker's address was compiled in; the server re-checks
  /// authority on every action regardless of what the sheet shows.
  Future<void> _showMember(Member member) async {
    final canManage = _canManage(member);
    final canWorker = widget.admin.canManageAccounts;
    final isSelf = member.userId == widget.admin.currentUserId;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      child: Text(member.label.characters.first.toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.label,
                              style: Theme.of(ctx).textTheme.titleMedium),
                          Text(roleLabel(member.role),
                              style: Theme.of(ctx).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // The information itself — shown for everyone, no rank needed.
              _infoRow(ctx, 'Nom complet', member.fullName),
              _infoRow(ctx, 'Téléphone', member.phone),
              _infoRow(ctx, 'Titre', member.title),
              _infoRow(
                ctx,
                'Date de naissance',
                member.dateOfBirth == null
                    ? null
                    : DateFormat('d MMMM y', 'fr_FR').format(member.dateOfBirth!),
              ),
              if (!canManage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    member.role == 'owner'
                        ? "Le propriétaire gère ses propres informations."
                        : 'Vous ne pouvez pas modifier ce compte.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                ),
              if (canManage) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Modifier les informations'),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Changer la responsabilité'),
                  onTap: () => Navigator.pop(ctx, 'role'),
                ),
                if (canWorker)
                  ListTile(
                    leading: const Icon(Icons.password_outlined),
                    title: const Text('Réinitialiser le mot de passe'),
                    onTap: () => Navigator.pop(ctx, 'password'),
                  ),
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text("Retirer de l'entreprise"),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
                if (canWorker && !isSelf)
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined,
                        color: Theme.of(ctx).colorScheme.error),
                    title: Text('Supprimer le compte',
                        style:
                            TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    onTap: () => Navigator.pop(ctx, 'delete'),
                  ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'edit':
        await _editProfile(member);
      case 'role':
        await _changeRole(member);
      case 'password':
        await _resetPassword(member);
      case 'remove':
        await _revokeMembership(member);
      case 'delete':
        await _deleteAccount(member);
    }
  }

  Widget _infoRow(BuildContext ctx, String label, String? value) {
    final shown = (value != null && value.trim().isNotEmpty) ? value : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(shown, style: Theme.of(ctx).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  /// The admin edit of a member's own information. Pre-filled from what the
  /// roster already holds, saved through admin_save_member_profile (046), which
  /// refuses anyone the caller does not outrank.
  Future<void> _editProfile(Member member) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditMemberSheet(admin: widget.admin, member: member),
    );
    if (saved == true) await _load();
  }

  /// The roles an admin may assign. Owner is deliberately absent — promoting to
  /// owner is a transfer of the business, refused by the server here.
  static const _assignableRoles = [
    'super_admin',
    'admin',
    'manager',
    'supervisor',
    'employee',
    'observer',
    'approver',
  ];

  Future<void> _changeRole(Member member) async {
    var selected = _assignableRoles.contains(member.role)
        ? member.role
        : 'employee';
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Responsabilité de ${member.label}'),
        content: StatefulBuilder(
          builder: (ctx, setInner) => DropdownButton<String>(
            value: selected,
            isExpanded: true,
            items: [
              for (final r in _assignableRoles)
                DropdownMenuItem(value: r, child: Text(roleLabel(r))),
            ],
            onChanged: (v) => setInner(() => selected = v ?? selected),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, selected),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == member.role) return;
    await _run(() => widget.admin.setMembershipRole(member.membershipId, chosen),
        done: 'Responsabilité mise à jour.');
  }

  Future<void> _resetPassword(Member member) async {
    final pw1 = TextEditingController();
    final pw2 = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text('Nouveau mot de passe — ${member.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pw1,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw2,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmer',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (pw1.text.length < 8) {
                  setInner(() =>
                      error = 'Au moins 8 caractères.');
                  return;
                }
                if (pw1.text != pw2.text) {
                  setInner(() => error = 'Les deux ne correspondent pas.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Changer'),
            ),
          ],
        ),
      ),
    );
    final password = pw1.text;
    pw1.dispose();
    pw2.dispose();
    if (ok != true) return;
    await _run(() => widget.admin.setUserPassword(member.userId, password),
        done: 'Mot de passe changé.');
  }

  Future<void> _deleteAccount(Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer le compte de ${member.label} ?'),
        content: const Text(
          "Le compte sera supprimé et la personne déconnectée. À sa prochaine "
          "connexion, elle arrivera sur la page d'accueil pour rejoindre une "
          'entreprise avec un code ou en demander une.\n\n'
          "L'historique de ce qu'elle a enregistré reste dans les comptes.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => widget.admin.deleteUserAccount(member.userId),
        done: 'Compte supprimé.');
  }

  /// Runs an admin action, shows the outcome, and reloads. One place so every
  /// action reports failure the same way instead of hanging silently.
  Future<void> _run(Future<void> Function() action, {required String done}) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthRepository.describeError(error))),
      );
    }
  }

  Future<void> _revokeInvitation(Invitation invitation) async {
    try {
      await widget.admin.revokeInvitation(invitation.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthRepository.describeError(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = _invitations.where((i) => i.isOpen).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Personnes')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    _Banner(message: _error!, onRetry: _load),
                    const SizedBox(height: 16),
                  ],
                  Text('Membres (${_members.length})',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Personne pour le moment.'),
                    )
                  else
                    ..._members.map(
                      (m) => Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerHighest,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              m.label.characters.first.toUpperCase(),
                            ),
                          ),
                          title: Text(m.label),
                          subtitle: Text(
                            '${roleLabel(m.role)} · ${_scopeLabel(m)}'
                            '${m.visibility == 'summary' ? ' · totaux seulement' : ''}',
                          ),
                          // Every member opens to their information — a
                          // colleague may read it. Whether the sheet then offers
                          // to edit or manage them is decided inside, by rank.
                          trailing: m.role == 'owner'
                              ? const Chip(
                                  label: Text('Propriétaire'),
                                  visualDensity: VisualDensity.compact,
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => _showMember(m),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text('Invitations en attente (${open.length})',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (open.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Aucune invitation en attente.'),
                    )
                  else
                    ...open.map(
                      (i) => Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading:
                              const Icon(Icons.confirmation_number_outlined),
                          title: SelectableText(
                            i.code,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 2,
                            ),
                          ),
                          subtitle: Text(
                            '${roleLabel(i.role)} · '
                            '${_scopeNames[i.scopeId] ?? scopeKindLabel(i.scopeKind)}'
                            '${i.phone != null ? '\nRéservé à ${i.phone}' : '\nAu porteur'}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copier',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: i.code),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Code copié')),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Annuler',
                                onPressed: () => _revokeInvitation(i),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 96),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _invite,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Inviter'),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

/// The admin edit of one member's own information. Pre-filled from the roster,
/// saved through admin_save_member_profile (046) — which lets an admin edit
/// only someone they outrank, so a refusal here is the server's word, not this
/// form's. A first name and a family name are required, matching the personal
/// profile form; the rest are optional.
class _EditMemberSheet extends StatefulWidget {
  const _EditMemberSheet({required this.admin, required this.member});

  final AdminRepository admin;
  final Member member;

  @override
  State<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends State<_EditMemberSheet> {
  late final _first = TextEditingController(text: widget.member.firstName ?? '');
  late final _middle =
      TextEditingController(text: widget.member.middleName ?? '');
  late final _last = TextEditingController(text: widget.member.lastName ?? '');
  late final _title = TextEditingController(text: widget.member.title ?? '');
  late final _phone = TextEditingController(text: widget.member.phone ?? '');
  late DateTime? _dob = widget.member.dateOfBirth;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _title.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      setState(() => _error = 'Un prénom et un nom de famille sont requis.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.saveMemberProfile(
        widget.member.userId,
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        middleName: _middle.text.trim(),
        dateOfBirth: _dob,
        title: _title.text.trim(),
        phone: _phone.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AuthRepository.describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text('Informations — ${widget.member.label}',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _first,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Prénom',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _middle,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Deuxième prénom (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _last,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom de famille',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Titre (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dob ?? DateTime(1990, 1, 1),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _dob = picked);
                    },
              icon: const Icon(Icons.cake_outlined),
              label: Text(_dob == null
                  ? 'Date de naissance (facultatif)'
                  : 'Né(e) le ${DateFormat('d MMMM y', 'fr_FR').format(_dob!)}'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer', style: TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

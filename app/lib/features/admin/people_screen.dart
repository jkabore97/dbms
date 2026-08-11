import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  });

  final AdminRepository admin;
  final String orgId;
  final String orgName;

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
                          trailing: m.role == 'owner'
                              // The owner is the one grant this screen will not
                              // remove. An org with nobody able to administer it
                              // cannot be repaired from inside the app.
                              ? const Chip(
                                  label: Text('Propriétaire'),
                                  visualDensity: VisualDensity.compact,
                                )
                              : IconButton(
                                  icon: const Icon(Icons.person_remove_outlined),
                                  tooltip: 'Retirer',
                                  onPressed: () => _revokeMembership(m),
                                ),
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
                          leading: const Icon(Icons.confirmation_number_outlined),
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

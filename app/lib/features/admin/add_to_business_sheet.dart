import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kaj_app/core/l10n/tr.dart';

import '../../core/admin/models.dart' show adminGrantableRoles, roleLabel;
import '../../core/auth/auth_repository.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';

/// An existing account added to a business, from the console (169).
///
/// The owner: « I want to be able to add a user that already has an
/// account to a business. » An invitation waits for the person to claim
/// it; this puts the account in at once. From a person's sheet, a platform
/// admin finds the business, chooses the role, and adds. The server checks
/// the rest: a platform admin only, not someone already there, not an
/// archived business, the free plan's team limit. The business's admins
/// are told; the console's journal can undo it.
class AddToBusinessSheet extends StatefulWidget {
  const AddToBusinessSheet({super.key, required this.console, required this.person});

  final ConsoleRepository console;
  final PlatformPerson person;

  /// Owner first, then the roles a business's own admin can give.
  static final roles = ['owner', ...adminGrantableRoles.keys];

  @override
  State<AddToBusinessSheet> createState() => _AddToBusinessSheetState();
}

class _AddToBusinessSheetState extends State<AddToBusinessSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<OrgRow>? _found;
  OrgRow? _org;
  String _role = 'employee';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _found = null);
        return;
      }
      try {
        final page = await widget.console.searchOrgs(query: q, status: 'active', sort: 'name', limit: 20);
        if (mounted) setState(() => _found = page.rows);
      } catch (e) {
        if (mounted) setState(() => _error = AuthRepository.describeError(e));
      }
    });
  }

  Future<void> _add() async {
    final org = _org;
    if (org == null) return;
    final done = context.tr('{who} a été ajouté·e à {org}.', {'who': widget.person.label, 'org': org.name});
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.console.addMember(orgId: org.id, userId: widget.person.userId, role: _role);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(done)));
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
    final org = _org;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Ajouter à une entreprise'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              context.tr('{who} rejoint l’entreprise tout de suite, sans code d’invitation. Ses administrateurs sont prévenus.',
                  {'who': widget.person.label}),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (org == null) ...[
              TextField(
                key: const Key('add-org-search'),
                controller: _search,
                onChanged: _onSearch,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.tr('Entreprise : nom'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_found != null && _found!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(context.tr('Aucune entreprise trouvée.')),
                ),
              for (final o in _found ?? const <OrgRow>[])
                ListTile(
                  key: Key('add-org-pick-${o.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(o.name),
                  subtitle: Text(o.slug),
                  onTap: () => setState(() {
                    _org = o;
                    _error = null;
                  }),
                ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_outlined),
                title: Text(org.name),
                subtitle: Text(org.slug),
                trailing: TextButton(
                  onPressed: _busy ? null : () => setState(() => _org = null),
                  child: Text(context.tr('Changer')),
                ),
              ),
              const SizedBox(height: 8),
              Text(context.tr('Responsabilité'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final r in AddToBusinessSheet.roles)
                    ChoiceChip(
                      key: Key('add-role-$r'),
                      label: Text(context.tr(roleLabel(r))),
                      selected: _role == r,
                      onSelected: _busy ? null : (_) => setState(() => _role = r),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('add-confirm'),
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_add_alt_1),
                label: Text(context.tr('Ajouter comme {role}', {'role': context.tr(roleLabel(_role))})),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import 'create_business_screen.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';

/// Every business on the platform, and the three things that can be done to
/// one: changed, put away, destroyed.
///
/// Only a platform admin reaches this screen, and `all_orgs()` refuses anyone
/// else server-side — it raises rather than returning an empty list, so
/// somebody who is not entitled sees an error instead of the false impression
/// of an empty platform.
///
/// The screen is arranged around one asymmetry. Renaming is ordinary and
/// reversible; archiving is reversible but affects everyone at once;
/// **deleting is permanent and destroys a business's entire history.** So they
/// are not three equal buttons in a row. Archive sits in the open, delete is
/// behind an archived business only, and the dialog for it makes you type the
/// name — a uuid in a confirmation dialog is not read by anybody, and neither
/// is "Are you sure?".
class BusinessesScreen extends StatefulWidget {
  const BusinessesScreen({super.key, required this.admin});

  final AdminRepository admin;

  @override
  State<BusinessesScreen> createState() => _BusinessesScreenState();
}

class _BusinessesScreenState extends State<BusinessesScreen> {
  List<PlatformOrg> _orgs = const [];
  bool _loading = true;
  String? _error;

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
      final orgs = await widget.admin.allOrgs();
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _create() async {
    // CreateBusinessScreen pops the new org's id, not a flag.
    final createdId = await context.push<String>(Routes.newBusiness);
    if (createdId != null) await _load();
  }

  Future<void> _edit(PlatformOrg org) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditBusinessSheet(admin: widget.admin, org: org),
    );
    if (changed == true) await _load();
  }

  Future<void> _archive(PlatformOrg org) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archiver ${org.name} ?'),
        content: const Text(
          'Elle disparaîtra de l’écran de ses membres. Rien n’est supprimé : '
          'toutes les écritures restent, et vous pouvez la restaurer à tout '
          'moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() => widget.admin.archiveOrg(org.id), '${org.name} archivée.');
  }

  Future<void> _restore(PlatformOrg org) =>
      _run(() => widget.admin.restoreOrg(org.id), '${org.name} restaurée.');

  Future<void> _delete(PlatformOrg org) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteBusinessDialog(org: org),
    );
    if (confirmed != true) return;

    await _run(
      () => widget.admin.deleteOrg(
        orgId: org.id,
        confirmName: org.name,
        // The server refuses without this when the books are not empty, and
        // the dialog above is where the person was told what it costs. Sending
        // it for an empty business changes nothing.
        force: org.hasBooks,
      ),
      '${org.name} supprimée définitivement.',
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (error) {
      // Server-side refusals arrive here with their own sentence — "Archivez
      // d'abord", "Tapez le nom exactement" — and those are better than
      // anything this screen could invent, so they are shown as they are.
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = _orgs.where((o) => !o.isArchived).toList();
    final archived = _orgs.where((o) => o.isArchived).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Entreprises')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_business),
        label: const Text('Nouvelle'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            for (final org in live)
              _BusinessCard(
                org: org,
                onEdit: () => _edit(org),
                onArchive: () => _archive(org),
              ),
            if (archived.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Archivées', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Invisibles pour leurs membres, complètes, restaurables. '
                'La suppression définitive n’est possible qu’ici.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final org in archived)
                _BusinessCard(
                  org: org,
                  onRestore: () => _restore(org),
                  onDelete: () => _delete(org),
                ),
            ],
            if (!_loading && _orgs.isEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Center(
                  child: Text(
                    'Aucune entreprise pour le moment.',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.org,
    this.onEdit,
    this.onArchive,
    this.onRestore,
    this.onDelete,
  });

  final PlatformOrg org;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(org.profile), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    org.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (org.isArchived)
                  Chip(
                    label: const Text('Archivée'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${org.slug} · ${_profileLabel(org.profile)} · ${org.currency}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // The two numbers that decide whether deleting this is a tidy-up
            // or the destruction of somebody's history.
            Text(
              '${org.memberCount} membre${org.memberCount > 1 ? 's' : ''} · '
              '${org.entryCount} écriture${org.entryCount > 1 ? 's' : ''}'
              '${org.createdAt == null ? '' : ' · depuis ${DateFormat('MMMM y', 'fr_FR').format(org.createdAt!)}'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (onEdit != null)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Modifier'),
                  ),
                if (onArchive != null)
                  OutlinedButton.icon(
                    onPressed: onArchive,
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('Archiver'),
                  ),
                if (onRestore != null)
                  FilledButton.tonalIcon(
                    onPressed: onRestore,
                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                    label: const Text('Restaurer'),
                  ),
                // Deliberately the last thing, deliberately only on an
                // archived business, and deliberately not a filled button.
                if (onDelete != null)
                  TextButton.icon(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: const Text('Supprimer définitivement'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String profile) => switch (profile) {
        'church' || 'association' => Icons.groups_outlined,
        'farm' => Icons.agriculture_outlined,
        'retail' => Icons.storefront_outlined,
        _ => Icons.work_outline,
      };

  static String _profileLabel(String profile) => switch (profile) {
        'church' || 'association' => 'Association',
        'farm' => 'Ferme',
        'retail' => 'Commerce',
        _ => 'Autre',
      };
}

/// The one destructive dialog in the app.
///
/// It asks for the name to be typed back rather than offering a button that
/// says "Supprimer". Two reasons: the person has to read which business this
/// is, and copying a name out is a deliberate act in a way that a second tap
/// is not. The server makes the same check, so a client that skipped it would
/// still be refused.
class DeleteBusinessDialog extends StatefulWidget {
  const DeleteBusinessDialog({super.key, required this.org});

  final PlatformOrg org;

  @override
  State<DeleteBusinessDialog> createState() => _DeleteBusinessDialogState();
}

class _DeleteBusinessDialogState extends State<DeleteBusinessDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches =>
      _controller.text.trim().toLowerCase() ==
      widget.org.name.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = widget.org;

    return AlertDialog(
      title: const Text('Supprimer définitivement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            org.hasBooks
                // Said in what is being destroyed, not in row counts: "42
                // écritures" is a number, "toute la comptabilité" is what it
                // means.
                ? 'Toute la comptabilité de ${org.name} sera détruite : '
                    '${org.entryCount} écriture${org.entryCount > 1 ? 's' : ''}, '
                    'les articles, le personnel, les photos et les '
                    '${org.memberCount} accès. C’est irréversible.'
                : '${org.name} n’a aucune écriture. Sa suppression est '
                    'définitive et ne peut pas être annulée.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Tapez « ${org.name} » pour confirmer.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: org.name,
              errorText: _controller.text.isEmpty || _matches
                  ? null
                  : 'Le nom ne correspond pas.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Supprimer'),
        ),
      ],
    );
  }
}

/// Renaming, re-addressing, and changing which home screen a business opens
/// on. Reachable by an org's own admins as well as the platform's, because
/// 004 already said an owner may edit their own `orgs` row.
class EditBusinessSheet extends StatefulWidget {
  const EditBusinessSheet({super.key, required this.admin, required this.org});

  final AdminRepository admin;
  final PlatformOrg org;

  @override
  State<EditBusinessSheet> createState() => _EditBusinessSheetState();
}

class _EditBusinessSheetState extends State<EditBusinessSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.org.name);
  late final TextEditingController _slug =
      TextEditingController(text: widget.org.slug);
  late final TextEditingController _currency =
      TextEditingController(text: widget.org.currency);
  late String _profile = widget.org.profile;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _slug.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _currency.dispose();
    super.dispose();
  }

  String? get _slugProblem {
    final slug = _slug.text.trim();
    if (slug.isEmpty) return null;
    return CreateBusinessScreen.slugProblem(slug);
  }

  bool get _canSave =>
      !_saving && _name.text.trim().isNotEmpty && _slugProblem == null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.admin.updateOrg(
        orgId: widget.org.id,
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        profile: _profile,
        currency: _currency.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(const SnackBar(content: Text('Enregistré.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, inset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modifier l’entreprise', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _slug,
              decoration: InputDecoration(
                labelText: 'Adresse',
                border: const OutlineInputBorder(),
                helperText: _slugProblem == null
                    ? 'Sert de sous-domaine : ${_slug.text.trim()}.kajapp.com'
                    : null,
                errorText: _slugProblem,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _profile,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
                // Not cosmetic: the profile decides which home screen every
                // member of this business opens on tomorrow morning.
                helperText: 'Change l’écran d’accueil de tous les membres.',
              ),
              items: [
                const DropdownMenuItem(
                    value: 'association', child: Text('Association')),
                const DropdownMenuItem(value: 'farm', child: Text('Ferme')),
                const DropdownMenuItem(
                    value: 'retail', child: Text('Commerce')),
                // A business not yet migrated by 035 still reads 'church';
                // keep it selectable so its edit form does not crash on a
                // value with no item, without offering it to anyone else.
                if (widget.org.profile == 'church')
                  const DropdownMenuItem(value: 'church', child: Text('Association')),
                // 'Autre' is no longer offered when creating a business. Kept
                // here only for one already on it, so its edit form neither
                // breaks (a Dropdown value must match an item) nor lets a
                // business be newly switched to the empty profile.
                if (widget.org.profile == 'generic')
                  const DropdownMenuItem(value: 'generic', child: Text('Autre')),
              ],
              onChanged: (v) => setState(() => _profile = v ?? _profile),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currency,
              decoration: const InputDecoration(
                labelText: 'Monnaie',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Enregistrer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

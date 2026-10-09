import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import 'create_business_screen.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../common/keyboard_sheet.dart';

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
      useSafeArea: true,
      builder: (_) => EditBusinessSheet(admin: widget.admin, org: org),
    );
    if (changed == true) await _load();
  }

  Future<void> _archive(PlatformOrg org) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Archiver {name} ?', {'name': org.name})),
        content: Text(
          context.tr('Elle disparaîtra de l’écran de ses membres. Rien n’est supprimé : toutes les écritures restent, et vous pouvez la restaurer à tout moment.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Archiver')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() => widget.admin.archiveOrg(org.id), context.tr('{name} archivée.', {'name': org.name}));
  }

  Future<void> _restore(PlatformOrg org) =>
      _run(() => widget.admin.restoreOrg(org.id), context.tr('{name} restaurée.', {'name': org.name}));

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
      context.tr('{name} supprimée définitivement.', {'name': org.name}),
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
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Entreprises'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_business),
        label: Text(context.tr('Nouvelle')),
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
                      label: Text(context.tr('Réessayer')),
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
              Text(context.tr('Archivées'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                context.tr('Invisibles pour leurs membres, complètes, restaurables. La suppression définitive n’est possible qu’ici.'),
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
                    context.tr('Aucune entreprise pour le moment.'),
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

    return KajCard(
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
                    label: Text(context.tr('Archivée')),
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
              '${org.memberCount > 1 ? context.tr('{n} membres', {'n': org.memberCount}) : context.tr('{n} membre', {'n': org.memberCount})} · '
              '${org.entryCount > 1 ? context.tr('{n} écritures', {'n': org.entryCount}) : context.tr('{n} écriture', {'n': org.entryCount})}'
              '${org.createdAt == null ? '' : ' · ${context.tr('depuis {date}', {'date': DateFormat('MMMM y', intlLocale()).format(org.createdAt!)})}'}',
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
                    label: Text(context.tr('Modifier')),
                  ),
                if (onArchive != null)
                  OutlinedButton.icon(
                    onPressed: onArchive,
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text(context.tr('Archiver')),
                  ),
                if (onRestore != null)
                  FilledButton.tonalIcon(
                    onPressed: onRestore,
                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                    label: Text(context.tr('Restaurer')),
                  ),
                // Deliberately the last thing, deliberately only on an
                // archived business, and deliberately not a filled button.
                if (onDelete != null)
                  TextButton.icon(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: Text(context.tr('Supprimer définitivement')),
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
      // The keyboard up on a small phone: the dialog scrolls (A6).
      scrollable: true,
      title: Text(context.tr('Supprimer définitivement')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            org.hasBooks
                // Said in what is being destroyed, not in row counts: "42
                // écritures" is a number, "toute la comptabilité" is what it
                // means.
                ? context.tr('Toute la comptabilité de {name} sera détruite : {entries} écriture(s), les articles, le personnel, les photos et les {members} accès. C’est irréversible.',
                    {'name': org.name, 'entries': org.entryCount, 'members': org.memberCount})
                : context.tr('{name} n’a aucune écriture. Sa suppression est définitive et ne peut pas être annulée.',
                    {'name': org.name}),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(context.tr('Tapez « {name} » pour confirmer.', {'name': org.name}),
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
                  : context.tr('Le nom ne correspond pas.'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(context.tr('Supprimer')),
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
      messenger.showSnackBar(SnackBar(content: Text(context.tr('Enregistré.'))));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      // The fields scroll; the button stays above the keyboard (A6).
      footer: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(context.tr('Enregistrer')),
              ),
            ),
      children: [
            Text(context.tr('Modifier l’entreprise'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: context.tr('Nom'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _slug,
              decoration: InputDecoration(
                labelText: context.tr('Adresse'),
                border: const OutlineInputBorder(),
                helperText: _slugProblem == null
                    ? context.tr('Adresse de la vitrine : marakaj.com/s/{slug}',
                        {'slug': _slug.text.trim()})
                    : null,
                errorText: _slugProblem,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _profile,
              decoration: InputDecoration(
                labelText: context.tr('Type'),
                border: const OutlineInputBorder(),
                // Not cosmetic: the profile decides which home screen every
                // member of this business opens on tomorrow morning.
                helperText: context.tr('Change l’écran d’accueil de tous les membres.'),
              ),
              items: [
                DropdownMenuItem(
                    value: 'association', child: Text(context.tr('Association'))),
                DropdownMenuItem(value: 'farm', child: Text(context.tr('Ferme'))),
                DropdownMenuItem(
                    value: 'retail', child: Text(context.tr('Commerce'))),
                // A business not yet migrated by 035 still reads 'church';
                // keep it selectable so its edit form does not crash on a
                // value with no item, without offering it to anyone else.
                if (widget.org.profile == 'church')
                  DropdownMenuItem(value: 'church', child: Text(context.tr('Association'))),
                // 'Autre' is no longer offered when creating a business. Kept
                // here only for one already on it, so its edit form neither
                // breaks (a Dropdown value must match an item) nor lets a
                // business be newly switched to the empty profile.
                if (widget.org.profile == 'generic')
                  DropdownMenuItem(value: 'generic', child: Text(context.tr('Autre'))),
              ],
              onChanged: (v) => setState(() => _profile = v ?? _profile),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currency,
              decoration: InputDecoration(
                labelText: context.tr('Monnaie'),
                border: const OutlineInputBorder(),
              ),
            ),
      ],
    );
  }
}

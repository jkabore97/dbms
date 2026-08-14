import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/admin/models.dart';
import '../../core/auth/auth_repository.dart';

/// The shape of the business: its sites, and the departments inside them.
///
/// This is not organisational decoration. Every scope here is something a role
/// can be granted over, so adding "Poultry" to "Farm A" is what makes
/// "Supervisor, Poultry, Farm A" possible on the invite screen — and what
/// stops that supervisor seeing the rest of the farm.
///
/// Nothing is deletable. A site or department with ledger history behind it
/// cannot be removed without orphaning entries, and a screen that offers a
/// delete which usually fails is worse than one that never offers it. Renaming
/// covers the real case, which is a typo.
class StructureScreen extends StatefulWidget {
  const StructureScreen({
    super.key,
    required this.admin,
    required this.orgId,
    required this.profile,
  });

  final AdminRepository admin;
  final String orgId;

  /// Decides what a site is called on screen — a farm has sites, a church has
  /// campuses, a shop has branches. Same table underneath.
  final String profile;

  @override
  State<StructureScreen> createState() => _StructureScreenState();
}

class _StructureScreenState extends State<StructureScreen> {
  List<Entity> _entities = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _entityWord => switch (widget.profile) {
        'church' => 'Campus',
        'farm' => 'Site',
        'retail' => 'Boutique',
        _ => 'Site',
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entities = await widget.admin.fetchStructure(widget.orgId);
      if (!mounted) return;
      setState(() {
        _entities = entities;
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

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthRepository.describeError(error))),
      );
    }
  }

  Future<String?> _askName({
    required String title,
    String? initial,
    String hint = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: hint,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('${_entityWord}s et départements')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_entities.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.account_tree_outlined,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun ${_entityWord.toLowerCase()} pour le moment.\n'
                            'Ajoutez-en un pour pouvoir confier un rôle sur '
                            'une partie seulement de l\'activité.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ..._entities.map(
                    (entity) => Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(
                              entity.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              entity.departments.isEmpty
                                  ? 'Aucun département'
                                  : '${entity.departments.length} département'
                                      '${entity.departments.length > 1 ? 's' : ''}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Renommer',
                              onPressed: () async {
                                final name = await _askName(
                                  title: 'Renommer',
                                  initial: entity.name,
                                );
                                if (name == null || name.isEmpty) return;
                                await _run(() =>
                                    widget.admin.renameEntity(entity.id, name));
                              },
                            ),
                          ),
                          ...entity.departments.map(
                            (dept) => Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: ListTile(
                                dense: true,
                                leading:
                                    const Icon(Icons.subdirectory_arrow_right),
                                title: Text(dept.name),
                                trailing: IconButton(
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 20),
                                  tooltip: 'Renommer',
                                  onPressed: () async {
                                    final name = await _askName(
                                      title: 'Renommer le département',
                                      initial: dept.name,
                                    );
                                    if (name == null || name.isEmpty) return;
                                    await _run(() => widget.admin
                                        .renameDepartment(dept.id, name));
                                  },
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 8, 8),
                            child: TextButton.icon(
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Ajouter un département'),
                              onPressed: () async {
                                final name = await _askName(
                                  title: 'Nouveau département',
                                  hint: 'Chorale, Volaille, Caisse…',
                                );
                                if (name == null || name.isEmpty) return;
                                await _run(() => widget.admin
                                    .createDepartment(entity.id, name));
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 96),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading
            ? null
            : () async {
                final name = await _askName(
                  title: 'Nouveau ${_entityWord.toLowerCase()}',
                  hint: 'Centre-ville, Ferme Nord…',
                );
                if (name == null || name.isEmpty) return;
                await _run(
                  () => widget.admin.createEntity(
                    widget.orgId,
                    name,
                    kind: switch (widget.profile) {
                      'church' => 'campus',
                      'farm' => 'farm_site',
                      'retail' => 'branch',
                      _ => null,
                    },
                  ),
                );
              },
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text('Ajouter un ${_entityWord.toLowerCase()}'),
      ),
    );
  }
}

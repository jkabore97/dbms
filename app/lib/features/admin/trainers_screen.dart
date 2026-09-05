import 'package:flutter/material.dart';

import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';
import '../../core/errors.dart';

/// Where the platform runs its trainers (038): the students sent out to teach
/// businesses the app.
///
/// A trainer is an ordinary account marked as a trainer here, then assigned to
/// the businesses they cover. Inside one of those businesses they see
/// everything and can change nothing — that safety lives in the server (038),
/// so this screen is only the roster and the assignments.
class TrainersScreen extends StatefulWidget {
  const TrainersScreen({super.key, required this.console});

  final ConsoleRepository console;

  @override
  State<TrainersScreen> createState() => _TrainersScreenState();
}

class _TrainersScreenState extends State<TrainersScreen> {
  bool _loading = true;
  String? _error;
  List<Trainer> _trainers = const [];

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
      final trainers = await widget.console.trainers();
      if (!mounted) return;
      setState(() {
        _trainers = trainers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _addTrainer() async {
    final phone = await showDialog<String>(
      context: context,
      builder: (_) => const _AddTrainerDialog(),
    );
    if (phone == null || phone.trim().isEmpty) return;
    try {
      await widget.console.setTrainerByPhone(phone.trim());
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    }
  }

  Future<void> _openTrainer(Trainer trainer) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrainerSheet(console: widget.console, trainer: trainer),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Formateurs'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTrainer,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Ajouter un formateur'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _trainers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.school_outlined,
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            const Text('Aucun formateur pour le moment'),
                            const SizedBox(height: 4),
                            Text(
                              'Ajoutez un formateur par son numéro, puis '
                              'affectez-le aux entreprises qu\'il accompagne.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: _trainers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = _trainers[i];
                        return Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(t.label.characters.first.toUpperCase()),
                            ),
                            title: Text(t.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(t.phone ?? ''),
                            trailing: Chip(
                              label: Text('${t.assignments}'),
                              avatar: const Icon(Icons.storefront_outlined,
                                  size: 16),
                            ),
                            onTap: () => _openTrainer(t),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _AddTrainerDialog extends StatefulWidget {
  const _AddTrainerDialog();

  @override
  State<_AddTrainerDialog> createState() => _AddTrainerDialogState();
}

class _AddTrainerDialogState extends State<_AddTrainerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un formateur'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Entrez le numéro de téléphone du compte à désigner comme '
            'formateur. Le compte doit déjà exister.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Numéro de téléphone',
              hintText: '+226 70 00 00 00',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// One trainer's businesses, with add and remove.
class _TrainerSheet extends StatefulWidget {
  const _TrainerSheet({required this.console, required this.trainer});

  final ConsoleRepository console;
  final Trainer trainer;

  @override
  State<_TrainerSheet> createState() => _TrainerSheetState();
}

class _TrainerSheetState extends State<_TrainerSheet> {
  bool _loading = true;
  List<TrainerOrg> _orgs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orgs = await widget.console.trainerOrgs(widget.trainer.userId);
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign() async {
    final org = await showModalBottomSheet<OrgRow>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BusinessPicker(console: widget.console),
    );
    if (org == null) return;
    try {
      await widget.console.assignTrainer(org.id, widget.trainer.userId);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    }
  }

  Future<void> _remove(TrainerOrg org) async {
    try {
      await widget.console.unassignTrainer(org.orgId, widget.trainer.userId);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(error))));
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.trainer.label, style: theme.textTheme.titleLarge),
          if (widget.trainer.phone != null)
            Text(widget.trainer.phone!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text('Entreprises accompagnées', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_orgs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Aucune entreprise affectée.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in _orgs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(o.name),
                      subtitle: Text(o.slug),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Retirer',
                        onPressed: () => _remove(o),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _assign,
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Affecter à une entreprise'),
          ),
        ],
      ),
    );
  }
}

/// A search-and-pick for a business, reusing the console's server-side search.
class _BusinessPicker extends StatefulWidget {
  const _BusinessPicker({required this.console});

  final ConsoleRepository console;

  @override
  State<_BusinessPicker> createState() => _BusinessPickerState();
}

class _BusinessPickerState extends State<_BusinessPicker> {
  final _controller = TextEditingController();
  bool _loading = true;
  List<OrgRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final page = await widget.console.searchOrgs(
        query: _controller.text,
        status: 'active',
        sort: 'name',
        limit: 30,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _rows = page.rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Rechercher une entreprise…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Rechercher',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _search,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in _rows)
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(o.name),
                      subtitle: Text(o.slug),
                      onTap: () => Navigator.of(context).pop(o),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

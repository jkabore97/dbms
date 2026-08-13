import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/accounting/accounting_repository.dart';
import '../../core/accounting/models.dart';
import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import 'account_ledger_screen.dart';
import 'report_shell.dart';

/// The categories money falls into, and what has landed in each.
///
/// This is the other half of letting people type their own entry names. A
/// typed name becomes an account the first time it is used, which is what
/// makes the app usable — and without a screen like this it is also what makes
/// a chart of accounts nobody can tidy. Three months of "Fourniture",
/// "Fournitures" and "fourniture bureau" need somewhere to be seen and
/// something to be done about them.
///
/// What can be done is deliberately limited to renaming and retiring. There is
/// no delete: an account with entries against it cannot be removed without
/// destroying the entries, and an account with none is not worth the button.
/// Retiring takes it off the list the recording sheets offer and leaves every
/// past entry exactly where it is.
///
/// Loading this screen is also what refreshes the categories the recording
/// sheets offer offline — see [LocalDb.cacheAccounts].
class ChartOfAccountsScreen extends StatefulWidget {
  const ChartOfAccountsScreen({
    super.key,
    required this.accounting,
    required this.org,
    this.db,
    this.canEdit = false,
  });

  final AccountingRepository accounting;
  final OrgSummary org;

  /// When given, the chart is mirrored to the device on every successful load.
  final LocalDb? db;

  /// Renaming and retiring are admin-only server-side. The buttons are hidden
  /// otherwise, which is a courtesy — 004 refuses the write either way.
  final bool canEdit;

  @override
  State<ChartOfAccountsScreen> createState() => _ChartOfAccountsScreenState();
}

class _ChartOfAccountsScreenState extends State<ChartOfAccountsScreen> {
  List<LedgerAccount> _accounts = const [];
  bool _loading = true;
  bool _showRetired = false;
  Object? _error;

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
      final accounts = await widget.accounting.chartOfAccounts(widget.org.id);

      // The device's copy, so a phone at the farm gate still offers the names
      // the books actually use rather than falling back to whatever it
      // happens to have recorded before.
      await widget.db?.cacheAccounts(
        widget.org.id,
        accounts.map((a) => a.toCache()).toList(),
      );

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final result = await showModalBottomSheet<({String name, String type, String? note})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewAccountSheet(),
    );
    if (result == null) return;

    await _guard(() async {
      await widget.accounting.createAccount(
        orgId: widget.org.id,
        name: result.name,
        type: result.type,
        description: result.note,
      );
    });
  }

  Future<void> _rename(LedgerAccount account) async {
    final result = await showDialog<({String name, String note})>(
      context: context,
      builder: (_) => _RenameAccountDialog(account: account),
    );
    if (result == null || result.name.isEmpty) return;

    await _guard(() => widget.accounting.updateAccount(
          account.id,
          name: result.name,
          description: result.note,
        ));
  }

  Future<void> _setActive(LedgerAccount account, bool active) async {
    await _guard(
      () => widget.accounting.updateAccount(account.id, isActive: active),
    );
  }

  /// Every write goes through here: run it, say what went wrong if anything
  /// did, and reload. Reloading rather than patching the list in place because
  /// the server may have done something other than what was asked — renaming
  /// into a name that already exists, most obviously.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_describe(error))),
      );
    }
  }

  static String _describe(Object error) {
    final text = error.toString();
    if (text.contains('already exists')) {
      return 'Un compte porte déjà ce nom.';
    }
    if (text.contains('administrator')) {
      return 'Seul un administrateur peut modifier le plan comptable.';
    }
    return 'Échec : la modification n\'a pas été enregistrée.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.org.currency);

    final visible = _showRetired
        ? _accounts
        : _accounts.where((a) => a.isActive).toList();
    final retiredCount = _accounts.where((a) => !a.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan comptable'),
        actions: [
          if (retiredCount > 0)
            IconButton(
              tooltip: _showRetired
                  ? 'Masquer les comptes retirés'
                  : 'Afficher les comptes retirés ($retiredCount)',
              icon: Icon(
                _showRetired ? Icons.visibility_off : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showRetired = !_showRetired),
            ),
        ],
      ),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Compte'),
            )
          : null,
      body: ReportBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        isEmpty: visible.isEmpty,
        emptyMessage: 'Aucun compte pour le moment. '
            'Le premier est créé tout seul, la première fois que quelqu\'un '
            'enregistre une entrée.',
        child: ListView(
          children: [
            for (final type in accountTypes.keys)
              ..._sectionFor(type, visible, money, theme),
            const SizedBox(height: 96),
          ],
        ),
      ),
    );
  }

  List<Widget> _sectionFor(
    String type,
    List<LedgerAccount> accounts,
    NumberFormat money,
    ThemeData theme,
  ) {
    final rows = accounts.where((a) => a.type == type).toList();
    if (rows.isEmpty) return const [];

    var total = 0.0;
    for (final row in rows) {
      total += row.balance;
    }

    return [
      SectionHeader(title: accountTypes[type]!, trailing: money.format(total)),
      for (final account in rows)
        _AccountTile(
          account: account,
          money: money,
          canEdit: widget.canEdit,
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AccountLedgerScreen(
                accounting: widget.accounting,
                org: widget.org,
                account: account,
              ),
            ),
          ),
          onRename: () => _rename(account),
          onToggleActive: () => _setActive(account, !account.isActive),
        ),
    ];
  }
}

/// Renaming an account, with the dialog owning its own controllers.
///
/// `showDialog`'s future completes the moment the route is popped, but the
/// route keeps building its content for the length of the exit animation.
/// Controllers disposed as soon as the future returns are therefore disposed
/// while live TextFields still hold them, which throws on the next frame.
class _RenameAccountDialog extends StatefulWidget {
  const _RenameAccountDialog({required this.account});

  final LedgerAccount account;

  @override
  State<_RenameAccountDialog> createState() => _RenameAccountDialogState();
}

class _RenameAccountDialogState extends State<_RenameAccountDialog> {
  late final _nameController = TextEditingController(text: widget.account.name);
  late final _noteController =
      TextEditingController(text: widget.account.description ?? '');

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;

    return AlertDialog(
      title: const Text('Renommer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nom',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'À quoi sert ce compte',
              hintText: 'Pour ceux qui liront ce plan dans deux ans',
              border: OutlineInputBorder(),
            ),
          ),
          if (account.hasHistory) ...[
            const SizedBox(height: 12),
            Text(
              '${account.entryCount} écriture'
              '${account.entryCount > 1 ? 's' : ''} portent déjà ce nom. '
              'Le renommer les renomme toutes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            name: _nameController.text.trim(),
            note: _noteController.text.trim(),
          )),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.money,
    required this.canEdit,
    required this.onOpen,
    required this.onRename,
    required this.onToggleActive,
  });

  final LedgerAccount account;
  final NumberFormat money;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = !account.isActive;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        account.label,
        style: TextStyle(
          color: faded ? theme.colorScheme.onSurfaceVariant : null,
          fontStyle: faded ? FontStyle.italic : null,
        ),
      ),
      subtitle: Text(
        [
          account.code,
          if (account.description != null) account.description!,
          if (faded) 'retiré',
          if (account.entryCount == 0) 'jamais utilisé',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            money.format(account.balance),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: faded ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
          if (canEdit)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') onRename();
                if (value == 'toggle') onToggleActive();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(faded ? 'Remettre en service' : 'Retirer'),
                ),
              ],
            )
          else
            const Icon(Icons.chevron_right, size: 18),
        ],
      ),
      onTap: onOpen,
    );
  }
}

/// Adding a category on purpose rather than as a side effect of recording
/// something. The type has to be chosen here, which is the reason this is a
/// sheet and not the one-line dialog the recording flow uses: an account is
/// only useful if it is on the right side of the books, and that is the one
/// thing the recording flow can infer and this cannot.
class _NewAccountSheet extends StatefulWidget {
  const _NewAccountSheet();

  @override
  State<_NewAccountSheet> createState() => _NewAccountSheetState();
}

class _NewAccountSheetState extends State<_NewAccountSheet> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  String _type = 'expense';

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _nameController.text.trim();

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
          Text('Nouveau compte', style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nom',
              hintText: 'Emprunt bancaire',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Nature', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in accountTypes.entries)
                ChoiceChip(
                  label: Text(accountTypeLabel(entry.key)),
                  selected: _type == entry.key,
                  onSelected: (_) => setState(() => _type = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            accountTypes[_type]!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'À quoi il sert (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.pop(context, (
                        name: name,
                        type: _type,
                        note: _noteController.text.trim().isEmpty
                            ? null
                            : _noteController.text.trim(),
                      )),
              child: const Text('Créer'),
            ),
          ),
        ],
      ),
    );
  }
}

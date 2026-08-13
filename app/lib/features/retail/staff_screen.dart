import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/models.dart';
import '../../core/retail/staff.dart';

/// Who gets paid, and what they are owed right now.
///
/// The screen leads with what is owed rather than with a list of people,
/// because that is the question being asked when somebody opens it: it is
/// Saturday evening and there are three helpers standing in the shop waiting
/// to be paid.
///
/// Paying does not ask for an amount. The server computes it from the hours
/// nobody has settled yet and marks those shifts as covered in the same
/// transaction, which is what stops the same afternoon being paid for twice —
/// the failure this screen exists to prevent, and the one nobody notices until
/// the month's wages are a third higher than they should be.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.org, required this.staff});

  final OrgSummary org;
  final StaffRepository staff;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  late final NumberFormat _money = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: widget.org.currency,
    decimalDigits: 0,
  );

  List<Employee> _people = const [];
  List<UnpaidWork> _owed = const [];
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
      final people = await widget.staff.employees(widget.org.id);
      final owed = await widget.staff.owed(widget.org.id);
      if (!mounted) return;
      setState(() {
        _people = people;
        _owed = owed;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  double? _owedFor(String employeeId) {
    for (final work in _owed) {
      if (work.employeeId == employeeId) return work.owed;
    }
    return null;
  }

  Future<void> _addPerson() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPersonSheet(org: widget.org, staff: widget.staff),
    );
    if (added == true) await _load();
  }

  Future<void> _recordShift(Employee person) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ShiftSheet(
        org: widget.org,
        staff: widget.staff,
        person: person,
      ),
    );
    if (recorded == true) await _load();
  }

  Future<void> _pay(Employee person) async {
    final owed = _owedFor(person.id);
    final amount = person.isCasual ? owed : person.salary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payer ${person.fullName} ?'),
        content: Text(
          amount == null || amount == 0
              ? "Rien à payer pour l'instant."
              : '${_money.format(amount)}'
                  '${person.isCasual ? ", pour les heures non réglées." : ", salaire."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          if (amount != null && amount > 0)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Payer'),
            ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.staff.pay(
        orgId: widget.org.id,
        employeeId: person.id,
        // One per payment, so a retry after a timeout cannot pay twice.
        clientUuid: const Uuid().v4(),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${person.fullName} payé.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalOwed = _owed.fold<double>(0, (sum, w) => sum + w.owed);

    return Scaffold(
      appBar: AppBar(title: const Text('Personnel')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPerson,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Ajouter'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),

            if (totalOwed > 0) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('À payer', style: theme.textTheme.titleMedium),
                    Text(
                      _money.format(totalOwed),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (!_loading && _people.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'Personne pour le moment.\n'
                  'Ajoutez les personnes que vous payez — elles n’ont pas '
                  'besoin de compte dans l’application.',
                  textAlign: TextAlign.center,
                ),
              ),

            ..._people.map((person) {
              final owed = _owedFor(person.id);
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  title: Text(person.fullName),
                  subtitle: Text([
                    person.isCasual
                        ? '${_money.format(person.hourlyRate)}/h'
                        : '${_money.format(person.salary)}/mois',
                    if (person.roleTitle != null) person.roleTitle!,
                    if (owed != null && owed > 0)
                      '${_money.format(owed)} à payer',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (person.isCasual)
                        IconButton(
                          icon: const Icon(Icons.more_time),
                          tooltip: 'Journée travaillée',
                          onPressed: () => _recordShift(person),
                        ),
                      IconButton(
                        icon: const Icon(Icons.payments_outlined),
                        tooltip: 'Payer',
                        onPressed: () => _pay(person),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _AddPersonSheet extends StatefulWidget {
  const _AddPersonSheet({required this.org, required this.staff});

  final OrgSummary org;
  final StaffRepository staff;

  @override
  State<_AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends State<_AddPersonSheet> {
  final _name = TextEditingController();
  final _rate = TextEditingController();
  final _role = TextEditingController();
  String _kind = 'casual';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rate = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
      await widget.staff.addEmployee(
        orgId: widget.org.id,
        fullName: _name.text.trim(),
        kind: _kind,
        hourlyRate: _kind == 'casual' ? rate : null,
        salary: _kind == 'permanent' ? rate : null,
        roleTitle: _role.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
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
            Text('Ajouter une personne', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              "Être payé et pouvoir ouvrir les comptes sont deux choses "
              "différentes : ajouter quelqu'un ici ne lui donne aucun accès.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nom',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'casual', label: Text('Journalier')),
                ButtonSegment(value: 'permanent', label: Text('Permanent')),
              ],
              selected: {_kind},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _kind == 'casual'
                    ? 'Taux horaire'
                    : 'Salaire mensuel',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _role,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Fonction (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed:
                    _name.text.trim().isEmpty || _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Ajouter', style: TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftSheet extends StatefulWidget {
  const _ShiftSheet({
    required this.org,
    required this.staff,
    required this.person,
  });

  final OrgSummary org;
  final StaffRepository staff;
  final Employee person;

  @override
  State<_ShiftSheet> createState() => _ShiftSheetState();
}

class _ShiftSheetState extends State<_ShiftSheet> {
  final _hours = TextEditingController(text: '8');

  /// One per shift, not per attempt — the same rule the sale sheet follows.
  late final String _clientUuid = const Uuid().v4();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  double? get _value =>
      double.tryParse(_hours.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final hours = _value;
    if (hours == null || hours <= 0 || hours > 24) {
      setState(() => _error = 'Entrez un nombre d’heures entre 1 et 24.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.staff.recordShift(
        orgId: widget.org.id,
        employeeId: widget.person.id,
        hours: hours,
        clientUuid: _clientUuid,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
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
          Text('Journée de ${widget.person.fullName}',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _hours,
            enabled: !_busy,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Heures travaillées',
              border: OutlineInputBorder(),
            ),
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
    );
  }
}

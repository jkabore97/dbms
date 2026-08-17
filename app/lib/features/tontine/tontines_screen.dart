import 'package:flutter/material.dart';
import '../../core/format/money.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import '../../core/tontine/tontine_repository.dart';
import '../../l10n/strings.dart';

/// The business's tontines, and the one screen a round needs: who has paid,
/// who has not, whose turn the pot is.
class TontinesScreen extends StatefulWidget {
  const TontinesScreen({
    super.key,
    required this.org,
    required this.tontine,
    this.access = OrgAccess.allEdit,
  });

  /// The owner's dial: at 'view' the rounds read, nothing is recorded.
  final OrgAccess access;

  final OrgSummary org;
  final TontineRepository tontine;

  @override
  State<TontinesScreen> createState() => _TontinesScreenState();
}

class _TontinesScreenState extends State<TontinesScreen> {
  List<TontineSummary> _rows = const [];
  bool _loading = true;
  String? _error;
  late final _money = moneyFormat(widget.org.currency);

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
      final rows = await widget.tontine.list(widget.org.id);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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
    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewTontineSheet(org: widget.org, tontine: widget.tontine),
    );
    if (made == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.tontines)),
      floatingActionButton: !widget.access.canEdit('tontines')
          ? null
          : FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.group_add_outlined),
        label: Text(strings.newTontine),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(strings.noTontines,
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        for (final t in _rows)
                          Card(
                            child: ListTile(
                              title: Text(t.name,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${_money.format(t.amount)} '
                                  '${widget.org.currency} · '
                                  '${strings.roundN(t.currentRound)}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await context.push(Routes.inside(
                                    widget.org.id, 'tontines/${t.id}'));
                                if (mounted) await _load();
                              },
                            ),
                          ),
                      ],
                    ),
    );
  }
}

/// One tontine's current round.
class TontineScreen extends StatefulWidget {
  const TontineScreen({
    super.key,
    required this.org,
    required this.tontine,
    required this.tontineId,
    this.access = OrgAccess.allEdit,
  });

  /// See [TontinesScreen.access].
  final OrgAccess access;

  final OrgSummary org;
  final TontineRepository tontine;
  final String tontineId;

  @override
  State<TontineScreen> createState() => _TontineScreenState();
}

class _TontineScreenState extends State<TontineScreen> {
  List<TontineMemberStatus> _members = const [];
  TontineSummary? _summary;
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
      final all = await widget.tontine.list(widget.org.id);
      final members = await widget.tontine.roundStatus(widget.tontineId);
      if (!mounted) return;
      setState(() {
        _summary = all.where((t) => t.id == widget.tontineId).firstOrNull;
        _members = members;
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

  Future<void> _markPaid(TontineMemberStatus m) async {
    final s = _summary;
    if (s == null) return;
    try {
      await widget.tontine.recordContribution(
        orgId: widget.org.id,
        tontineId: widget.tontineId,
        memberId: m.memberId,
        round: s.currentRound,
        amount: s.amount,
      );
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _advance() async {
    try {
      await widget.tontine.advanceRound(widget.tontineId);
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      // The server's refusal names how many have not paid — worth showing
      // verbatim, it is the tontine's contract speaking.
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final theme = Theme.of(context);
    final s = _summary;
    final allPaid = _members.isNotEmpty && _members.every((m) => m.hasPaid);

    return Scaffold(
      appBar: AppBar(title: Text(s?.name ?? strings.tontines)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (s != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(strings.roundN(s.currentRound),
                            style: theme.textTheme.titleLarge),
                      ),
                    for (final m in _members)
                      Card(
                        color: m.isTaker
                            ? theme.colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          leading: Icon(m.hasPaid
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked),
                          title: Text(m.name,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w500)),
                          subtitle: m.isTaker ? Text(strings.takesThePot) : null,
                          trailing: m.hasPaid ||
                                  !widget.access.canEdit('tontines')
                              ? null
                              : FilledButton.tonal(
                                  onPressed: () => _markPaid(m),
                                  child: Text(strings.markPaid),
                                ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        // Offered only once everyone has paid — the server
                        // enforces it anyway; hiding a button that can only
                        // refuse is kinder than showing it.
                        onPressed:
                            allPaid && widget.access.canEdit('tontines')
                                ? _advance
                                : null,
                        icon: const Icon(Icons.skip_next),
                        label: Text(strings.closeRound),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _NewTontineSheet extends StatefulWidget {
  const _NewTontineSheet({required this.org, required this.tontine});

  final OrgSummary org;
  final TontineRepository tontine;

  @override
  State<_NewTontineSheet> createState() => _NewTontineSheetState();
}

class _NewTontineSheetState extends State<_NewTontineSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _members = TextEditingController();
  String _period = 'monthly';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _members.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = Strings.of(context);
    final amount = double.tryParse(_amount.text.trim());
    final names = _members.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (_name.text.trim().isEmpty) {
      setState(() => _error = strings.enterLabel);
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = strings.enterAmount);
      return;
    }
    if (names.length < 2) {
      setState(() => _error = strings.needTwoMembers);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.tontine.create(
        orgId: widget.org.id,
        name: _name.text.trim(),
        amount: amount,
        period: _period,
        memberNames: names,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.newTontine,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: InputDecoration(labelText: strings.tontineName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: strings.amountPerRound,
                suffixText: widget.org.currency,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _period,
              decoration: InputDecoration(labelText: strings.period),
              items: [
                DropdownMenuItem(
                    value: 'daily', child: Text(strings.periodDaily)),
                DropdownMenuItem(
                    value: 'weekly', child: Text(strings.periodWeekly)),
                DropdownMenuItem(
                    value: 'monthly', child: Text(strings.periodMonthly)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _period = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _members,
              enabled: !_busy,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: strings.membersInOrder,
                helperText: strings.membersInOrderHelp,
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(strings.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

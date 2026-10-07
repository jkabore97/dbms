import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_mark.dart';
import '../cauris/cauri_icon.dart';

/// Console › Mara Pro › Cauris › « Offrir » (100): for any business — a
/// shop, a farm, an association — the platform gives cauris, gives
/// promotional cauris to spend before a day, or opens a Pro tool until a
/// date. Each reaches the business's admins on their bell. The server
/// holds the door: only Mara's admins.
class CaurisGiftsScreen extends StatefulWidget {
  const CaurisGiftsScreen({
    super.key,
    required this.console,
    required this.admin,
    required this.cauris,
  });

  final ConsoleRepository console;
  final AdminRepository admin;
  final CaurisRepository cauris;

  @override
  State<CaurisGiftsScreen> createState() => _CaurisGiftsScreenState();
}

enum GiftKind { cauris, promo, unlock }

class _CaurisGiftsScreenState extends State<CaurisGiftsScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<OrgRow> _found = const [];
  bool _searching = false;
  String? _error;

  OrgRow? _org;
  CaurisWallet? _wallet;
  FeatureStates? _states;
  List<({String feature, int cost, int minDays})> _tools = const [];

  @override
  void initState() {
    super.initState();
    _search('');
    widget.cauris.costs().then((c) {
      if (mounted) {
        setState(() => _tools = [for (final t in c) if (t.feature != 'photo_slot') t]);
      }
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _typed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final page = await widget.console.searchOrgs(query: q, limit: 20, sort: 'name');
      if (!mounted) return;
      setState(() {
        _found = page.rows;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _searching = false;
      });
    }
  }

  Future<void> _pick(OrgRow org) async {
    setState(() {
      _org = org;
      _wallet = null;
      _states = null;
    });
    await _reload();
  }

  Future<void> _reload() async {
    final org = _org;
    if (org == null) return;
    final wallet = await widget.cauris.wallet(org.id).catchError((Object _) => null);
    final states = await widget.admin.featureStates(org.id);
    if (!mounted || _org?.id != org.id) return;
    setState(() {
      _wallet = wallet;
      _states = states;
    });
  }

  Future<void> _give(GiftKind kind) async {
    final org = _org;
    if (org == null) return;
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => GiftSheet(
        org: org,
        kind: kind,
        tools: _tools,
        admin: widget.admin,
      ),
    );
    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('Offert à {name}. Ses administrateurs sont prévenus.',
            {'name': org.name})),
      ));
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = _org;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Offrir des cauris'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (org == null) ...[
            TextField(
              key: const Key('gift-search'),
              controller: _query,
              onChanged: _typed,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: context.tr('Nom de l\'entreprise'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_searching) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            for (final o in _found)
              ListTile(
                key: Key('gift-org-${o.id}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                minVerticalPadding: 12,
                leading: KindBadge(profile: o.profile),
                title: Text(o.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(kindLabel(context, o.profile)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pick(o),
              ),
          ] else ...[
            KajCard(
              margin: EdgeInsets.zero,
              child: ListTile(
                minVerticalPadding: 14,
                leading: KindBadge(profile: org.profile),
                title: Text(org.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                subtitle: Text(kindLabel(context, org.profile)),
                trailing: TextButton(
                  key: const Key('gift-change'),
                  onPressed: () => setState(() => _org = null),
                  child: Text(context.tr('Changer')),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _WalletCard(wallet: _wallet, states: _states),
            const SizedBox(height: 16),
            _ActionTile(
              key: const Key('gift-cauris'),
              icon: Icons.redeem_outlined,
              title: context.tr('Offrir des cauris'),
              line: context.tr('Ils restent jusqu\'à ce qu\'ils soient dépensés.'),
              onTap: () => _give(GiftKind.cauris),
            ),
            _ActionTile(
              key: const Key('gift-promo'),
              icon: Icons.event_outlined,
              title: context.tr('Cauris à utiliser avant une date'),
              line: context.tr('Dépensés en premier ; ce qui reste disparaît ce jour-là.'),
              onTap: () => _give(GiftKind.promo),
            ),
            _ActionTile(
              key: const Key('gift-unlock'),
              icon: Icons.lock_open_outlined,
              title: context.tr('Ouvrir un outil jusqu\'à une date'),
              line: context.tr('Offert par Mara : aucun cauri dépensé.'),
              onTap: () => _give(GiftKind.unlock),
            ),
          ],
        ],
      ),
    );
  }
}

/// A business's kind at a glance: its colour and its sign.
class KindBadge extends StatelessWidget {
  const KindBadge({super.key, required this.profile});

  final String profile;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color bg, Color fg) = switch (profile) {
      'farm' => (Icons.agriculture_outlined, maraGreen, maraPaper),
      'association' || 'church' => (Icons.volunteer_activism_outlined, maraBrown, maraPaper),
      _ => (Icons.storefront_outlined, maraCaramel, maraDeep),
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: fg),
    );
  }
}

String kindLabel(BuildContext context, String profile) => switch (profile) {
      'farm' => context.tr('Ferme'),
      'association' || 'church' => context.tr('Association'),
      'retail' => context.tr('Boutique'),
      _ => context.tr('Entreprise'),
    };

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet, required this.states});

  final CaurisWallet? wallet;
  final FeatureStates? states;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = wallet;
    final open = [
      for (final e in (states?.tools ?? const <String, ToolState>{}).entries)
        if (e.value.until != null) e,
    ];
    return Container(
      key: const Key('gift-wallet'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: maraDeep, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CauriIcon(size: 28),
              const SizedBox(width: 10),
              Text(w == null ? '…' : '${w.balance}',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(color: maraPaper, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text(context.tr('cauris'),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: maraPaper.withValues(alpha: 0.8))),
            ],
          ),
          for (final p in w?.promo ?? const <PromoLot>[])
            Text(
              context.tr('dont {n} à utiliser avant le {date}', {
                'n': p.points,
                'date': DateFormat('dd/MM').format(p.until),
              }),
              style: theme.textTheme.bodyMedium?.copyWith(color: maraCaramel),
            ),
          for (final e in open)
            Text(
              context.tr('{tool} ouvert jusqu\'au {date}', {
                'tool': e.key == 'pro_all' ? context.tr('Mara Pro complet') : PlanTerms.labelOf(e.key),
                'date': DateFormat('dd/MM').format(e.value.until!.toLocal()),
              }),
              style: theme.textTheme.bodySmall?.copyWith(color: maraPaper),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KajCard(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          minVerticalPadding: 14,
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: maraPaper,
            child: Icon(icon, color: maraBrown),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(line),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

/// One gift: how many cauris, or which tool; until when; a word for them.
class GiftSheet extends StatefulWidget {
  const GiftSheet({
    super.key,
    required this.org,
    required this.kind,
    required this.tools,
    required this.admin,
  });

  final OrgRow org;
  final GiftKind kind;
  final List<({String feature, int cost, int minDays})> tools;
  final AdminRepository admin;

  @override
  State<GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<GiftSheet> {
  final _points = TextEditingController();
  final _note = TextEditingController();
  late DateTime _until = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 30));
  String? _tool;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _points.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = widget.kind == GiftKind.promo ? today.add(const Duration(days: 1)) : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _until.isBefore(first) ? first : _until,
      firstDate: first,
      lastDate: today.add(const Duration(days: 366)),
    );
    if (picked != null) setState(() => _until = picked);
  }

  Future<void> _save() async {
    final points = int.tryParse(_points.text.trim().replaceAll(' ', ''));
    if (widget.kind != GiftKind.unlock && (points == null || points <= 0)) {
      setState(() => _error = context.tr('Combien de cauris ?'));
      return;
    }
    if (widget.kind == GiftKind.unlock && _tool == null) {
      setState(() => _error = context.tr('Quel outil ?'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (widget.kind) {
        case GiftKind.cauris:
          await widget.admin.platformGiveCauris(widget.org.id, points!, note: _note.text);
        case GiftKind.promo:
          await widget.admin.platformGiveCauris(widget.org.id, points!,
              note: _note.text, expiresOn: _until);
        case GiftKind.unlock:
          await widget.admin.platformGiveUnlock(widget.org.id, _tool!, _until,
              note: _note.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = widget.kind;
    final title = switch (kind) {
      GiftKind.cauris => context.tr('Offrir des cauris'),
      GiftKind.promo => context.tr('Cauris à utiliser avant une date'),
      GiftKind.unlock => context.tr('Ouvrir un outil jusqu\'à une date'),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            Text(widget.org.name, style: theme.textTheme.bodyMedium?.copyWith(color: maraBrown)),
            const SizedBox(height: 16),
            if (kind != GiftKind.unlock)
              TextField(
                key: const Key('gift-points'),
                controller: _points,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: theme.textTheme.headlineSmall,
                decoration: InputDecoration(
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(12),
                    child: CauriIcon(size: 22),
                  ),
                  labelText: context.tr('Cauris'),
                  border: const OutlineInputBorder(),
                ),
              )
            else
              DropdownButtonFormField<String>(
                key: const Key('gift-tool'),
                initialValue: _tool,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('Outil'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final t in widget.tools)
                    DropdownMenuItem(
                      value: t.feature,
                      child: Text(
                        t.feature == 'pro_all'
                            ? context.tr('Mara Pro complet')
                            : PlanTerms.labelOf(t.feature),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _tool = v),
              ),
            if (kind != GiftKind.cauris) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('gift-date'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : _pickDate,
                icon: const Icon(Icons.event),
                label: Text(kind == GiftKind.promo
                    ? context.tr('À utiliser avant le {date}',
                        {'date': DateFormat('dd/MM/yyyy').format(_until)})
                    : context.tr('Ouvert jusqu\'au {date} inclus',
                        {'date': DateFormat('dd/MM/yyyy').format(_until)})),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('gift-note'),
              controller: _note,
              enabled: !_busy,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: context.tr('Un mot pour eux (facultatif)'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('gift-save'),
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.redeem),
                label: Text(context.tr('Offrir'), style: const TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

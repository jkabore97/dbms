import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kaj_app/core/l10n/tr.dart';

import '../../core/admin/models.dart' show roleLabel;
import '../../core/auth/auth_repository.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';

/// Two accounts of one person, merged (168).
///
/// The owner: people sign in with Apple, then with Google, and find two
/// accounts. From a person's sheet in the console, a platform admin finds
/// the other account, chooses which one is kept, reads both side by side,
/// and types the absorbed account's email back. The server moves the
/// absorbed account's Google or Apple sign-in to the kept one — whatever
/// they sign in with now, they reach the same account — moves everything it
/// had, and deletes it. Nothing merges by itself: someone who wants two
/// accounts keeps them.
class MergeAccountsSheet extends StatefulWidget {
  const MergeAccountsSheet({super.key, required this.console, required this.person});

  final ConsoleRepository console;
  final PlatformPerson person;

  @override
  State<MergeAccountsSheet> createState() => _MergeAccountsSheetState();
}

class _MergeAccountsSheetState extends State<MergeAccountsSheet> {
  final _search = TextEditingController();
  final _confirm = TextEditingController();
  Timer? _debounce;
  List<PlatformPerson>? _found;
  PlatformPerson? _other;

  /// True: the person this sheet was opened from is kept.
  bool _keepThis = true;
  AccountMergePreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _confirm.dispose();
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
        final people = await widget.console.searchPeople(q, limit: 20);
        if (mounted) {
          setState(() => _found = [for (final p in people) if (p.userId != widget.person.userId) p]);
        }
      } catch (e) {
        if (mounted) setState(() => _error = AuthRepository.describeError(e));
      }
    });
  }

  String get _keepId => _keepThis ? widget.person.userId : _other!.userId;
  String get _absorbId => _keepThis ? _other!.userId : widget.person.userId;

  Future<void> _loadPreview() async {
    setState(() {
      _preview = null;
      _error = null;
      _confirm.clear();
    });
    try {
      final p = await widget.console.mergePreview(keepId: _keepId, absorbId: _absorbId);
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      if (mounted) setState(() => _error = AuthRepository.describeError(e));
    }
  }

  Future<void> _choose(PlatformPerson other) async {
    setState(() {
      _other = other;
      _keepThis = true;
    });
    await _loadPreview();
    // Keep the account with the email-and-password login when only one has
    // it: absorbed, that login would stop working.
    final p = _preview;
    if (p != null && p.absorb.password && !p.keep.password && mounted) {
      setState(() => _keepThis = false);
      await _loadPreview();
    }
  }

  bool get _typed {
    final p = _preview;
    return p != null && _confirm.text.trim().toLowerCase() == p.absorb.confirmLabel.trim().toLowerCase();
  }

  Future<void> _merge() async {
    final p = _preview;
    if (p == null || !_typed) return;
    final done = context.tr('Comptes fusionnés : {label} est maintenant un seul compte.', {'label': p.keep.label});
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.console.mergeAccounts(keepId: p.keep.id, absorbId: p.absorb.id, confirm: _confirm.text.trim());
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
    final other = _other;
    final p = _preview;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Fusionner deux comptes'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              context.tr('Pour une personne qui a deux comptes (par exemple Apple et Google) : après la fusion, elle retrouve le même compte, quelle que soit la façon de se connecter. Irréversible.'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (other == null) ...[
              TextField(
                key: const Key('merge-search'),
                controller: _search,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  labelText: context.tr('L\'autre compte : nom, e-mail ou téléphone'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_found != null && _found!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(context.tr('Aucun autre compte trouvé.')),
                ),
              for (final f in _found ?? const <PlatformPerson>[])
                ListTile(
                  key: Key('merge-pick-${f.userId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(f.label),
                  subtitle: Text([f.email, f.phone].whereType<String>().join(' · ')),
                  onTap: () => _choose(f),
                ),
            ] else ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(context.tr('Garder {label}', {'label': widget.person.label}),
                      overflow: TextOverflow.ellipsis)),
                  ButtonSegment(value: false, label: Text(context.tr('Garder {label}', {'label': other.label}),
                      overflow: TextOverflow.ellipsis)),
                ],
                selected: {_keepThis},
                onSelectionChanged: _busy
                    ? null
                    : (v) {
                        setState(() => _keepThis = v.first);
                        _loadPreview();
                      },
              ),
              const SizedBox(height: 12),
              if (p == null && _error == null)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              else if (p != null) ...[
                _card(context, context.tr('Gardé'), p.keep, theme.colorScheme.primary),
                const SizedBox(height: 8),
                _card(context, context.tr('Absorbé puis supprimé'), p.absorb, theme.colorScheme.error),
                const SizedBox(height: 8),
                Text(
                  context.tr('{n} élément(s) passent au compte gardé : entreprises, commandes, écritures, réglages…', {'n': p.rowCount}),
                  style: theme.textTheme.bodySmall,
                ),
                if (p.absorb.password) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr('Attention : le compte absorbé se connecte par e-mail et mot de passe. Cette connexion ne marchera plus ; la personne se connectera comme le compte gardé.'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  key: const Key('merge-confirm'),
                  controller: _confirm,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr('Pour confirmer, tapez : {label}', {'label': p.absorb.confirmLabel}),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('merge-go'),
                  style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                  onPressed: _busy || !_typed ? null : _merge,
                  icon: const Icon(Icons.call_merge),
                  label: Text(context.tr('Fusionner les comptes')),
                ),
              ],
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _other = null;
                          _preview = null;
                          _error = null;
                        }),
                child: Text(context.tr('Choisir un autre compte')),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, String title, MergeAccountCard a, Color colour) {
    final theme = Theme.of(context);
    const names = {'google': 'Google', 'apple': 'Apple', 'email': 'E-mail', 'phone': 'Téléphone'};
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: colour), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: colour)),
        const SizedBox(height: 4),
        Text(a.label, style: theme.textTheme.titleMedium),
        if (a.email != null) Text(a.email!, style: theme.textTheme.bodySmall),
        Text(
          context.tr('Connexion : {ways}', {
            'ways': a.providers.isEmpty
                ? (a.password ? context.tr('E-mail') : '—')
                : a.providers.map((p) => context.tr(names[p] ?? p)).join(', '),
          }),
          style: theme.textTheme.bodySmall,
        ),
        if (a.businesses.isEmpty)
          Text(context.tr('Aucune entreprise.'), style: theme.textTheme.bodySmall)
        else
          for (final b in a.businesses) Text('• ${b.org} · ${roleLabel(b.role)}', style: theme.textTheme.bodySmall),
      ]),
    );
  }
}

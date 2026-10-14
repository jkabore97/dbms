import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/bell_room.dart';
import '../../core/terms/terms.dart';
import '../../core/theme/kaj_card.dart';
import '../account/terms_words.dart';

/// Réglages › Sécurité › « Conditions d'utilisation » (142, batch 147): each
/// document's version, since when, and how many people accepted it; and
/// « Nouvelle version » — everyone is asked again at their next opening of
/// Mara, the server still letting the accounts already here through for
/// the days chosen. The words themselves live in the app (legal_screens.dart
/// and the site): a new version is for a new text, shipped first.
class TermsAdminScreen extends StatefulWidget {
  const TermsAdminScreen({super.key, this.api});

  /// The server; the app's unless a test gives one.
  final TermsApi? api;

  @override
  State<TermsAdminScreen> createState() => _TermsAdminScreenState();
}

class _TermsAdminScreenState extends State<TermsAdminScreen> {
  late final TermsApi _api = widget.api ?? SupabaseTermsApi(AppScope.read(context)?.auth.client);
  TermsBoard? _board;
  bool _loading = true;
  bool _installed = true;
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
      final b = await _api.board();
      if (!mounted) return;
      setState(() {
        _board = b;
        _installed = b != null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _day(BuildContext context, DateTime? d) => d == null ? '—' : termsDateTime(context, d).split(',').first;

  Future<void> _bump() async {
    final asked = await showDialog<_Bump>(context: context, builder: (_) => const _BumpDialog());
    if (asked == null || !mounted) return;
    final names = asked.docs.map((d) => termsDocName(context, d)).join(', ');
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('terms-bump-confirm'),
        scrollable: true,
        title: Text(dialog.tr('Demander à tout le monde d\'accepter à nouveau ?')),
        content: Text(dialog.tr(
            'Tout le monde devra accepter à nouveau : {docs}, à sa prochaine ouverture de Mara. Pendant {n} jours, le serveur laisse encore passer les comptes déjà là ; ensuite, il refuse leurs commandes et leurs créations tant qu\'ils n\'ont pas accepté.',
            {'docs': names, 'n': asked.graceDays})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(dialog.tr('Annuler'))),
          FilledButton(
            key: const Key('terms-bump-go'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(dialog.tr('Confirmer')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final done = context.tr('Nouvelle version publiée : tout le monde sera invité à l\'accepter.');
    try {
      final b = await _api.bump(asked.docs,
          changes: asked.changes, changesEn: asked.changesEn, graceDays: asked.graceDays);
      if (!mounted) return;
      setState(() => _board = b);
      messenger?.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = _board;
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
          ]),
        ),
      );
    } else if (!_installed || b == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('Les acceptations arrivent avec la migration 142 : en attendant, personne n\'est interrogé.'),
            key: const Key('terms-admin-before'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = ListView(
        key: const Key('terms-admin'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            context.tr('Chaque personne accepte ces documents dans l\'application avant de continuer ; le serveur refuse une commande, une création d\'activité ou une demande de livreur sans eux.'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          for (final d in TermsDoc.all)
            KajCard(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                key: Key('terms-admin-$d'),
                title: Text(termsDocName(context, d), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  context.tr('Version {n}, depuis le {date}',
                      {'n': b.documents[d]!.version, 'date': _day(context, b.documents[d]!.since)}),
                  context.tr('{a} personnes l\'ont acceptée, sur {p} comptes',
                      {'a': b.documents[d]!.accepted, 'p': b.people}),
                  if (b.documents[d]!.graceUntil case final g? when g.isAfter(DateTime.now()))
                    context.tr('Comptes déjà là laissés passer jusqu\'au {date}', {'date': _day(context, g)}),
                ].join('\n')),
                isThreeLine: true,
              ),
            ),
          if (b.changesIn(context.trLanguage) case final c?) ...[
            const SizedBox(height: 4),
            Text(context.tr('Ce qui change : {changes}', {'changes': c}), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('terms-bump'),
            onPressed: _bump,
            icon: const Icon(Icons.campaign_outlined),
            label: Text(context.tr('Nouvelle version…')),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('Changez d\'abord le texte dans l\'application et sur le site : une nouvelle version ne change pas les mots, elle demande seulement à tout le monde de les accepter à nouveau.'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(actions: const [bellRoom], title: Text(context.tr('Conditions d\'utilisation'))),
      body: body,
    );
  }
}

extension on TermsBoard {
  String? changesIn(String language) {
    final en = changesEn?.trim();
    final fr = changes?.trim();
    if (language == 'en' && en != null && en.isNotEmpty) return en;
    return fr == null || fr.isEmpty ? null : fr;
  }
}

class _Bump {
  const _Bump(this.docs, this.changes, this.changesEn, this.graceDays);
  final List<String> docs;
  final String changes;
  final String? changesEn;
  final int graceDays;
}

/// Which documents, what changed (French, and English if typed), and how
/// many days the accounts already here are still let through.
class _BumpDialog extends StatefulWidget {
  const _BumpDialog();

  @override
  State<_BumpDialog> createState() => _BumpDialogState();
}

class _BumpDialogState extends State<_BumpDialog> {
  final _docs = <String>{TermsDoc.terms, TermsDoc.privacy};
  final _changes = TextEditingController();
  final _changesEn = TextEditingController();
  final _days = TextEditingController(text: '14');

  @override
  void dispose() {
    _changes.dispose();
    _changesEn.dispose();
    _days.dispose();
    super.dispose();
  }

  int? get _grace {
    final n = int.tryParse(_days.text.trim());
    return n == null || n < 0 || n > 90 ? null : n;
  }

  bool get _ready => _docs.isNotEmpty && _changes.text.trim().isNotEmpty && _grace != null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('terms-bump-form'),
      scrollable: true,
      title: Text(context.tr('Nouvelle version')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in TermsDoc.all)
            CheckboxListTile(
              key: Key('terms-bump-$d'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _docs.contains(d),
              onChanged: (v) => setState(() => v == true ? _docs.add(d) : _docs.remove(d)),
              title: Text(termsDocName(context, d)),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('terms-bump-changes'),
            controller: _changes,
            maxLength: 200,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('Ce qui change, en une phrase'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('terms-bump-changes-en'),
            controller: _changesEn,
            maxLength: 200,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.tr('La même phrase en anglais (facultatif)'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('terms-bump-days'),
            controller: _days,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('Jours pendant lesquels les comptes déjà là passent encore (0 à 90)'),
              errorText: _grace == null ? context.tr('De 0 à 90 jours.') : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Annuler'))),
        FilledButton(
          key: const Key('terms-bump-next'),
          onPressed: _ready
              ? () => Navigator.pop(
                  context,
                  _Bump([for (final d in TermsDoc.all) if (_docs.contains(d)) d], _changes.text.trim(),
                      _changesEn.text.trim().isEmpty ? null : _changesEn.text.trim(), _grace!))
              : null,
          child: Text(context.tr('Suivant')),
        ),
      ],
    );
  }
}

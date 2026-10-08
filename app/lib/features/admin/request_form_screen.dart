import 'package:flutter/material.dart';

import '../../core/console/command_center.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/onboarding/application_form.dart';
import '../../core/onboarding/onboarding_repository.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/onboarding/business_creation.dart';
import '../setup/create_my_business_screen.dart';

/// « Parcours de création » in the command center (107, renamed in 111):
/// the questions somebody answers to create their business at once
/// (CreateMyBusinessScreen) — the page that once asked for one. Mara writes
/// its welcome, chooses which kinds may be created, and adds questions — a
/// text, a choice in a list, a number, yes or no; each with its help and
/// « obligatoire » — each a screen of its own, in order, after the ones
/// always asked (the kind, the name and address, what it does, the town,
/// the phone and currency).
///
/// Saved through platform_set_application_form (the platform's, checked by
/// the server, in the journal with « Annuler »). Nothing set — or « Page
/// d'origine » — is today's page. The preview beside it (or behind
/// « Aperçu » on a phone) is the page itself, drawn with what is typed.
class RequestFormScreen extends StatefulWidget {
  const RequestFormScreen({super.key, this.onboarding, this.undo});

  /// Stands in for the server in a test; the app's own otherwise.
  final OnboardingRepository? onboarding;

  /// « Annuler »: the journal's undo (104); the command center's otherwise.
  final Future<void> Function(String actionId)? undo;

  @override
  State<RequestFormScreen> createState() => _RequestFormScreenState();
}

/// A question being written: its fields, as typed.
class _Draft {
  _Draft([FormQuestion? q])
      : id = q?.id,
        label = TextEditingController(text: q?.label ?? ''),
        help = TextEditingController(text: q?.help ?? ''),
        options = TextEditingController(text: (q?.options ?? const []).join('\n')),
        type = q?.type ?? QuestionType.text,
        required = q?.required ?? false;

  final String? id;
  final TextEditingController label;
  final TextEditingController help;

  /// One answer offered per line, for a choice.
  final TextEditingController options;
  QuestionType type;
  bool required;

  FormQuestion get question => FormQuestion(
        id: id,
        label: label.text.trim(),
        help: help.text.trim().isEmpty ? null : help.text.trim(),
        required: required,
        type: type,
        options: [
          for (final o in options.text.split('\n'))
            if (o.trim().isNotEmpty) o.trim(),
        ],
      );

  void dispose() {
    label.dispose();
    help.dispose();
    options.dispose();
  }
}

class _RequestFormScreenState extends State<RequestFormScreen> {
  late final OnboardingRepository _onboarding =
      widget.onboarding ?? AppScope.read(context)!.onboarding;
  late final Future<void> Function(String) _undo = widget.undo ??
      CommandCenterRepository(AppScope.read(context)?.auth.client).undo;

  final _welcome = TextEditingController();
  final _kinds = {...ApplicationForm.allKinds};
  final _drafts = <_Draft>[];
  bool _loading = true;
  bool _busy = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _welcome.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _welcome.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final form = await _onboarding.applicationForm(strict: true);
      if (!mounted) return;
      setState(() => _fill(form));
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(ApplicationForm? form) {
    _welcome.text = form?.welcome ?? '';
    _kinds
      ..clear()
      ..addAll(form?.kinds ?? ApplicationForm.allKinds);
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts
      ..clear()
      ..addAll([for (final q in form?.questions ?? const <FormQuestion>[]) _watch(_Draft(q))]);
    _saved = form != null;
  }

  _Draft _watch(_Draft d) {
    d.label.addListener(_changed);
    d.help.addListener(_changed);
    d.options.addListener(_changed);
    return d;
  }

  /// The page as typed, in the server's shape.
  ApplicationForm get _form => ApplicationForm(
        welcome: _welcome.text.trim().isEmpty ? null : _welcome.text.trim(),
        kinds: _kinds.length == ApplicationForm.allKinds.length
            ? null
            : [for (final k in ApplicationForm.allKinds) if (_kinds.contains(k)) k],
        questions: [for (final d in _drafts) d.question],
      );

  /// What the page cannot be saved with, said before the server says it.
  String? get _problem {
    if (_kinds.isEmpty) return context.tr('Proposez au moins un type d\'activité.');
    for (final q in _form.questions) {
      if (q.label.isEmpty) return context.tr('Chaque question a son intitulé.');
      if (q.type == QuestionType.choice && (q.options.length < 2 || q.options.length > 12)) {
        return context.tr('Une question à choix a de 2 à 12 réponses.');
      }
    }
    if (_drafts.length > 12) return context.tr('Douze questions au plus.');
    return null;
  }

  Future<void> _save({bool original = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final done = original
        ? context.tr('Parcours d\'origine remis. Le journal le garde.')
        : context.tr('Parcours de création enregistré. Le journal le garde.');
    final same = context.tr('Rien n\'a changé.');
    final undoLabel = context.tr('Annuler');
    setState(() => _busy = true);
    try {
      final id = await _onboarding.setApplicationForm(original ? null : _form);
      messenger.showSnackBar(SnackBar(
        content: Text(id == null ? same : done),
        action: id == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () async {
                  try {
                    await _undo(id);
                  } catch (error) {
                    messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
                  }
                  if (mounted) await _load();
                },
              ),
      ));
      await _load();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _original() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Revenir au parcours d\'origine ?')),
        content: Text(context.tr('Le mot d\'accueil et les questions sont retirés ; les trois types sont proposés. Les activités déjà créées gardent leurs réponses.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Remettre le parcours d\'origine')),
          ),
        ],
      ),
    );
    if (ok == true) await _save(original: true);
  }

  void _add() => setState(() => _drafts.add(_watch(_Draft())));

  void _move(int i, int by) => setState(() {
        final d = _drafts.removeAt(i);
        _drafts.insert(i + by, d);
      });

  void _remove(int i) => setState(() => _drafts.removeAt(i).dispose());

  /// The creation itself, drawn with what is typed: nothing read or sent.
  Widget _preview() => CreateMyBusinessScreen(
        api: SupabaseBusinessCreation(null),
        previewForm: _form,
      );

  void _openPreview() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _preview(),
      ));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final problem = _problem;
    final editor = ListView(
      key: const Key('form-editor'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
        ],
        Text(
          _saved
              ? context.tr('Le parcours de création est celui de Mara.')
              : context.tr('Le parcours de création est celui d\'origine.'),
          key: const Key('form-state'),
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('Toujours demandés, un par écran : le type, le nom et son adresse (marakaj.com/s/…), ce que fait l\'activité, la ville et le quartier, le téléphone et la monnaie. Vos questions viennent ensuite, une par écran.'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('form-welcome'),
          controller: _welcome,
          enabled: !_busy,
          maxLines: 3,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.tr('Mot d\'accueil'),
            hintText: context.tr('Ex. : Bienvenue ! Votre activité est prête en cinq minutes.'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(context.tr('Types proposés'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (k, label) in [
              ('association', context.tr('Association')),
              ('farm', context.tr('Ferme')),
              ('retail', context.tr('Boutique')),
            ])
              FilterChip(
                key: Key('form-kind-$k'),
                label: Text(label),
                selected: _kinds.contains(k),
                selectedColor: maraCaramel,
                onSelected: _busy
                    ? null
                    : (on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(context.tr('Questions en plus'), style: theme.textTheme.titleSmall),
            ),
            Text('${_drafts.length} / 12', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 8),
        for (final (i, d) in _drafts.indexed) _questionCard(theme, i, d),
        OutlinedButton.icon(
          key: const Key('form-add'),
          onPressed: _busy || _drafts.length >= 12 ? null : _add,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.add),
          label: Text(context.tr('Ajouter une question')),
        ),
        const SizedBox(height: 20),
        if (problem != null) ...[
          Text(problem,
              key: const Key('form-problem'),
              style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('form-save'),
              onPressed: _busy || _loading || problem != null ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.check),
              label: Text(context.tr('Enregistrer le parcours')),
            ),
            if (!wide)
              OutlinedButton.icon(
                key: const Key('form-preview'),
                onPressed: _openPreview,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(context.tr('Aperçu du parcours')),
              ),
            if (_saved)
              TextButton(
                key: const Key('form-original'),
                onPressed: _busy ? null : _original,
                child: Text(context.tr('Remettre le parcours d\'origine')),
              ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Parcours de création'))),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: editor),
                Container(
                  width: 420,
                  color: maraPaper,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(context.tr('Aperçu du parcours'),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: maraDeep.withValues(alpha: 0.25)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: _preview(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : editor,
    );
  }

  Widget _questionCard(ThemeData theme, int i, _Draft d) => KajCard(
        key: Key('form-q-$i'),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: maraCaramel,
                    child: Text('${i + 1}',
                        style: const TextStyle(color: maraDeep, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<QuestionType>(
                      key: Key('form-q-$i-type'),
                      value: d.type,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      onChanged: _busy ? null : (t) => setState(() => d.type = t ?? d.type),
                      items: [
                        DropdownMenuItem(value: QuestionType.text, child: Text(context.tr('Texte'))),
                        DropdownMenuItem(value: QuestionType.choice, child: Text(context.tr('Choix dans une liste'))),
                        DropdownMenuItem(value: QuestionType.number, child: Text(context.tr('Nombre'))),
                        DropdownMenuItem(value: QuestionType.yesno, child: Text(context.tr('Oui ou non'))),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('Monter'),
                    onPressed: _busy || i == 0 ? null : () => _move(i, -1),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: context.tr('Descendre'),
                    onPressed: _busy || i == _drafts.length - 1 ? null : () => _move(i, 1),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: context.tr('Retirer'),
                    onPressed: _busy ? null : () => _remove(i),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                key: Key('form-q-$i-label'),
                controller: d.label,
                enabled: !_busy,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('La question'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                key: Key('form-q-$i-help'),
                controller: d.help,
                enabled: !_busy,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: context.tr('Aide (facultatif)'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (d.type == QuestionType.choice) ...[
                const SizedBox(height: 4),
                TextField(
                  key: Key('form-q-$i-options'),
                  controller: d.options,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: context.tr('Les réponses, une par ligne'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              SwitchListTile(
                key: Key('form-q-$i-required'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Obligatoire')),
                value: d.required,
                onChanged: _busy ? null : (v) => setState(() => d.required = v),
              ),
            ],
          ),
        ),
      );
}

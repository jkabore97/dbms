import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/onboarding/application_form.dart';
import '../../core/onboarding/onboarding_repository.dart';
import '../../core/theme/mara_mark.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Making a new business — the one screen only Kaj-consulting sees.
///
/// Every other org in the app arrives by invitation. This is where the first
/// one comes from, and it is reachable only for a profile carrying
/// `is_platform_admin`. The flag is checked again inside `create_org`, so
/// reaching this screen by any other route still fails at the server.
///
/// The profile choice is the consequential field and cannot be changed
/// afterwards from a phone — it decides which home screen every member of the
/// business lands on, and `org_settings_screen.dart` deliberately omits it. So
/// it is a visible list of options here rather than a dropdown default nobody
/// reads.
class CreateBusinessScreen extends StatefulWidget {
  const CreateBusinessScreen({
    super.key,
    required this.admin,
    this.onboarding,
    this.asApplication = false,
    this.previewForm,
  });

  final AdminRepository admin;

  /// Only needed when this is an application rather than a creation.
  final OnboardingRepository? onboarding;

  /// When true this screen files a request instead of making a business.
  ///
  /// Same fields either way, and deliberately so: what a platform admin fills
  /// in to create one and what a manager fills in to ask for one are the same
  /// facts. What differs is who decides — `create_org()` is platform-admin
  /// only and always has been — and so what the button says and what comes
  /// back. A creation pops the new org's id; an application pops true.
  final bool asApplication;

  /// The request page as Mara is shaping it (107's RequestFormScreen): the
  /// page drawn with this form instead of the server's, and nothing sent.
  final ApplicationForm? previewForm;

  /// Lowercases, strips accents, and hyphenates — the name as typed turned
  /// into something that can live in a hostname.
  ///
  /// Kept static and pure so the rules are testable without a server: this
  /// becomes a live subdomain, and "Église d'Israël" has to survive the trip.
  static String slugify(String name) {
    const accents = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
    const plain = 'aaaaaaceeeeiiiinooooouuuuyy';

    final buffer = StringBuffer();
    for (final rune in name.toLowerCase().trim().runes) {
      final ch = String.fromCharCode(rune);
      final i = accents.indexOf(ch);
      buffer.write(i >= 0 ? plain[i] : ch);
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Null when the slug is usable, otherwise why it is not.
  static String? slugProblem(String slug) {
    if (slug.length < 3) return 'Au moins 3 caractères.';
    if (slug.length > 40) return 'Au plus 40 caractères.';
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      return 'Lettres sans accent, chiffres et tirets uniquement.';
    }
    if (slug.startsWith('-') || slug.endsWith('-')) {
      return 'Ne peut pas commencer ni finir par un tiret.';
    }
    return null;
  }

  @override
  State<CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

/// The profiles a business can be created as — each one the app has a real
/// home screen for. 'generic' ("Autre") is deliberately absent: it made an
/// empty business with no dedicated module, which was more confusing than
/// useful to offer. Existing generic businesses keep working (the server still
/// accepts the value and their home screen still renders); it is simply no
/// longer something new businesses are created as.
const _profiles =
    <({String value, String label, String detail, IconData icon})>[
  (
    value: 'association',
    label: 'Association',
    detail: 'Membres, cotisations, dépenses, résumé',
    icon: Icons.groups_outlined,
  ),
  (
    value: 'farm',
    label: 'Ferme',
    detail: 'Stock, troupeaux, production, factures',
    icon: Icons.agriculture_outlined,
  ),
  (
    value: 'retail',
    label: 'Commerce',
    detail: 'Ventes et dépenses',
    icon: Icons.storefront_outlined,
  ),
];

class _CreateBusinessScreenState extends State<CreateBusinessScreen> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _currencyController = TextEditingController(text: 'XOF');

  /// Only shown on an application: a reviewer deciding whether a business
  /// should exist needs a sentence about it, and a creation by a platform
  /// admin is being decided by the person typing.
  final _descriptionController = TextEditingController();

  String _profile = 'association';

  /// The request page Mara set (107): a welcome, the kinds offered, extra
  /// questions. Null — no form, no server, a database before 107 — is
  /// today's page, field for field.
  ApplicationForm? _form;

  /// The answers to [_form]'s questions: a controller for the typed ones,
  /// the chosen value for a choice or a yes/no. By question id.
  final _typed = <String, TextEditingController>{};
  final _picked = <String, Object>{};

  /// True once the slug has been edited by hand, after which typing the name
  /// stops overwriting it — otherwise a deliberate slug is silently undone by
  /// the next keystroke in the field above.
  bool _slugTouched = false;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    if (widget.previewForm != null) {
      _useForm(widget.previewForm);
    } else if (widget.asApplication && widget.onboarding != null) {
      widget.onboarding!.applicationForm().then((form) {
        if (mounted && form != null) setState(() => _useForm(form));
      });
    }
  }

  @override
  void didUpdateWidget(CreateBusinessScreen old) {
    super.didUpdateWidget(old);
    if (widget.previewForm != null && widget.previewForm != old.previewForm) {
      _useForm(widget.previewForm);
    }
  }

  void _useForm(ApplicationForm? form) {
    _form = form;
    for (final q in form?.questions ?? const <FormQuestion>[]) {
      final id = _idOf(q);
      if (q.type == QuestionType.text || q.type == QuestionType.number) {
        _typed.putIfAbsent(id, () => TextEditingController()..addListener(_refresh));
      }
    }
    // A kind the page no longer offers is not left chosen.
    final offered = _offered;
    if (offered.isNotEmpty && !offered.any((p) => p.value == _profile)) {
      _profile = offered.first.value;
    }
  }

  void _refresh() => setState(() {});

  /// A question not saved yet (the preview) answers under its place.
  String _idOf(FormQuestion q) => q.id ?? 'q${_form!.questions.indexOf(q)}';

  List<({String value, String label, String detail, IconData icon})> get _offered => [
        for (final p in _profiles)
          if (!widget.asApplication || (_form?.offers(p.value) ?? true)) p,
      ];

  /// Each answer as the server takes it; null when not answered.
  Object? _answerOf(FormQuestion q) {
    final id = _idOf(q);
    switch (q.type) {
      case QuestionType.text:
        final t = _typed[id]?.text.trim() ?? '';
        return t.isEmpty ? null : t;
      case QuestionType.number:
        final t = (_typed[id]?.text ?? '').replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
        return t.isEmpty ? null : num.tryParse(t) ?? t;
      case QuestionType.choice:
      case QuestionType.yesno:
        return _picked[id];
    }
  }

  bool get _answered {
    if (!widget.asApplication) return true;
    for (final q in _form?.questions ?? const <FormQuestion>[]) {
      final a = _answerOf(q);
      if (q.required && a == null) return false;
      if (q.type == QuestionType.number && a is String) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _slugController.dispose();
    _currencyController.dispose();
    _descriptionController.dispose();
    for (final c in _typed.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onNameChanged() {
    if (!_slugTouched) {
      _slugController.text = CreateBusinessScreen.slugify(_nameController.text);
    }
    // Rebuilds so the Create button follows what has been typed. The button is
    // a pure function of the fields; without this it never wakes up.
    setState(() {});
  }

  String get _name => _nameController.text.trim();
  String get _slug => _slugController.text.trim();
  String get _currency => _currencyController.text.trim().toUpperCase();

  bool get _ready =>
      _name.isNotEmpty &&
      CreateBusinessScreen.slugProblem(_slug) == null &&
      _currency.length == 3 &&
      _answered;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (widget.asApplication) {
        final onboarding = widget.onboarding;
        if (onboarding == null) {
          throw StateError('Cet écran a été ouvert sans service de demande.');
        }
        final questions = _form?.questions ?? const <FormQuestion>[];
        await onboarding.applyForOrg(
          name: _name,
          slug: _slug,
          profile: _profile,
          currency: _currency,
          description: _descriptionController.text.trim(),
          answers: questions.isEmpty
              ? null
              : {
                  for (final q in questions)
                    if (q.id != null) q.id!: _answerOf(q),
                },
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final orgId = await widget.admin.createOrg(
          name: _name,
          slug: _slug,
          profile: _profile,
          currency: _currency,
        );
        if (mounted) Navigator.of(context).pop(orgId);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The two failures worth naming. A duplicate slug is the one a person can
  /// actually fix, and the raw Postgres text for it names a constraint rather
  /// than the field they typed in.
  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('orgs_slug_key') || text.contains('duplicate key')) {
      return context.tr('L\'adresse « {_slug} » est déjà utilisée par une autre activité.', {'_slug': _slug});
    }
    if (text.contains('Only a platform admin')) {
      return context.tr('Ce compte n\'a pas le droit de créer une activité.');
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slugProblem =
        _slug.isEmpty ? null : CreateBusinessScreen.slugProblem(_slug);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Nouvelle activité'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.previewForm != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(context.tr('Aperçu : la page telle que la voit la personne qui demande. Rien n\'est envoyé.'),
                    key: const Key('apply-preview'),
                    style: theme.textTheme.labelMedium?.copyWith(color: maraBrown)),
              ),
            if (widget.asApplication && _form?.welcome != null)
              Container(
                key: const Key('apply-welcome'),
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: maraDeep,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_form!.welcome!,
                    style: theme.textTheme.bodyLarge?.copyWith(color: maraPaper)),
              ),
            TextField(
              controller: _nameController,
              enabled: !_busy,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('Nom de l\'activité'),
                hintText: context.tr('Association Bethel'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _slugController,
              enabled: !_busy,
              onChanged: (_) => setState(() => _slugTouched = true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
              ],
              decoration: InputDecoration(
                labelText: context.tr('Adresse'),
                helperText: slugProblem == null ? 'marakaj.com/s/$_slug' : null,
                errorText: slugProblem,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            Text(context.tr('Type'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // Cards rather than a radio group: four options each needing a
            // line of explanation do not fit a SegmentedButton, and this is
            // the choice that cannot be undone from a phone afterwards.
            ..._offered.map((p) {
              final selected = p.value == _profile;
              return KajCard(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: Icon(p.icon, color: theme.colorScheme.primary),
                  title: Text(p.label),
                  subtitle: Text(p.detail, style: theme.textTheme.bodySmall),
                  trailing: selected
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary)
                      : null,
                  onTap:
                      _busy ? null : () => setState(() => _profile = p.value),
                ),
              );
            }),
            const SizedBox(height: 8),

            SizedBox(
              width: 160,
              child: TextField(
                controller: _currencyController,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(3),
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr('Monnaie'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),

            if (widget.asApplication) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _descriptionController,
                enabled: !_busy,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('Décrivez votre activité'),
                  helperText: context.tr('Ce que vous vendez ou produisez, où, depuis quand. C’est ce que lira la personne qui valide.'),
                  border: const OutlineInputBorder(),
                ),
              ),
              for (final q in _form?.questions ?? const <FormQuestion>[]) ...[
                const SizedBox(height: 20),
                _question(theme, q),
              ],
            ],

            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('apply-send'),
                onPressed: _ready && !_busy && widget.previewForm == null ? _create : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.asApplication
                            ? context.tr('Envoyer la demande')
                            : context.tr('Créer l\'activité'),
                        style: const TextStyle(fontSize: 17),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.asApplication
                  ? context.tr('Un administrateur Kaj-consulting examine la demande. Une fois validée, vous en serez le propriétaire.')
                  : context.tr('Vous en serez le propriétaire. Un plan comptable de départ est créé automatiquement.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One of the page's own questions, as its type asks to be answered.
  Widget _question(ThemeData theme, FormQuestion q) {
    final id = _idOf(q);
    final label = q.required ? '${q.label} *' : q.label;
    switch (q.type) {
      case QuestionType.text:
      case QuestionType.number:
        final number = q.type == QuestionType.number;
        final typed = _answerOf(q);
        return TextField(
          key: Key('apply-q-$id'),
          controller: _typed[id],
          enabled: !_busy,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            helperText: q.help,
            errorText: number && typed is String
                ? context.tr('En chiffres, s\'il vous plaît.')
                : null,
            border: const OutlineInputBorder(),
          ),
        );
      case QuestionType.choice:
      case QuestionType.yesno:
        final options = q.type == QuestionType.yesno
            ? [(true, context.tr('Oui')), (false, context.tr('Non'))]
            : [for (final o in q.options) (o, o)];
        return Column(
          key: Key('apply-q-$id'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            if (q.help != null)
              Text(q.help!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, text) in options)
                  ChoiceChip(
                    label: Text(text),
                    selected: _picked[id] == value,
                    selectedColor: maraCaramel,
                    onSelected: _busy
                        ? null
                        : (on) => setState(() {
                              if (on) {
                                _picked[id] = value;
                              } else {
                                _picked.remove(id);
                              }
                            }),
                  ),
              ],
            ),
          ],
        );
    }
  }
}

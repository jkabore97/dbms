import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/store_rules.dart';
import '../../core/auth/models.dart' show OrgSummary;
import '../../core/auth/whatsapp_phone.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/onboarding/application_form.dart';
import '../../core/onboarding/business_creation.dart';
import '../../core/phone/country_codes.dart';
import '../../core/rates/currency_rates.dart' show knownCurrencies;
import '../../core/theme/mara_mark.dart';
import '../admin/create_business_screen.dart' show CreateBusinessScreen;
import '../auth/org_picker_screen.dart' show iconForProfile, kindColour, kindInk;
import '../common/phone_field.dart';
import '../storefront/whatsapp_verify_screen.dart';
import 'association_setup_screen.dart' show associationKinds;
import '../../core/notify/bell_room.dart';
import '../../core/nav/router.dart';
import '../../core/nav/app_scope.dart';

/// « Créer mon activité » (111): a person makes their business at once —
/// no request, no wait. One question per screen, a bar that fills, Retour
/// and Suivant:
///
///  1. what it is — Boutique, Ferme, Association (the kinds Mara's
///     creation page offers, under its welcome text);
///  2. its name, with its address marakaj.com/s/… written as it is typed
///     and said free or taken at once (a free one offered);
///  3. what it does — a shop's or a farm's line of trade, an
///     association's kind (102) — and one sentence, if they like;
///  4. its town and area;
///  5. its phone (their WhatsApp number when proved), the currency
///     following the phone's country;
///  6. Mara's own questions, if the creation page has some, one a screen;
///  7. everything on one page → « Créer mon activité ».
///
/// The answers are kept on the device until the business exists and the
/// app has seen it, and the flow opens again where it was left. Created,
/// the person is its owner; [onCreated] takes them into its first setup
/// (and the device code, once: session.dart asks it of whoever has a
/// business).
///
/// With [previewForm] this is the creation page as Mara shapes it in the
/// command center: drawn with her form, nothing read, nothing sent.
class CreateMyBusinessScreen extends StatefulWidget {
  const CreateMyBusinessScreen({
    super.key,
    required this.api,
    this.drafts,
    this.whatsApp,
    this.onCreated,
    this.previewForm,
  });

  final BusinessCreation api;

  /// Where the answers wait; none: nothing is kept (a test, the preview).
  final DraftStore? drafts;

  /// Proving a number on WhatsApp (109), when the platform asks for it.
  final WhatsAppPhone? whatsApp;

  /// The business exists: open it — what the creation knows of it (its
  /// id, name, kind, address, currency; the person its owner). Answers
  /// whether the app now has it (on a bad line the server's list may not
  /// yet): only then are the answers on the device let go.
  final Future<bool> Function(OrgSummary created)? onCreated;

  final ApplicationForm? previewForm;

  bool get preview => previewForm != null;

  @override
  State<CreateMyBusinessScreen> createState() => _CreateMyBusinessScreenState();
}

/// A shop's and a farm's lines of trade, in the server's order
/// (111's business_activities); an association's are 102's kinds.
List<({String key, IconData icon, String name})> businessActivities(
        BuildContext context, String profile) =>
    switch (profile) {
      'retail' => [
          (key: 'alimentation', icon: Icons.local_grocery_store_outlined, name: context.tr('Alimentation')),
          (key: 'telephonie', icon: Icons.smartphone_outlined, name: context.tr('Téléphonie et électronique')),
          (key: 'vetements', icon: Icons.checkroom_outlined, name: context.tr('Vêtements et mode')),
          (key: 'beaute', icon: Icons.spa_outlined, name: context.tr('Beauté et cosmétique')),
          (key: 'restaurant', icon: Icons.restaurant_outlined, name: context.tr('Restaurant et maquis')),
          (key: 'quincaillerie', icon: Icons.hardware_outlined, name: context.tr('Quincaillerie')),
          (key: 'autre', icon: Icons.more_horiz, name: context.tr('Autre')),
        ],
      'farm' => [
          (key: 'volaille', icon: Icons.egg_outlined, name: context.tr('Volaille')),
          (key: 'elevage', icon: Icons.pets_outlined, name: context.tr('Élevage')),
          (key: 'maraichage', icon: Icons.eco_outlined, name: context.tr('Maraîchage')),
          (key: 'cereales', icon: Icons.grass_outlined, name: context.tr('Céréales')),
          (key: 'mixte', icon: Icons.agriculture_outlined, name: context.tr('Mixte')),
          (key: 'autre', icon: Icons.more_horiz, name: context.tr('Autre')),
        ],
      _ => [
          for (final k in associationKinds(context)) (key: k.key, icon: k.icon, name: k.name),
        ],
    };

class _CreateMyBusinessScreenState extends State<CreateMyBusinessScreen> {
  BusinessStart? _start;
  String? _loadError;
  late BusinessDraft _draft;

  /// Taken up from the device: said once, on the screen it reopens.
  bool _resumed = false;

  final _name = TextEditingController();
  final _slug = TextEditingController();
  final _about = TextEditingController();
  final _city = TextEditingController();
  final _area = TextEditingController();
  final _phone = TextEditingController();
  final _typed = <String, TextEditingController>{};

  /// The number proved on WhatsApp, the account's or proved here.
  String? _proved;

  AddressCheck? _check;
  bool _checking = false;
  bool _editAddress = false;
  Timer? _checkSoon;
  Timer? _saveSoon;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = BusinessDraft();
    if (widget.preview) {
      // Mara's page as she shapes it: nothing read, nothing kept.
      _start = BusinessStart(form: widget.previewForm);
      _take(_draft);
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(CreateMyBusinessScreen old) {
    super.didUpdateWidget(old);
    if (widget.preview && widget.previewForm != old.previewForm) {
      // What Mara typed changes the page; what was clicked through stays.
      setState(() {
        _start = BusinessStart(form: widget.previewForm);
        _fitForm();
      });
    }
  }

  @override
  void dispose() {
    _checkSoon?.cancel();
    _saveSoon?.cancel();
    for (final c in [_name, _slug, _about, _city, _area, _phone, ..._typed.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _start = null;
    });
    try {
      final results = await Future.wait<Object?>([
        widget.api.start(),
        widget.drafts?.read() ?? Future<BusinessDraft?>.value(),
      ]);
      if (!mounted) return;
      final start = results[0] as BusinessStart;
      final kept = results[1] as BusinessDraft?;
      setState(() {
        _start = start;
        _proved = start.verifiedPhone;
        _resumed = kept != null && !kept.isEmpty;
        _take(kept ?? BusinessDraft());
      });
      if (_draft.slug.isNotEmpty) _checkAddress(now: true);
    } catch (e) {
      if (mounted) setState(() => _loadError = describeError(e));
    }
  }

  /// Fills the fields from [d] — a kept draft, or a new one. Called inside
  /// a setState (or before the first frame).
  void _take(BusinessDraft d) {
    _draft = d;
    _name.text = d.name;
    _slug.text = d.slug;
    _about.text = d.about;
    _city.text = d.city;
    _area.text = d.area;
    final proved = _proved;
    if (d.phone.isEmpty && proved != null) {
      final country = countryOfNumber(proved) ?? defaultCountry;
      d.phoneIso = country.iso;
      d.phone = country.localPart(proved);
    }
    _phone.text = d.phone;
    for (final q in _questions) {
      if (q.type == QuestionType.text || q.type == QuestionType.number) {
        final a = d.answers[_idOf(q)];
        _typed.putIfAbsent(_idOf(q), TextEditingController.new).text = a == null ? '' : '$a';
      }
    }
    _fitForm();
  }

  /// The draft fitted to the page as it is now: a kind it no longer offers
  /// is not left chosen, a screen gone is not stayed on.
  void _fitForm() {
    for (final q in _questions) {
      if (q.type == QuestionType.text || q.type == QuestionType.number) {
        _typed.putIfAbsent(_idOf(q), TextEditingController.new);
      }
    }
    final d = _draft;
    if (d.profile != null && !_offered.contains(d.profile)) d.profile = null;
    d.step = d.step.clamp(0, _steps.length - 1);
    if (d.profile == null) d.step = 0;
  }

  // ---- what is asked ----

  ApplicationForm? get _form => _start?.form;
  List<FormQuestion> get _questions => _form?.questions ?? const [];
  String _idOf(FormQuestion q) => q.id ?? 'q${_questions.indexOf(q)}';

  List<String> get _offered => [
        for (final k in const ['retail', 'farm', 'association'])
          if (_form?.offers(k) ?? true) k,
      ];

  /// The screens, in order: the five, Mara's questions, the summary.
  List<String> get _steps => [
        'kind', 'name', 'activity', 'place', 'phone',
        for (var i = 0; i < _questions.length; i++) 'q$i',
        'summary',
      ];

  String get _stepKey => _steps[_draft.step.clamp(0, _steps.length - 1)];

  CountryCode get _country => countryByIso(_draft.phoneIso);
  String get _currency => _draft.currency ?? currencyOfCountry(_draft.phoneIso);

  String? get _phoneE164 {
    final typed = _phone.text.trim();
    if (typed.isEmpty || _country.lengthProblem(typed) != null) return null;
    return _country.toE164(typed);
  }

  bool get _phoneProved => _proved != null && _phoneE164 == _proved;

  // ---- keeping the answers ----

  void _changed() {
    _draft
      ..name = _name.text
      ..slug = _slug.text
      ..about = _about.text
      ..city = _city.text
      ..area = _area.text
      ..phone = _phone.text;
    for (final e in _typed.entries) {
      final t = e.value.text.trim();
      if (t.isEmpty) {
        _draft.answers.remove(e.key);
      } else {
        _draft.answers[e.key] = t;
      }
    }
    setState(() => _error = null);
    _saveSoon?.cancel();
    final drafts = widget.drafts;
    if (drafts != null && !widget.preview) {
      _saveSoon = Timer(const Duration(milliseconds: 400), () => drafts.write(_draft));
    }
  }

  void _onName(String _) {
    if (!_draft.slugTouched) {
      _slug.text = CreateBusinessScreen.slugify(_name.text);
    }
    _changed();
    _checkAddress();
  }

  void _onSlug(String _) {
    _draft.slugTouched = true;
    _changed();
    _checkAddress();
  }

  /// The address said at once: the app's own rule first, then the
  /// server's (free or taken), a moment after typing stops.
  void _checkAddress({bool now = false}) {
    _checkSoon?.cancel();
    final slug = _slug.text.trim();
    if (slug.isEmpty || CreateBusinessScreen.slugProblem(slug) != null || widget.preview) {
      setState(() {
        _check = null;
        _checking = false;
      });
      return;
    }
    setState(() => _checking = true);
    _checkSoon = Timer(now ? Duration.zero : const Duration(milliseconds: 450), () async {
      try {
        final c = await widget.api.checkAddress(slug);
        if (!mounted || _slug.text.trim() != slug) return;
        setState(() {
          _check = c;
          _checking = false;
        });
      } catch (_) {
        // No answer is no verdict: the server says it again on creating.
        if (mounted) setState(() => _checking = false);
      }
    });
  }

  void _useSlug(String slug) {
    _slug.text = slug;
    _draft.slugTouched = true;
    _changed();
    _checkAddress(now: true);
  }

  // ---- moving ----

  bool get _ready => switch (_stepKey) {
        'kind' => _draft.profile != null,
        'name' => _name.text.trim().isNotEmpty &&
            CreateBusinessScreen.slugProblem(_slug.text.trim()) == null &&
            !_checking &&
            !(_check?.taken ?? false) &&
            _check?.problem == null,
        'activity' => _draft.activity != null,
        'place' => _city.text.trim().isNotEmpty,
        'phone' => _phoneE164 != null && (!(_start?.phoneRequired ?? false) || _phoneProved),
        'summary' => !_busy && !widget.preview,
        _ => _answered(_questions[int.parse(_stepKey.substring(1))]),
      };

  bool _answered(FormQuestion q) {
    final a = _answerOf(q);
    if (q.type == QuestionType.number && a is String) return false;
    return !q.required || a != null;
  }

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
        return _draft.answers[id];
    }
  }

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _draft.step = step.clamp(0, _steps.length - 1);
      _error = null;
      _resumed = false;
    });
    _changed();
  }

  void _next() {
    if (!_ready) return;
    if (_stepKey == 'summary') {
      _create();
    } else {
      _go(_draft.step + 1);
    }
  }

  void _back() {
    if (_draft.step > 0) {
      _go(_draft.step - 1);
    } else {
      _leave();
    }
  }

  /// Something already answered: leaving asks first (the owner's « a button
  /// to return to the welcome page or just go back »).
  bool get _anythingAnswered =>
      _draft.profile != null ||
      _draft.answers.isNotEmpty ||
      [_name, _slug, _about, _city, _area, _phone].any((c) => c.text.trim().isNotEmpty);

  /// « Quitter sans enregistrer ? » — the business is not created; the
  /// answers stay on the phone all the same, and the flow reopens on them.
  Future<bool> _mayLeave() async {
    if (widget.preview || !_anythingAnswered) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('create-leave'),
        title: Text(dialog.tr('Quitter sans enregistrer ?')),
        content: Text(dialog.tr('Votre activité n\'est pas encore créée. Vos réponses sont gardées : vous reprendrez ici.')),
        actions: [
          TextButton(
            key: const Key('create-leave-stay'),
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(dialog.tr('Rester')),
          ),
          FilledButton(
            key: const Key('create-leave-go'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(dialog.tr('Quitter')),
          ),
        ],
      ),
    );
    return go == true;
  }

  /// Back from the first question: where the person came from — or, with
  /// [home] (« Retour à l'accueil »), the welcome page, the street. A page
  /// reached by its address alone has nowhere behind it: the street too.
  Future<void> _leave({bool home = false}) async {
    if (_busy || !await _mayLeave() || !mounted) return;
    // What is pending is written now: « Vos réponses sont gardées ».
    _saveSoon?.cancel();
    final drafts = widget.drafts;
    if (drafts != null && !widget.preview) await drafts.write(_draft);
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (home && router != null) {
      router.go(Routes.directory);
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      router?.go(Routes.directory);
    }
  }

  Future<void> _verify() async {
    final phone = widget.whatsApp;
    if (phone == null) return;
    final proved = await Navigator.of(context).push(WhatsAppVerifyScreen.route(phone,
        intro: context.tr('Avant de créer votre activité, Mara vérifie votre numéro WhatsApp.')));
    if (!mounted || proved == null) return;
    final country = countryOfNumber(proved) ?? defaultCountry;
    setState(() {
      _proved = proved;
      _draft.phoneIso = country.iso;
      _phone.text = country.localPart(proved);
    });
    _changed();
  }

  Future<void> _create() async {
    final profile = _draft.profile;
    final activity = _draft.activity;
    final phone = _phoneE164;
    if (profile == null || activity == null || phone == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.api.create(
        profile: profile,
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        activity: activity,
        about: _about.text.trim(),
        city: _city.text.trim(),
        area: _area.text.trim(),
        phone: phone,
        currency: _currency,
        answers: _questions.isEmpty
            ? null
            : {for (final q in _questions) if (q.id != null) q.id!: _answerOf(q)},
      );
      _saveSoon?.cancel();
      final drafts = widget.drafts;
      final seen = await widget.onCreated?.call(OrgSummary(
            id: id,
            name: _name.text.trim(),
            profile: profile,
            slug: _slug.text.trim(),
            currency: _currency,
            roles: const ['owner'],
          )) ??
          true;
      // Kept until the app has the business: a line that drops between the
      // creation and the list must not lose what was typed.
      if (seen) await drafts?.write(null);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- drawing ----

  String _kindWord(String? profile) => switch (profile) {
        'farm' => context.tr('Ferme'),
        'association' => context.tr('Association'),
        _ => context.tr('Boutique'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = _start;
    final Widget body;
    if (_loadError != null) {
      body = _Message(
        icon: Icons.wifi_off,
        title: context.tr('Impossible de charger'),
        line: _loadError!,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(context.tr('Réessayer')),
        ),
      );
    } else if (start == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (start.locked) {
      body = _Message(
        key: const Key('create-locked'),
        icon: Icons.lock_outline,
        title: context.tr('Une deuxième activité : avec Mara Pro'),
        // The iPhone app sells no Pro (125): what a second activity needs,
        // said plainly, with no way to buy it.
        line: sellsDigitalInApp
            ? context.tr('Vous avez déjà une activité sur Mara. Passez-la à Mara Pro pour en créer une deuxième.')
            : context.tr('Vous avez déjà une activité sur Mara. Une deuxième activité fait partie de Mara Pro.'),
        // Never a dead end (122): the way to Pro on the activity owned,
        // beside the way back.
        action: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_ownedOrgId() case final owned? when sellsDigitalInApp) ...[
              FilledButton.icon(
                key: const Key('create-locked-pro'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: maraCaramel,
                    foregroundColor: maraDeep),
                onPressed: () => context.push(Routes.inside(owned, 'kaj-pro')),
                icon: const Icon(Icons.workspace_premium),
                label: Text(context.tr('Passer à Pro')),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(context.tr('Retour')),
            ),
          ],
        ),
      );
    } else {
      body = _flow(theme);
    }
    return PopScope(
      // Android's back steps back through the questions; the preview, drawn
      // inside the command center's page, never holds that page's back.
      canPop: widget.preview ||
          start == null ||
          start.locked ||
          (_draft.step == 0 && !_anythingAnswered),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: const [bellRoom],
          title: Text(widget.preview ? context.tr('Aperçu de la création') : context.tr('Créer mon activité')),
          // Back on every question: the previous one, and from the first
          // where the person came from.
          leading: widget.preview
              ? null
              : IconButton(
                  key: const Key('create-bar-back'),
                  tooltip: context.tr('Retour'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _busy
                      ? null
                      : start == null || start.locked
                          ? () => Navigator.of(context).maybePop()
                          : _back,
                ),
        ),
        body: SafeArea(child: body),
      ),
    );
  }

  /// The live activity this person owns, whose Pro opens a second (099).
  String? _ownedOrgId() {
    final orgs = AppScope.maybeOf(context)?.session.orgs ?? const <OrgSummary>[];
    for (final o in orgs) {
      if (o.roles.contains('owner')) return o.id;
    }
    return null;
  }

  Widget _flow(ThemeData theme) {
    final steps = _steps;
    final at = _draft.step.clamp(0, steps.length - 1);
    final last = _stepKey == 'summary';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    key: const Key('create-progress'),
                    value: (at + 1) / steps.length,
                    minHeight: 6,
                    color: maraCaramel,
                    backgroundColor: maraCaramel.withValues(alpha: 0.2),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${at + 1} / ${steps.length}',
                  key: const Key('create-count'), style: theme.textTheme.labelLarge),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                key: ValueKey('create-step-$_stepKey'),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  if (_resumed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(context.tr('Vos réponses ont été gardées : vous reprenez ici.'),
                          key: const Key('create-resumed'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: maraBrown)),
                    ),
                  ..._page(theme),
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Container(
              key: const Key('create-error'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                children: [
                  if (at > 0) ...[
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        key: const Key('create-back'),
                        onPressed: _busy ? null : _back,
                        child: Text(context.tr('Retour')),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: Key(last ? 'create-submit' : 'create-next'),
                        style: FilledButton.styleFrom(
                          backgroundColor: maraDeep,
                          foregroundColor: maraPaper,
                        ),
                        onPressed: _ready ? _next : null,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: maraPaper),
                              )
                            : Text(last ? context.tr('Créer mon activité') : context.tr('Suivant'),
                                style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The first question: the way back to the welcome page, in words.
        if (at == 0 && !widget.preview)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton.icon(
              key: const Key('create-home'),
              onPressed: _busy ? null : () => _leave(home: true),
              icon: const Icon(Icons.storefront_outlined),
              label: Text(context.tr('Retour à l\'accueil')),
            ),
          ),
      ],
    );
  }

  Widget _title(ThemeData theme, String text, [String? line]) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (line != null) ...[
              const SizedBox(height: 6),
              Text(line, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      );

  String _ofKind(String retail, String farm, String association) => switch (_draft.profile) {
        'farm' => farm,
        'association' => association,
        _ => retail,
      };

  List<Widget> _page(ThemeData theme) {
    switch (_stepKey) {
      case 'kind':
        return _kindPage(theme);
      case 'name':
        return _namePage(theme);
      case 'activity':
        return _activityPage(theme);
      case 'place':
        return _placePage(theme);
      case 'phone':
        return _phonePage(theme);
      case 'summary':
        return _summaryPage(theme);
      default:
        return _questionPage(theme, _questions[int.parse(_stepKey.substring(1))]);
    }
  }

  List<Widget> _kindPage(ThemeData theme) {
    final welcome = _form?.welcome;
    final lines = {
      'retail': context.tr('Vous vendez des articles : alimentation, téléphones, vêtements…'),
      'farm': context.tr('Vous élevez ou cultivez, et vous vendez votre production.'),
      'association': context.tr('Une tontine, une église, un groupement : ses membres et ses cotisations.'),
    };
    return [
      if (welcome != null)
        Container(
          key: const Key('create-welcome'),
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: maraDeep, borderRadius: BorderRadius.circular(14)),
          child: Text(welcome, style: theme.textTheme.bodyLarge?.copyWith(color: maraPaper)),
        ),
      _title(theme, context.tr('Qu\'allez-vous créer ?')),
      for (final k in _offered)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _BigTile(
            key: Key('create-kind-$k'),
            icon: iconForProfile(k),
            colour: kindColour(k),
            ink: kindInk(k),
            title: _kindWord(k),
            line: lines[k]!,
            selected: _draft.profile == k,
            onTap: () {
              if (_draft.profile != k) _draft.activity = null;
              _draft.profile = k;
              _changed();
            },
          ),
        ),
    ];
  }

  List<Widget> _namePage(ThemeData theme) {
    final slug = _slug.text.trim();
    final local = slug.isEmpty ? null : CreateBusinessScreen.slugProblem(slug);
    final check = _check;
    final Widget status;
    if (slug.isEmpty) {
      status = const SizedBox.shrink();
    } else if (local != null) {
      status = Text(context.tr(local), style: TextStyle(color: theme.colorScheme.error));
    } else if (_checking) {
      status = Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text(context.tr('Vérification…')),
      ]);
    } else if (check?.problem != null) {
      status = Text(context.tr(check!.problem!), style: TextStyle(color: theme.colorScheme.error));
    } else if (check?.taken ?? false) {
      status = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(context.tr('Déjà prise par une autre activité.'),
              key: const Key('create-address-taken'),
              style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
          if (check!.suggestion != null)
            OutlinedButton.icon(
              key: const Key('create-address-suggestion'),
              icon: const Icon(Icons.check, size: 18),
              label: Text(context.tr('Prendre {slug}', {'slug': check.suggestion})),
              onPressed: () => _useSlug(check.suggestion!),
            ),
        ],
      );
    } else if (check?.free ?? false) {
      status = Row(children: [
        const Icon(Icons.check_circle, color: maraGreen, size: 18),
        const SizedBox(width: 6),
        Text(context.tr('Libre'),
            key: const Key('create-address-free'),
            style: const TextStyle(color: maraGreen, fontWeight: FontWeight.w700)),
      ]);
    } else {
      status = const SizedBox.shrink();
    }
    return [
      _title(theme, _ofKind(context.tr('Le nom de votre boutique'), context.tr('Le nom de votre ferme'),
          context.tr('Le nom de votre association'))),
      TextField(
        key: const Key('create-name'),
        controller: _name,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 20),
        onChanged: _onName,
        decoration: InputDecoration(
          hintText: _ofKind(context.tr('Ex. : Chez Awa, Café Lumière, Green Market'), context.tr('Ex. : Ferme Wendkouni, Green Valley Farm, Rancho Sol'),
              context.tr('Ex. : Tontine des femmes de Dapoya, Club des amis, Hope Foundation')),
          hintMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: maraPaper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: maraCaramel.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Votre adresse'), style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text('marakaj.com/s/${slug.isEmpty ? '…' : slug}',
                key: const Key('create-address'),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: maraBlack)),
            const SizedBox(height: 6),
            status,
            if (_editAddress || _draft.slugTouched) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('create-slug'),
                controller: _slug,
                onChanged: _onSlug,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]'))],
                decoration: InputDecoration(
                  labelText: context.tr('Adresse'),
                  prefixText: 'marakaj.com/s/',
                  border: const OutlineInputBorder(),
                ),
              ),
            ] else
              TextButton(
                key: const Key('create-edit-address'),
                onPressed: () => setState(() => _editAddress = true),
                child: Text(context.tr('Changer l\'adresse')),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _activityPage(ThemeData theme) {
    final profile = _draft.profile ?? 'retail';
    return [
      _title(theme, _ofKind(context.tr('Que vend votre boutique ?'), context.tr('Que produit votre ferme ?'),
          context.tr('Quel genre d\'association ?'))),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final a in businessActivities(context, profile))
            ChoiceChip(
              key: Key('create-activity-${a.key}'),
              avatar: Icon(a.icon, size: 20),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(a.name, style: const TextStyle(fontSize: 16)),
              ),
              showCheckmark: false,
              selected: _draft.activity == a.key,
              selectedColor: maraCaramel,
              onSelected: (_) {
                _draft.activity = a.key;
                _changed();
              },
            ),
        ],
      ),
      const SizedBox(height: 24),
      TextField(
        key: const Key('create-about'),
        controller: _about,
        // The vitrine's sentence: the setup and the settings keep 80.
        maxLength: 80,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => _changed(),
        decoration: InputDecoration(
          labelText: context.tr('En une phrase (facultatif)'),
          hintText: _ofKind(context.tr('Ex. : Riz et savon au détail, café et pâtisseries, vêtements'),
              context.tr('Ex. : Œufs frais, légumes bio, miel'),
              context.tr('Ex. : On cotise chaque semaine depuis 2019')),
          hintMaxLines: 2,
          helperText: context.tr('Elle paraîtra sur votre vitrine.'),
          border: const OutlineInputBorder(),
        ),
      ),
    ];
  }

  List<Widget> _placePage(ThemeData theme) => [
        _title(theme, _ofKind(context.tr('Où se trouve votre boutique ?'),
            context.tr('Où se trouve votre ferme ?'), context.tr('Où se trouve votre association ?'))),
        TextField(
          key: const Key('create-city'),
          controller: _city,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: context.tr('Ville'),
            border: const OutlineInputBorder(),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final town in suggestedTowns(_draft.phoneIso))
              ChoiceChip(
                label: Text(town),
                showCheckmark: false,
                selected: _city.text.trim() == town,
                selectedColor: maraCaramel,
                onSelected: (_) {
                  _city.text = town;
                  _changed();
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('create-area'),
          controller: _area,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: context.tr('Quartier (facultatif)'),
            hintText: context.tr('Ex. : Dapoya près du marché, Le Plateau, Centre-ville'),
            hintMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
      ];

  List<Widget> _phonePage(ThemeData theme) {
    final required = _start?.phoneRequired ?? false;
    final typed = _phone.text.trim();
    final length = typed.isEmpty ? null : _country.lengthProblem(typed);
    final currencies = <String>{_currency, 'XOF', 'XAF', ...knownCurrencies.keys}.toList();
    return [
      _title(theme, _ofKind(context.tr('Le numéro de votre boutique'), context.tr('Le numéro de votre ferme'),
              context.tr('Le numéro de votre association')),
          context.tr('Vos clients vous appellent ou vous écrivent sur WhatsApp à ce numéro.')),
      if (required && !_phoneProved)
        Container(
          key: const Key('create-verify'),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: maraCaramel.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('Mara demande un numéro WhatsApp vérifié pour créer une activité.'),
                  style: theme.textTheme.bodyLarge),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('create-verify-button'),
                onPressed: widget.whatsApp == null || widget.preview ? null : _verify,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.verified_user_outlined),
                label: Text(context.tr('Vérifier mon numéro WhatsApp')),
              ),
            ],
          ),
        ),
      PhoneField(
        key: const Key('create-phone'),
        controller: _phone,
        country: _country,
        large: true,
        onCountry: (c) {
          _draft.phoneIso = c.iso;
          _changed();
        },
        onChanged: (_) => _changed(),
        labelText: context.tr('Numéro'),
        errorText: length,
      ),
      if (_phoneProved)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.verified, color: maraGreen, size: 18),
            const SizedBox(width: 6),
            Text(context.tr('Vérifié sur WhatsApp'),
                key: const Key('create-phone-proved'),
                style: const TextStyle(color: maraGreen, fontWeight: FontWeight.w600)),
          ]),
        ),
      const SizedBox(height: 24),
      DropdownButtonFormField<String>(
        // Keyed by the currency: a new country starts it on its own.
        key: ValueKey('create-currency-$_currency'),
        initialValue: _currency,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.tr('Monnaie'),
          helperText: context.tr('Celle du pays du numéro. Vos prix et vos comptes sont dans cette monnaie.'),
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final c in currencies)
            DropdownMenuItem(value: c, child: Text('$c — ${_currencyName(c)}')),
        ],
        onChanged: (c) {
          _draft.currency = c == currencyOfCountry(_draft.phoneIso) ? null : c;
          _changed();
        },
      ),
    ];
  }

  String _currencyName(String code) => switch (code) {
        'XOF' => context.tr('Franc CFA (UEMOA)'),
        'GNF' => context.tr('Franc guinéen'),
        _ => knownCurrencies[code] ?? code,
      };

  List<Widget> _questionPage(ThemeData theme, FormQuestion q) {
    final id = _idOf(q);
    final title = q.required ? q.label : context.tr('{label} (facultatif)', {'label': q.label});
    final Widget input;
    switch (q.type) {
      case QuestionType.text:
      case QuestionType.number:
        final number = q.type == QuestionType.number;
        final typed = _answerOf(q);
        input = TextField(
          key: Key('create-q-$id'),
          controller: _typed.putIfAbsent(id, TextEditingController.new),
          autofocus: true,
          maxLines: number ? 1 : 3,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            errorText: number && typed is String ? context.tr('En chiffres, s\'il vous plaît.') : null,
            border: const OutlineInputBorder(),
          ),
        );
      case QuestionType.choice:
      case QuestionType.yesno:
        final options = q.type == QuestionType.yesno
            ? [(true, context.tr('Oui')), (false, context.tr('Non'))]
            : [for (final o in q.options) (o, o)];
        input = Column(
          key: Key('create-q-$id'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (value, text) in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BigTile(
                  title: text,
                  selected: _draft.answers[id] == value,
                  onTap: () {
                    _draft.answers[id] = value;
                    _changed();
                  },
                ),
              ),
          ],
        );
    }
    return [_title(theme, title, q.help), input];
  }

  List<Widget> _summaryPage(ThemeData theme) {
    String said(FormQuestion q) => switch (_answerOf(q)) {
          null => '—',
          true => context.tr('Oui'),
          false => context.tr('Non'),
          final v => '$v',
        };
    final activity = businessActivities(context, _draft.profile ?? 'retail')
        .where((a) => a.key == _draft.activity)
        .map((a) => a.name)
        .firstOrNull;
    final rows = <(String, String, int)>[
      (context.tr('Type'), _kindWord(_draft.profile), 0),
      (context.tr('Nom'), _name.text.trim(), 1),
      (context.tr('Adresse'), 'marakaj.com/s/${_slug.text.trim()}', 1),
      (context.tr('Activité'), activity ?? '—', 2),
      if (_about.text.trim().isNotEmpty) (context.tr('En une phrase'), _about.text.trim(), 2),
      (context.tr('Ville'), _city.text.trim(), 3),
      if (_area.text.trim().isNotEmpty) (context.tr('Quartier'), _area.text.trim(), 3),
      (context.tr('Téléphone'), _phoneE164 ?? '—', 4),
      (context.tr('Monnaie'), '$_currency — ${_currencyName(_currency)}', 4),
      for (var i = 0; i < _questions.length; i++) (_questions[i].label, said(_questions[i]), 5 + i),
    ];
    return [
      _title(theme, context.tr('Tout est juste ?'),
          context.tr('Touchez une ligne pour la changer.')),
      Material(
        color: maraPaper,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (label, value, step) in rows)
              ListTile(
                key: Key('create-summary-$step-$label'),
                title: Text(label, style: theme.textTheme.labelMedium),
                subtitle: Text(value,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: maraBlack)),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _busy ? null : () => _go(step),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        widget.preview
            ? context.tr('Aperçu : rien n\'est créé.')
            : _ofKind(
                context.tr('Vous en êtes le propriétaire tout de suite. Ensuite, la mise en route : votre premier article, votre vitrine.'),
                context.tr('Vous en êtes le propriétaire tout de suite. Ensuite, la mise en route : ce que vous vendez, votre vitrine.'),
                context.tr('Vous en êtes le propriétaire tout de suite. Ensuite, la mise en route : vos premiers membres, votre vitrine.')),
        key: const Key('create-after'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ];
  }
}

/// A choice as big as a thumb: its picture in its kind's colour, a word,
/// one line.
class _BigTile extends StatelessWidget {
  const _BigTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.colour = maraDeep,
    this.ink = maraPaper,
    this.line,
  });

  final IconData? icon;
  final Color colour;
  final Color ink;
  final String title;
  final String? line;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? maraCaramel.withValues(alpha: 0.22) : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? maraCaramel : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, size: 28, color: ink),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (line != null) ...[
                      const SizedBox(height: 2),
                      Text(line!, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? maraBrown : theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// A whole-screen word: a picture, a title, a line, one button.
class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.title, required this.line, required this.action});

  final IconData icon;
  final String title;
  final String line;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: maraBrown),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(line, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              action,
            ],
          ),
        ),
      ),
    );
  }
}

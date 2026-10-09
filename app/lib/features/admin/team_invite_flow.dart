import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/access/org_access.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/admin/models.dart' show roleLabel;
import '../../core/auth/models.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/onboarding/onboarding_repository.dart';
import '../../core/phone/country_codes.dart';
import '../../core/storefront/storefront_repository.dart' show whatsappUrl;
import '../common/phone_field.dart';
import '../common/step_flow.dart';
import 'member_edit_sheet.dart' show grantableRolesFor;
import 'team_access_screen.dart' show teamDialFeatures;

/// One line for each responsibility, said where it is chosen (French; the
/// flow passes it through `tr`).
String roleLine(String role) => switch (role) {
      'admin' => 'Gère tout : ventes, articles, équipe, réglages — sauf l\'argent et le type de l\'activité, qui restent au propriétaire',
      'manager' => 'Dirige le travail du jour et l\'équipe en dessous',
      'supervisor' => 'Surveille les ventes, le stock et le travail des employés',
      'approver' => 'Valide les dépenses et les paiements',
      'employee' => 'Vend et enregistre au quotidien',
      'observer' => 'Regarde seulement : ne peut rien enregistrer',
      _ => '',
    };

/// « Ajouter une personne », one question a screen (115) — the same for a
/// shop, a farm and an association: the name, the WhatsApp number, the
/// responsibility (only those below the caller's own — 103's ladder, which
/// invite_employee holds on the server), what they will see, the salary if
/// it is said now (118 keeps it on the invitation until they join), then
/// the summary and « Créer l'invitation »; « C'est fait » shows the code and
/// sends it on WhatsApp. Replaces the invitation sheet.
class TeamInviteFlow extends StatefulWidget {
  const TeamInviteFlow({
    super.key,
    required this.org,
    required this.onboarding,
    required this.admin,
    this.store,
  });

  final OrgSummary org;
  final OnboardingRepository onboarding;
  final AdminRepository admin;
  final FlowStore? store;

  /// Opens the flow; resolves once it is closed (true when an invitation
  /// was written).
  static Future<bool?> open(BuildContext context,
          {required OrgSummary org,
          required OnboardingRepository onboarding,
          required AdminRepository admin}) =>
      StepFlow.push(context,
          TeamInviteFlow(org: org, onboarding: onboarding, admin: admin));

  @override
  State<TeamInviteFlow> createState() => _TeamInviteFlowState();
}

class _TeamInviteFlowState extends State<TeamInviteFlow> {
  final _flow = StepFlowController();
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _phone = TextEditingController();
  final _salary = TextEditingController();
  CountryCode _country = defaultCountry;
  String? _role;
  String _visibility = 'full';
  String _period = 'month';

  /// The dial of each tier, read once: what an employee or a supervisor sees.
  final Map<String, Map<String, String>> _rules = {};

  Invitation? _invitation;
  bool _salaryFailed = false;

  late final List<String> _roles = grantableRolesFor(widget.org.roles);

  @override
  void initState() {
    super.initState();
    if (_roles.contains('employee')) _role = 'employee';
    _loadRules();
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _phone, _salary]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRules() async {
    for (final tier in const ['employee', 'supervisor']) {
      try {
        final r = await widget.admin.featureRulesForTier(widget.org.id, tier);
        if (mounted) setState(() => _rules[tier] = r);
      } catch (_) {}
    }
  }

  String get _who =>
      _name.text.trim().isEmpty ? context.tr('cette personne') : _name.text.trim();

  double get _amount => FlowNumberField.read(_salary) ?? 0;

  String _periodLabel(String p) => switch (p) {
        'week' => context.tr('par semaine'),
        'day' => context.tr('par jour'),
        _ => context.tr('par mois'),
      };

  String _accessLabel(String a) => switch (a) {
        'hidden' => context.tr('Caché'),
        'view' => context.tr('Voir'),
        _ => context.tr('Modifier'),
      };

  Future<bool> _save() async {
    final phone =
        _phone.text.trim().isEmpty ? '' : _country.toE164(_phone.text);
    final invitation = await widget.onboarding.invite(
      orgId: widget.org.id,
      role: _role!,
      fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
      title: _title.text.trim(),
      phone: phone,
      visibility: _visibility,
    );
    var failed = false;
    if (_amount > 0) {
      try {
        await widget.onboarding
            .setInvitationSalary(invitation.id, _amount, period: _period);
      } catch (_) {
        // The invitation stands; the salary is said in Équipe once they join.
        failed = true;
      }
    }
    setState(() {
      _invitation = invitation;
      _salaryFailed = failed;
    });
    return true;
  }

  Future<void> _send() async {
    final inv = _invitation;
    if (inv == null) return;
    final phone =
        _phone.text.trim().isEmpty ? null : _country.toE164(_phone.text);
    final url = whatsappUrl(phone, text: inv.message);
    if (url != null) {
      final uri = Uri.parse(url);
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    }
    await SharePlus.instance.share(ShareParams(text: inv.message));
  }

  Future<void> _copy() async {
    final inv = _invitation;
    if (inv == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.tr('Code copié.');
    await Clipboard.setData(ClipboardData(text: inv.code));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  void _again() {
    setState(() {
      for (final c in [_name, _title, _phone, _salary]) {
        c.clear();
      }
      _role = _roles.contains('employee') ? 'employee' : null;
      _visibility = 'full';
      _period = 'month';
      _invitation = null;
      _salaryFailed = false;
    });
    _flow.restart();
  }

  Map<String, Object?> _toJson() => {
        'name': _name.text,
        'title': _title.text,
        'phone': _phone.text,
        'country': _country.iso,
        'role': _role,
        'visibility': _visibility,
        'salary': _salary.text,
        'period': _period,
      };

  void _fromJson(Map<String, Object?> a) => setState(() {
        _name.text = (a['name'] as String?) ?? '';
        _title.text = (a['title'] as String?) ?? '';
        _phone.text = (a['phone'] as String?) ?? '';
        final iso = a['country'] as String?;
        _country = allCountries.where((c) => c.iso == iso).firstOrNull ??
            defaultCountry;
        final role = a['role'] as String?;
        _role = _roles.contains(role)
            ? role
            : (_roles.contains('employee') ? 'employee' : null);
        _visibility = a['visibility'] == 'summary' ? 'summary' : 'full';
        _salary.text = (a['salary'] as String?) ?? '';
        final p = a['period'] as String?;
        _period = p == 'week' || p == 'day' ? p! : 'month';
      });

  /// What the chosen responsibility sees, as the dial says it today.
  Widget _sees(ThemeData theme) {
    final role = _role ?? 'employee';
    final access = AppScope.maybeOf(context)?.session.accessFor(widget.org.id);
    final Widget what;
    if (role == 'admin') {
      what = Text(context.tr('Tout ce que vous voyez, et les réglages.'),
          style: theme.textTheme.titleMedium);
    } else if (role == 'observer') {
      what = Text(context.tr('Tout regarder, sans rien enregistrer.'),
          style: theme.textTheme.titleMedium);
    } else {
      final rules = _rules[OrgAccess.tierOf([role])] ?? const {};
      what = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Les ventes et le stock, et :'),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final f in teamDialFeatures)
            if (!(access?.isHidden(f.key) ?? false) &&
                !(f.key == 'production' && widget.org.isAssociation))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(f.icon, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(context.tr(f.title))),
                    Text(
                        _accessLabel(rules[f.key] ??
                            (f.key == 'reports' ? 'view' : 'edit')),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          const SizedBox(height: 6),
          Text(context.tr('Le propriétaire change cela dans Administration › Accès de l\'équipe.'),
              style: theme.textTheme.bodySmall),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('team-sees'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: what,
        ),
        const SizedBox(height: 20),
        Text(context.tr('Les chiffres'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FlowChoice<String>(
          options: [
            FlowOption('full', context.tr('Tout le détail'),
                detail: context.tr('Chaque vente, chaque client')),
            FlowOption('summary', context.tr('Seulement les totaux'),
                detail: context.tr('Les sommes du jour, pas le détail')),
          ],
          value: _visibility,
          onChanged: (v) => setState(() => _visibility = v),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.org.currency);
    final cur = money.currencySymbol;
    final inv = _invitation;
    return StepFlow(
      title: context.tr('Ajouter une personne'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
          key: 'team-invite:${widget.org.id}', save: _toJson, restore: _fromJson),
      saveLabel: context.tr('Créer l\'invitation'),
      steps: [
        FlowStep(
          id: 'name',
          title: context.tr('Comment s\'appelle cette personne ?'),
          // Optional, as the invitation sheet had it (batch 115): the
          // person's own name arrives with their account.
          optional: true,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('team-name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: theme.textTheme.titleLarge,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.tr('Prénom et nom'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('team-title'),
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('Fonction (facultatif)'),
                  helperText: context.tr('Vendeuse, gardien, comptable…'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'phone',
          title: context.tr('Son numéro WhatsApp'),
          help: context.tr('Avec un numéro, le code ne marche que pour lui.'),
          optional: true,
          isValid: () =>
              _phone.text.trim().isEmpty ||
              _country.lengthProblem(_phone.text) == null,
          builder: (_) => PhoneField(
            key: const Key('team-phone'),
            controller: _phone,
            country: _country,
            onCountry: (c) => setState(() => _country = c),
            onChanged: (_) => setState(() {}),
            labelText: context.tr('Téléphone'),
            hintText: '70 12 34 56',
            large: true,
            errorText: _phone.text.trim().isEmpty
                ? null
                : _country.lengthProblem(_phone.text),
          ),
        ),
        FlowStep(
          id: 'role',
          title: context.tr('Quelle responsabilité ?'),
          help: _roles.isEmpty
              ? null
              : context.tr('Seulement en dessous de la vôtre.'),
          isValid: () => _role != null && _roles.contains(_role),
          builder: (_) => _roles.isEmpty
              ? Text(context.tr('Votre responsabilité ne permet pas d\'inviter quelqu\'un.'))
              : FlowChoice<String>(
                  options: [
                    for (final r in _roles)
                      FlowOption(r, context.tr(roleLabel(r)),
                          detail: context.tr(roleLine(r))),
                  ],
                  value: _role,
                  onChanged: (v) => setState(() => _role = v),
                ),
        ),
        FlowStep(
          id: 'sees',
          title: context.tr('Ce que {name} verra', {'name': _who}),
          builder: (_) => _sees(theme),
        ),
        FlowStep(
          id: 'salary',
          title: context.tr('Son salaire'),
          help: context.tr('Noté dans Équipe dès qu\'il rejoint. Le payer reste dans « Paie et journées ».'),
          optional: true,
          isValid: () => _salary.text.trim().isEmpty || _amount > 0,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('team-salary'),
                controller: _salary,
                suffix: cur,
                decimal: false,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final p in const ['month', 'week', 'day'])
                    ChoiceChip(
                      key: Key('team-period-$p'),
                      label: Text(_periodLabel(p)),
                      selected: _period == p,
                      onSelected: (_) => setState(() => _period = p),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
      summary: (_) => FlowSummary(rows: [
        FlowSummaryRow(
            context.tr('Nom'),
            _name.text.trim().isEmpty ? context.tr('Pas dit') : _name.text.trim(),
            step: 'name',
            bold: true),
        if (_title.text.trim().isNotEmpty)
          FlowSummaryRow(context.tr('Fonction'), _title.text.trim(), step: 'name'),
        FlowSummaryRow(
            context.tr('WhatsApp'),
            _phone.text.trim().isEmpty
                ? context.tr('Pas de numéro : le code marche pour qui l\'a')
                : _country.toE164(_phone.text),
            step: 'phone'),
        FlowSummaryRow(context.tr('Responsabilité'),
            _role == null ? '—' : context.tr(roleLabel(_role!)),
            step: 'role'),
        FlowSummaryRow(
            context.tr('Les chiffres'),
            _visibility == 'summary'
                ? context.tr('Seulement les totaux')
                : context.tr('Tout le détail'),
            step: 'sees'),
        FlowSummaryRow(
            context.tr('Salaire'),
            _amount > 0
                ? '${money.format(_amount)} ${_periodLabel(_period)}'
                : context.tr('Pas dit'),
            step: 'salary'),
      ]),
      onSave: _save,
      done: (_) => FlowDone(
        message: _name.text.trim().isEmpty
            ? context.tr('L\'invitation est prête')
            : context.tr('L\'invitation de {name} est prête', {'name': _name.text.trim()}),
        details: inv == null
            ? null
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(inv.code,
                        key: const Key('team-code'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold, letterSpacing: 3)),
                  ),
                  const SizedBox(height: 12),
                  // The new person standing right there: one phone at the other.
                  QrImageView(
                      data: inv.code, size: 140, backgroundColor: Colors.white),
                  Text(context.tr('Ou faites-lui scanner ce code s’il est à côté de vous.'),
                      textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  if (_salaryFailed) ...[
                    const SizedBox(height: 8),
                    Text(
                        context.tr('Le salaire n\'a pas pu être noté : dites-le dans Équipe quand {name} aura rejoint.',
                            {'name': _who}),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ],
              ),
        actions: [
          FlowAction(
            key: const Key('team-send'),
            primary: true,
            label: context.tr('Envoyer sur WhatsApp'),
            icon: Icons.send,
            onPressed: _send,
          ),
          FlowAction(
            key: const Key('team-copy'),
            label: context.tr('Copier le code'),
            icon: Icons.copy,
            onPressed: _copy,
          ),
          FlowAction(
            key: const Key('team-again'),
            label: context.tr('Inviter quelqu’un d’autre'),
            icon: Icons.person_add_alt_1,
            onPressed: _again,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/console/command_center.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/onboarding/application_form.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_mark.dart';
import '../auth/org_picker_screen.dart' show iconForProfile, kindColour, kindInk, kindSingular;
import '../setup/create_my_business_screen.dart' show businessActivities;

/// « Activités créées » (111): what the command center's « Demandes » was.
/// People create their business at once now — nothing waits for approval —
/// so this is the list of what they created: the business, its line of
/// trade, its town, who made it and how to reach them, and the creation
/// page's answers as they were asked. The requests of before stay
/// readable: approved by Mara, or refused with the reason. A card opens
/// the business's fiche.
class CreatedBusinessesScreen extends StatefulWidget {
  const CreatedBusinessesScreen({super.key, required this.center});

  final CommandCenterRepository center;

  @override
  State<CreatedBusinessesScreen> createState() => _CreatedBusinessesScreenState();
}

class _CreatedBusinessesScreenState extends State<CreatedBusinessesScreen> {
  CreatedBusinesses? _list;
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
      final list = await widget.center.createdBusinesses();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Activités créées')),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(_error!),
                  trailing: TextButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                context.tr('Chacun crée son activité tout de suite, sans demande à valider. Elles sont ici, la plus récente d\'abord, avec les demandes d\'avant.'),
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if ((list?.oldRequests ?? 0) > 0)
              Container(
                key: const Key('created-old-requests'),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: maraCaramel.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(list!.oldRequests == 1
                    ? context.tr(
                        '1 demande envoyée depuis une ancienne version de l\'application attend : la personne peut maintenant créer son activité elle-même, dans la nouvelle version.')
                    : context.tr(
                        '{n} demandes envoyées depuis une ancienne version de l\'application attendent : la personne peut maintenant créer son activité elle-même, dans la nouvelle version.',
                        {'n': list.oldRequests})),
              ),
            for (final b in list?.items ?? const <CreatedBusiness>[]) _card(theme, b),
            if (!_loading && _error == null && (list?.items.isEmpty ?? true))
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(Icons.add_business_outlined, size: 48, color: theme.disabledColor),
                    const SizedBox(height: 12),
                    Text(context.tr('Aucune activité créée pour l\'instant.'),
                        style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The business's phone, unless it is the person's (digits compared).
  static String? _ownPhone(CreatedBusiness b) {
    String digits(String? v) => (v ?? '').replaceAll(RegExp(r'\D'), '');
    final phone = b.phone;
    if (phone == null || digits(phone).isEmpty) return null;
    return digits(phone) == digits(b.personPhone) ? null : phone;
  }

  Widget _card(ThemeData theme, CreatedBusiness b) {
    final activity = b.activity == null
        ? null
        : businessActivities(context, kindOf(b.profile))
            .where((a) => a.key == b.activity)
            .map((a) => a.name)
            .firstOrNull;
    final day = b.at == null ? null : DateFormat('d MMM y', 'fr_FR').format(b.at!);
    final how = switch (b.how) {
      'approved' => context.tr('Demande validée par Mara'),
      'rejected' => context.tr('Demande refusée : {reason}', {'reason': b.note ?? ''}),
      _ => context.tr('Créée par la personne'),
    };
    final kind = kindOf(b.profile);
    return KajCard(
      key: Key('created-${b.slug ?? b.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: b.orgId == null ? null : () => context.push(Routes.consoleOrg(b.orgId!)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: kindColour(kind), borderRadius: BorderRadius.circular(12)),
                    child: Icon(iconForProfile(kind), color: kindInk(kind)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          [
                            kindSingular(context, b.profile),
                            ?activity,
                            if (b.slug != null) 'marakaj.com/s/${b.slug}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (b.archived)
                    Chip(label: Text(context.tr('Archivée')), visualDensity: VisualDensity.compact),
                  if (b.orgId != null) const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                [how, ?day].join(' · '),
                style: theme.textTheme.labelLarge?.copyWith(
                    color: b.how == 'rejected' ? theme.colorScheme.error : maraBrown),
              ),
              if (b.person != null || b.personPhone != null || b.personEmail != null)
                Text([?b.person, ?b.personPhone, ?b.personEmail].join(' · '),
                    style: theme.textTheme.bodyMedium),
              // The business's phone once: not again when it is the
              // person's own number, said on the line above.
              if (b.city != null || b.area != null || _ownPhone(b) != null)
                Text([?b.area, ?b.city, ?_ownPhone(b)].join(' · '), style: theme.textTheme.bodyMedium),
              if (b.about != null) ...[
                const SizedBox(height: 6),
                Text(b.about!, style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
              ],
              if (b.answers.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Answers(answers: b.answers),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A legacy church reads as an association.
  static String kindOf(String profile) => profile == 'church' ? 'association' : profile;
}

/// The creation page's questions on a card, each with its answer.
class _Answers extends StatelessWidget {
  const _Answers({required this.answers});

  final List<ApplicationAnswer> answers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String said(ApplicationAnswer a) => switch (a.value) {
          true => context.tr('Oui'),
          false => context.tr('Non'),
          final num n => NumberFormat.decimalPattern('fr_FR').format(n),
          final v => '${v ?? ''}',
        };
    return Container(
      key: const Key('created-answers'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in answers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.label,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text(said(a), style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

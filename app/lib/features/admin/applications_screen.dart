import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:intl/intl.dart';

import '../../core/onboarding/application_form.dart';
import '../../core/onboarding/onboarding_repository.dart';
import '../../core/errors.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// The platform's queue: people asking for a business to exist.
///
/// `create_org()` has been platform-admin-only since 010, and the reason has
/// not changed — whether a new tenant appears on this platform is a decision
/// somebody makes, not a form submission. What was missing was somewhere to
/// make it. Before this screen an application would have gone to an email
/// nobody sent.
///
/// Approving creates the business and makes the applicant its **owner**, in
/// one transaction. That is the whole point of approving rather than
/// creating: they asked for it, so it is theirs, and the reviewer does not
/// quietly become a member of somebody else's books.
///
/// Rejecting requires a reason, enforced by the server and not only by this
/// form. A refusal somebody cannot act on produces the same application again
/// next week, with the same problem in it. Ready reasons fill it in one tap.
///
/// Each card carries the request page's answers (107) as they were asked,
/// and the applicant hears the decision on their bell (107's trigger):
/// accepted with their business to open, refused with the reason.
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key, required this.onboarding});

  final OnboardingRepository onboarding;

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  List<OrgApplication> _applications = const [];
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
      final rows = await widget.onboarding.pendingApplications();
      if (!mounted) return;
      setState(() {
        _applications = rows;
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

  Future<void> _approve(OrgApplication application) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Valider {name} ?', {'name': application.name})),
        content: Text(
          'L’entreprise sera créée à l’adresse « ${application.slug} », et '
          '${application.applicant ?? 'le demandeur'} en deviendra '
          'propriétaire. ${context.tr('Le demandeur est prévenu.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Valider')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(
      () => widget.onboarding.approve(application.id),
      '${application.name} créée.',
    );
  }

  Future<void> _reject(OrgApplication application) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(application: application),
    );
    if (!mounted || reason == null || reason.trim().isEmpty) return;

    await _run(
      () => widget.onboarding.reject(application.id, reason.trim()),
      context.tr('Demande refusée. Le demandeur est prévenu.'),
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (error) {
      // The server's refusals say something useful — the address was taken
      // while this was waiting, the application is already decided — and are
      // better than anything this screen could invent.
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Demandes'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.tr('Réessayer')),
                    ),
                  ],
                ),
              ),
            ],
            for (final application in _applications)
              KajCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(application.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${application.slug} · ${_profileLabel(application.profile)}'
                        ' · ${application.currency}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          application.applicant,
                          application.contactPhone,
                          application.contactEmail,
                        ]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (application.description != null &&
                          application.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(application.description!),
                      ],
                      if (application.answers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _Answers(answers: application.answers),
                      ],
                      if (application.createdAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Reçue le ${DateFormat('d MMMM y', 'fr_FR').format(application.createdAt!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => _approve(application),
                            icon: const Icon(Icons.check, size: 18),
                            label: Text(context.tr('Valider')),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => _reject(application),
                            style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.error),
                            icon: const Icon(Icons.close, size: 18),
                            label: Text(context.tr('Refuser')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (!_loading && _applications.isEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 48),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 48, color: theme.disabledColor),
                    const SizedBox(height: 12),
                    Text(context.tr('Aucune demande en attente.'),
                        style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _profileLabel(String profile) => switch (profile) {
        'church' || 'association' => 'Association',
        'farm' => 'Ferme',
        'retail' => 'Commerce',
        _ => 'Autre',
      };
}

/// The request page's questions on a card, each with its answer.
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
      key: const Key('application-answers'),
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

/// Refusing, with the reason that makes the refusal useful.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.application});

  final OrgApplication application;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Refuser {name}', {'name': widget.application.name})),
      content: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Le demandeur verra ce message et pourra corriger sa demande.'),
          ),
          const SizedBox(height: 12),
          // Ready reasons: one tap writes it, the field can still be edited.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in [
                context.tr('Informations manquantes'),
                context.tr('Nom déjà utilisé'),
                context.tr('Adresse (lien) à changer'),
                context.tr('Activité hors du champ de Mara'),
                context.tr('Demande en double'),
              ])
                ActionChip(
                  label: Text(r),
                  onPressed: () => _reason.text = r,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: context.tr('Nom déjà utilisé, informations manquantes…'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          // The server refuses an empty reason too. Both, because a dialog
          // that lets it through only to be rejected teaches people the app
          // is unreliable.
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reason.text),
          child: Text(context.tr('Refuser')),
        ),
      ],
    );
  }
}

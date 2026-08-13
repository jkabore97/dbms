import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/onboarding/onboarding_repository.dart';
import '../admin/create_business_screen.dart';
import 'profile_form_screen.dart';
import '../../core/errors.dart';

/// What somebody sees when they have an account and belong to nothing.
///
/// This replaces a screen that offered "J'ai un code" — a menu entry that
/// assumed somebody had already been given one, by some means the app knew
/// nothing about. The two things a person in this position actually is:
///
///   **Somebody's new employee**, holding a code their manager sent them over
///   WhatsApp. One field, one button.
///
///   **Somebody starting a business**, who needs it to exist before anything
///   else can happen. A form, and then a wait — because whether a new tenant
///   appears on this platform is a decision made by a person, not a form
///   submission.
///
/// The waiting state is a first-class part of this screen rather than an
/// afterthought. An application that disappears into silence is one the
/// applicant submits again next week, which is how a review queue fills up
/// with the same business four times.
class JoinOrApplyScreen extends StatefulWidget {
  const JoinOrApplyScreen({
    super.key,
    required this.identity,
    required this.onboarding,
    required this.admin,
    required this.onRetry,
    required this.onSignOut,
    this.onJoined,
    this.checking = false,
  });

  final LocalIdentity identity;
  final OnboardingRepository onboarding;
  final AdminRepository admin;

  /// Re-resolves the org list. Called after a code is claimed, because the
  /// business the person just joined is the thing they want to open.
  final Future<void> Function() onRetry;
  final VoidCallback onSignOut;
  final VoidCallback? onJoined;
  final bool checking;

  @override
  State<JoinOrApplyScreen> createState() => _JoinOrApplyScreenState();
}

class _JoinOrApplyScreenState extends State<JoinOrApplyScreen> {
  final _code = TextEditingController();

  OrgApplication? _application;
  bool _profileComplete = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final complete = await widget.onboarding.isProfileComplete();
    final application = await widget.onboarding.myApplication();
    if (!mounted) return;
    setState(() {
      _profileComplete = complete;
      _application = application;
      _loading = false;
    });
  }

  Future<void> _editProfile({String? intro, String? nextLabel}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileFormScreen(
          onboarding: widget.onboarding,
          intro: intro,
          nextLabel: nextLabel ?? 'Enregistrer',
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _claim() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      // Returns the org's id, not its name. The name arrives with the org
      // list a moment later, and routing into the business is the real
      // confirmation — this line only has to say the code worked.
      await widget.admin.claimInvitation(_code.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Code accepté. Ouverture de votre entreprise…';
      });
      await widget.onRetry();
      widget.onJoined?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The server's refusals are sentences a person can act on — expired,
        // already used, issued for another number — and are better than
        // anything this screen could invent.
        _error = describeError(error);
      });
    }
  }

  Future<void> _apply() async {
    // The business form asks for a slug and a profile; the application then
    // needs the person's own details, which is why the profile comes first.
    if (!_profileComplete) {
      await _editProfile(
        intro: 'Avant de décrire votre entreprise, dites-nous qui vous êtes. '
            'Ces informations figureront sur la demande.',
        nextLabel: 'Continuer',
      );
      if (!_profileComplete) return;
    }
    if (!mounted) return;

    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateBusinessScreen(
          admin: widget.admin,
          onboarding: widget.onboarding,
          asApplication: true,
        ),
      ),
    );
    if (applied == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = widget.identity.phone ?? widget.identity.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bienvenue sur Kaj'),
        actions: [
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  Text(
                    widget.identity.label.isEmpty
                        ? 'Votre compte est créé.'
                        : 'Bonjour ${widget.identity.label}.',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contact == null
                        ? 'Votre compte existe. Il ne donne encore accès à '
                            'aucune entreprise.'
                        : 'Compte $contact. Il ne donne encore accès à aucune '
                            'entreprise.',
                    style: theme.textTheme.bodySmall,
                  ),

                  // The profile prompt sits above both routes because both
                  // need it, and because somebody who fills it in now does
                  // not get asked again halfway through the other thing.
                  if (!_profileComplete) ...[
                    const SizedBox(height: 20),
                    Card(
                      color: theme.colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('Complétez vos informations'),
                        subtitle: const Text(
                            'Nom, date de naissance, téléphone. Nécessaire '
                            'pour un contrat ou un bulletin de paie.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editProfile(
                          intro: 'Ces informations vous suivent dans toutes '
                              'les entreprises que vous rejoindrez.',
                        ),
                      ),
                    ),
                  ],

                  if (_application != null) ...[
                    const SizedBox(height: 20),
                    _ApplicationCard(
                      application: _application!,
                      onEdit: _apply,
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Route one, and first because it is far more common: most
                  // people arriving here were sent a code by somebody.
                  Text('On vous a envoyé un code ?',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Votre responsable vous l’a envoyé par WhatsApp ou SMS.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: "Code d'invitation",
                      hintText: 'XXXX-XXXX',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        _busy || _code.text.trim().length < 4 ? null : _claim,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: const Text('Rejoindre l’entreprise'),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!,
                        style: TextStyle(color: theme.colorScheme.primary)),
                  ],

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Route two.
                  Text('Vous dirigez une entreprise ?',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Décrivez-la et envoyez la demande. Un administrateur '
                    'Kaj-consulting la valide, puis vous en devenez '
                    'propriétaire.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy || (_application?.isPending ?? false)
                        ? null
                        : _apply,
                    icon: const Icon(Icons.add_business_outlined),
                    label: Text(_application?.isPending ?? false
                        ? 'Demande en cours'
                        : 'Demander une entreprise'),
                  ),

                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: widget.checking ? null : () => widget.onRetry(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Vérifier à nouveau'),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Where an application has got to.
///
/// Shown in full, including the reason for a refusal, because a rejection the
/// applicant cannot read is one they respond to by applying again with the
/// same details.
class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.application, required this.onEdit});

  final OrgApplication application;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (colour, icon, headline) = switch (application.status) {
      'approved' => (
          theme.colorScheme.primaryContainer,
          Icons.check_circle_outline,
          '${application.name} est validée',
        ),
      'rejected' => (
          theme.colorScheme.errorContainer,
          Icons.cancel_outlined,
          'Demande refusée',
        ),
      _ => (
          theme.colorScheme.tertiaryContainer,
          Icons.hourglass_top,
          'Demande envoyée',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(headline, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${application.name} · ${application.slug}'
            '${application.createdAt == null ? '' : ' · envoyée le ${DateFormat('d MMM y', 'fr_FR').format(application.createdAt!)}'}',
            style: theme.textTheme.bodySmall,
          ),
          if (application.isPending) ...[
            const SizedBox(height: 8),
            Text(
              'Nous vous répondrons bientôt. Vous pouvez modifier la demande '
              'tant qu’elle est en attente.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onEdit,
              child: const Text('Modifier la demande'),
            ),
          ],
          if (application.isRejected && application.decisionNote != null) ...[
            const SizedBox(height: 8),
            Text(application.decisionNote!),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onEdit,
              child: const Text('Corriger et renvoyer'),
            ),
          ],
          if (application.isApproved) ...[
            const SizedBox(height: 8),
            Text(
              'Ouvrez-la depuis l’écran d’accueil. Vous en êtes propriétaire.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

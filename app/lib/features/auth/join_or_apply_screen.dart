import '../../core/theme/kaj_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/onboarding/onboarding_repository.dart';
import 'profile_form_screen.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// What somebody sees when they have an account and belong to nothing.
///
/// This replaces a screen that offered "J'ai un code" — a menu entry that
/// assumed somebody had already been given one, by some means the app knew
/// nothing about. The two things a person in this position actually is:
///
///   **Somebody's new employee**, holding a code their manager sent them over
///   WhatsApp. One field, one button.
///
///   **Somebody starting a business.** Since 111 they create it themselves,
///   at once — « Créer mon activité » opens the questions, and the business
///   is theirs the moment they finish. There is no request to wait on any
///   more, so this screen no longer watches for one.
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
    if (!mounted) return;
    setState(() {
      _profileComplete = complete;
      _loading = false;
    });
  }

  Future<void> _editProfile({String? intro}) async {
    // Kept as a pushed page rather than a route of its own: the wording
    // changes with why it was opened (before an application it explains
    // itself differently), and that is content, not an address.
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileFormScreen(
          onboarding: widget.onboarding,
          intro: intro,
          nextLabel: context.tr('Enregistrer'),
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
        _message = context.tr('Code accepté. Ouverture de votre entreprise…');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = widget.identity.phone ?? widget.identity.email;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Bienvenue sur Mara')),
        actions: [
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: context.tr('Se déconnecter'),
          ),
          bellRoom,
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
                        ? context.tr('Votre compte est créé.')
                        : context.tr('Bonjour {label}.', {'label': widget.identity.label}),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contact == null
                        ? context.tr('Votre compte existe. Il ne donne encore accès à aucune entreprise.')
                        : context.tr('Compte {contact}. Il ne donne encore accès à aucune entreprise.', {'contact': contact}),
                    style: theme.textTheme.bodySmall,
                  ),

                  // The profile prompt sits above both routes because both
                  // need it, and because somebody who fills it in now does
                  // not get asked again halfway through the other thing.
                  if (!_profileComplete) ...[
                    const SizedBox(height: 20),
                    KajCard(
                      color: theme.colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(context.tr('Complétez vos informations')),
                        subtitle: Text(
                            context.tr('Nom, date de naissance, téléphone. Nécessaire pour un contrat ou un bulletin de paie.')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editProfile(
                          intro: 'Ces informations vous suivent dans toutes '
                              'les entreprises que vous rejoindrez.',
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Route one, and first because it is far more common: most
                  // people arriving here were sent a code by somebody.
                  Text(context.tr('On vous a envoyé un code ?'),
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('Votre responsable vous l’a envoyé par WhatsApp ou SMS.'),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: context.tr('Code d\'invitation'),
                      hintText: context.tr('XXXX-XXXX'),
                      border: const OutlineInputBorder(),
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
                    label: Text(context.tr('Rejoindre l’entreprise')),
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

                  // Route two: one's own business, created at once (111).
                  Text(context.tr('Vous avez une activité ?'),
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('Boutique, ferme ou association : créez-la en quelques minutes. Elle est à vous tout de suite.'),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      key: const Key('join-create'),
                      onPressed: _busy ? null : () => context.push(Routes.createBusiness),
                      icon: const Icon(Icons.add_business_outlined),
                      label: Text(context.tr('Créer mon activité')),
                    ),
                  ),

                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: widget.checking ? null : () => widget.onRetry(),
                    icon: const Icon(Icons.refresh),
                    label: Text(context.tr('Vérifier à nouveau')),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/auth/models.dart';

/// Signed in, invited to nothing.
///
/// This is not an error and must not look like one. It happens every time a
/// new employee verifies their number before the owner has added them, which
/// in practice is most first sign-ins. The screen's job is to say "you are in,
/// the next move belongs to someone else" and to show the number the owner
/// needs in order to make it.
class NoOrgScreen extends StatelessWidget {
  const NoOrgScreen({
    super.key,
    required this.identity,
    required this.onRetry,
    required this.onSignOut,
    this.checking = false,
  });

  final LocalIdentity identity;
  final Future<void> Function() onRetry;
  final VoidCallback onSignOut;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = identity.phone ?? identity.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('En attente'),
        actions: [
          IconButton(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Votre compte est prêt',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  "Vous n'êtes encore rattaché à aucune activité. "
                  "Demandez au responsable de vous ajouter, puis appuyez sur "
                  'Vérifier.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (contact != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'À communiquer au responsable',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          contact,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: checking ? null : () => onRetry(),
                    icon: checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text(
                      'Vérifier',
                      style: TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

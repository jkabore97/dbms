import 'package:flutter/material.dart';

import '../../core/db/local_db.dart';

/// The account menu every home screen carries: who you are, how to switch
/// businesses, how to leave.
///
/// Signing out with work still in the outbox is the one genuinely destructive
/// thing a user can do here — those entries exist nowhere else — so it asks
/// first, and says exactly how many are at stake.
class AccountMenu extends StatelessWidget {
  const AccountMenu({
    super.key,
    required this.db,
    required this.userLabel,
    required this.onSignOut,
    this.onSwitchOrg,
    this.onAdminister,
    this.onJoinByCode,
  });

  final LocalDb db;
  final String userLabel;
  final VoidCallback onSignOut;

  /// Null when the user belongs to only one business.
  final VoidCallback? onSwitchOrg;

  /// Null unless this person administers the org they are currently in.
  final VoidCallback? onAdminister;

  /// Joining a second business from inside the first — the case where someone
  /// already using the app is handed a code for somewhere else.
  final VoidCallback? onJoinByCode;

  Future<void> _confirmSignOut(BuildContext context) async {
    final pending = await db.pendingCount();
    if (!context.mounted) return;

    if (pending == 0) {
      onSignOut();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Des données ne sont pas encore envoyées'),
        content: Text(
          '$pending enregistrement${pending > 1 ? 's' : ''} '
          "attend${pending > 1 ? 'ent' : ''} le réseau. "
          'Ces données restent sur cet appareil et seront envoyées à la '
          'prochaine connexion de ce compte.\n\n'
          'Se déconnecter maintenant ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Rester connecté'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );

    if (confirmed == true) onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: 'Compte',
      onSelected: (value) {
        switch (value) {
          case 'admin':
            onAdminister?.call();
          case 'join':
            onJoinByCode?.call();
          case 'switch':
            onSwitchOrg?.call();
          case 'signout':
            _confirmSignOut(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            userLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const PopupMenuDivider(),
        if (onAdminister != null)
          const PopupMenuItem<String>(
            value: 'admin',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Administration'),
            ),
          ),
        if (onJoinByCode != null)
          const PopupMenuItem<String>(
            value: 'join',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.confirmation_number_outlined),
              title: Text("J'ai un code"),
            ),
          ),
        if (onSwitchOrg != null)
          const PopupMenuItem<String>(
            value: 'switch',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.swap_horiz),
              title: Text("Changer d'activité"),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Se déconnecter'),
          ),
        ),
      ],
    );
  }
}

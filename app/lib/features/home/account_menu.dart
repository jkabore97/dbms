import 'package:flutter/material.dart';

import '../../l10n/strings.dart';

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
    this.onAccounting,
    this.onCreateBusiness,
    this.onBusinesses,
    this.onApplications,
    this.onInvite,
    this.onMyProfile,
    this.onApplyForOrg,
    this.onLanguage,
  });

  final LocalDb db;
  final String userLabel;
  final VoidCallback onSignOut;

  /// Null when the user belongs to only one business.
  final VoidCallback? onSwitchOrg;

  /// Null unless this person administers the org they are currently in.
  final VoidCallback? onAdminister;

  /// The platform's own list of businesses. Null for everyone who is not a
  /// platform admin, and `all_orgs()` refuses them server-side anyway.
  final VoidCallback? onBusinesses;

  /// The platform's queue of businesses being asked for. Platform admin only.
  final VoidCallback? onApplications;

  /// Generating a code to send somebody. This is what replaced "J'ai un
  /// code": that entry sat with the invitee, who by definition does not have
  /// the app yet.
  final VoidCallback? onInvite;

  /// The books: journal, résultat, bilan, plan comptable, balance. Offered to
  /// every member rather than to admins only — a summary observer opening
  /// these is shown the totals and no line items, which is decided by the
  /// server in 006 and 007 and not by whether a menu entry was drawn.
  ///
  /// Null in a build with no server, since every one of those screens is a
  /// query the device cannot answer.
  final VoidCallback? onAccounting;

  /// Joining a second business from inside the first — the case where someone
  /// already using the app is handed a code for somewhere else.
  /// Who this person is: names, date of birth, job title, phone. Offered to
  /// everyone, always.
  ///
  /// It used to be reachable only from the screen somebody sees before they
  /// belong to any business — which meant that once you were in, there was no
  /// way to fill it in or fix a typo in your own name, and anybody who
  /// already had a business never saw the form at all.
  final VoidCallback? onMyProfile;

  /// Asking for another business. Not the same as creating one: this files a
  /// request for a platform admin to approve, and it is here because the
  /// person who wants a second shop is by definition somebody who already has
  /// a first one and never sees the welcome screen again.
  final VoidCallback? onApplyForOrg;

  /// Null for everyone except a platform admin.
  final VoidCallback? onCreateBusiness;

  /// The device's language. Offered to everyone; the same screen is reachable
  /// from the sign-in page for the person not yet signed in.
  final VoidCallback? onLanguage;

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
        title: Text(Strings.of(context).unsentDataTitle),
        content: Text(Strings.of(context).unsentDataBody(pending)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Strings.of(context).stayConnected),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Strings.of(context).signOut),
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
      tooltip: Strings.of(context).account,
      onSelected: (value) {
        switch (value) {
          case 'accounting':
            onAccounting?.call();
          case 'admin':
            onAdminister?.call();
          case 'businesses':
            onBusinesses?.call();
          case 'applications':
            onApplications?.call();
          case 'invite':
            onInvite?.call();
          case 'profile':
            onMyProfile?.call();
          case 'apply':
            onApplyForOrg?.call();
          case 'create':
            onCreateBusiness?.call();
          case 'switch':
            onSwitchOrg?.call();
          case 'language':
            onLanguage?.call();
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
        if (onMyProfile != null)
          PopupMenuItem<String>(
            value: 'profile',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: Text(Strings.of(context).myProfile),
            ),
          ),
        if (onAccounting != null)
          PopupMenuItem<String>(
            value: 'accounting',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(Strings.of(context).accounting),
            ),
          ),
        if (onAdminister != null)
          PopupMenuItem<String>(
            value: 'admin',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(Strings.of(context).administration),
            ),
          ),
        if (onInvite != null)
          PopupMenuItem<String>(
            value: 'invite',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_add_alt),
              title: Text(Strings.of(context).inviteSomeone),
            ),
          ),
        if (onApplications != null)
          PopupMenuItem<String>(
            value: 'applications',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inbox_outlined),
              title: Text(Strings.of(context).applications),
            ),
          ),
        if (onBusinesses != null)
          PopupMenuItem<String>(
            value: 'businesses',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.business_outlined),
              title: Text(Strings.of(context).businesses),
            ),
          ),
        if (onApplyForOrg != null)
          PopupMenuItem<String>(
            value: 'apply',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.business_center_outlined),
              title: Text(Strings.of(context).applyForBusiness),
            ),
          ),
        if (onCreateBusiness != null)
          PopupMenuItem<String>(
            value: 'create',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_business_outlined),
              title: Text(Strings.of(context).newBusiness),
            ),
          ),
        if (onSwitchOrg != null)
          PopupMenuItem<String>(
            value: 'switch',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: Text(Strings.of(context).switchBusiness),
            ),
          ),
        // The language of this device, offered to everybody signed in the
        // same way it is offered before sign-in.
        PopupMenuItem<String>(
          value: 'language',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(Strings.of(context).language),
          ),
        ),
        PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: Text(Strings.of(context).signOut),
          ),
        ),
      ],
    );
  }
}

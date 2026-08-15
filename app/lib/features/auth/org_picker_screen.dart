import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../l10n/strings.dart';

/// Shown when someone belongs to more than one business — the accountant who
/// keeps books for a church and a farm, or an owner with two shops.
///
/// There is no "remember my choice": picking the wrong set of books and not
/// noticing is worse than one extra tap at launch.
class OrgPickerScreen extends StatelessWidget {
  const OrgPickerScreen({
    super.key,
    required this.orgs,
    required this.onSelected,
    this.onSignOut,
    this.onCreateBusiness,
    this.onBusinesses,
    this.title,
  });

  final List<OrgSummary> orgs;
  final void Function(OrgSummary org) onSelected;
  final VoidCallback? onSignOut;

  /// Null for everyone except a platform admin, whose list here is every
  /// business there is rather than the ones they were invited to.
  final VoidCallback? onCreateBusiness;

  /// Also platform-admin only: the list here is already every business, so
  /// this is the natural place to reach the one screen that can rename,
  /// archive or delete one.
  final VoidCallback? onBusinesses;

  /// Null takes the localized default. Passed only by callers that mean
  /// something narrower than "choose".
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? Strings.of(context).pickBusiness),
        actions: [
          if (onBusinesses != null)
            IconButton(
              onPressed: onBusinesses,
              icon: const Icon(Icons.business_outlined),
              tooltip: Strings.of(context).manageBusinesses,
            ),
          if (onCreateBusiness != null)
            IconButton(
              onPressed: onCreateBusiness,
              icon: const Icon(Icons.add_business_outlined),
              tooltip: Strings.of(context).newBusiness,
            ),
          if (onSignOut != null)
            IconButton(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
              tooltip: Strings.of(context).signOut,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orgs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final org = orgs[i];
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      iconForProfile(org.profile),
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    org.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    [
                      localizedProfile(context, org.profile),
                      if (org.roles.isNotEmpty) labelForRole(org.roles.first),
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onSelected(org),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

IconData iconForProfile(String profile) {
  switch (profile) {
    case 'church':
      return Icons.church_outlined;
    case 'farm':
      return Icons.agriculture_outlined;
    case 'retail':
      return Icons.storefront_outlined;
    default:
      return Icons.business_outlined;
  }
}

/// The localized profile label. The plain [labelForProfile] stays for the
/// screens not yet migrated; new code takes this one.
String localizedProfile(BuildContext context, String profile) {
  final strings = Strings.of(context);
  switch (profile) {
    case 'church':
      return strings.church;
    case 'farm':
      return strings.farm;
    case 'retail':
      return strings.shop;
    default:
      return strings.business;
  }
}

String labelForProfile(String profile) {
  switch (profile) {
    case 'church':
      return 'Église';
    case 'farm':
      return 'Ferme';
    case 'retail':
      return 'Commerce';
    default:
      return 'Activité';
  }
}

String labelForRole(String role) {
  switch (role) {
    case 'owner':
      return 'Propriétaire';
    case 'super_admin':
      return 'Super administrateur';
    case 'admin':
      return 'Administrateur';
    case 'manager':
      return 'Gestionnaire';
    case 'supervisor':
      return 'Superviseur';
    case 'employee':
      return 'Employé';
    case 'observer':
      return 'Observateur';
    case 'approver':
      return 'Approbateur';
    default:
      return role;
  }
}

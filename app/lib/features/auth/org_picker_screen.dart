import 'package:flutter/material.dart';

import '../../core/auth/models.dart';

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
    this.title = 'Choisissez une activité',
  });

  final List<OrgSummary> orgs;
  final void Function(OrgSummary org) onSelected;
  final VoidCallback? onSignOut;

  /// Null for everyone except a platform admin, whose list here is every
  /// business there is rather than the ones they were invited to.
  final VoidCallback? onCreateBusiness;

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (onCreateBusiness != null)
            IconButton(
              onPressed: onCreateBusiness,
              icon: const Icon(Icons.add_business_outlined),
              tooltip: 'Nouvelle activité',
            ),
          if (onSignOut != null)
            IconButton(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
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
                      labelForProfile(org.profile),
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

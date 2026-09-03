import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/nav/router.dart';

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
    this.loading = false,
    this.onRetry,
    this.onSignOut,
    this.onCreateBusiness,
    this.onBusinesses,
    this.title,
  });

  final List<OrgSummary> orgs;
  final void Function(OrgSummary org) onSelected;

  /// True while the business list is still being fetched. It matters because
  /// this screen can be opened cold — a bookmark or a reload straight onto
  /// `/entreprises` — before any org has arrived, and for a platform admin the
  /// list is *every* business there is, a heavier query that is slow on a thin
  /// connection. Without this the screen drew an empty page during that whole
  /// window, which reads as broken. An empty list is either "still loading"
  /// (spinner) or, once loaded, "you belong to none" (a message) — never a
  /// blank.
  final bool loading;

  /// Retries the resolve from the loading state's escape hatch. A resolve that
  /// stalls should recover on its own within seconds, but if it does not, this
  /// screen must never be a trap: after a short wait it offers a way to try
  /// again rather than spin forever.
  final VoidCallback? onRetry;

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
          IconButton(
            onPressed: () => context.go(Routes.directory),
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Les vitrines',
          ),
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
          child: orgs.isEmpty ? _empty(context) : _list(context, theme),
        ),
      ),
    );
  }

  /// Loading or truly empty — never a blank page. While the list is still on
  /// its way this is a spinner; once it has arrived empty (a rare state, since
  /// the router sends someone who belongs to nothing to the waiting room) it
  /// is a plain message rather than a screen that looks broken.
  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return _LoadingWithEscape(onRetry: onRetry, onSignOut: onSignOut);
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.business_outlined,
              size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            "Aucune entreprise pour l'instant.",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, ThemeData theme) {
    return ListView.separated(
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
    );
  }
}

/// The loading state, with an escape hatch.
///
/// A resolve that stalls now falls back to the cached list within seconds, so
/// the spinner is normally brief. But no spinner on this app may be a trap:
/// after a short wait this reveals "Réessayer" and "Se déconnecter", so a
/// person whose resolve never returns — a wedged local store, a connection
/// that neither answers nor errors — always has a way out instead of a screen
/// that loads forever.
class _LoadingWithEscape extends StatefulWidget {
  const _LoadingWithEscape({this.onRetry, this.onSignOut});

  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  State<_LoadingWithEscape> createState() => _LoadingWithEscapeState();
}

class _LoadingWithEscapeState extends State<_LoadingWithEscape> {
  bool _stuck = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Long enough that a normal resolve (bounded to ~12s per network step, and
    // usually far quicker) has finished and moved us off this screen; short
    // enough that a person is not left wondering. If we are still here at 10s,
    // something is wrong and they should be offered a way out.
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _stuck = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text('Chargement de vos entreprises…',
              style: theme.textTheme.bodyMedium),
          if (_stuck) ...[
            const SizedBox(height: 24),
            Text(
              'Cela prend plus de temps que prévu.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (widget.onRetry != null)
              FilledButton.icon(
                onPressed: () {
                  setState(() => _stuck = false);
                  _timer?.cancel();
                  _timer = Timer(const Duration(seconds: 10), () {
                    if (mounted) setState(() => _stuck = true);
                  });
                  widget.onRetry!();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            if (widget.onSignOut != null)
              TextButton(
                onPressed: widget.onSignOut,
                child: const Text('Se déconnecter'),
              ),
          ],
        ],
      ),
    );
  }
}

IconData iconForProfile(String profile) {
  switch (profile) {
    case 'church':
    case 'association':
      return Icons.groups_outlined;
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
    case 'association':
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
    case 'association':
      return 'Association';
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

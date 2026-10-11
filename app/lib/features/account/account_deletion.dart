import 'package:flutter/material.dart';

import '../../core/access/store_rules.dart';
import '../../core/admin/admin_repository.dart' show AccountDeletionPlan, DoomedBusiness;
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../shopper/shopper_profile_screen.dart' show DeleteAccountDialog;

/// « Supprimer mon compte » from a business's Compte (130): every account
/// type — a member, an owner — is deleted for real, from the app.
///
/// The server's plan first (128's delete_my_account_preview): what refuses
/// it now (said, nothing to type), or what disappears — each business the
/// person alone owns, with its members (who become plain shoppers), its
/// open orders (cancelled, each customer told) and what it pays outside —
/// and the businesses only left. Then the word, then the deletion, which
/// sends back the very list shown: a business that is not on it is never
/// deleted. An App Store subscription is the owner's to cancel (Mara
/// cannot): the confirmation says where.
Future<void> askAccountDeletion(
  BuildContext context, {
  Future<AccountDeletionPlan?> Function()? plan,
  Future<void> Function(List<String> confirmedOrgs)? delete,
  Future<void> Function()? signOut,
}) async {
  final scope = AppScope.maybeOf(context);
  final read = plan ?? scope?.admin.deletionPlan;
  final AccountDeletionPlan? p = read == null ? null : await read();
  if (!context.mounted) return;
  if (p == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.tr('La suppression n\'a pas pu être préparée : vérifiez la connexion et réessayez.'))));
    return;
  }
  if (p.blocked != null) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('deletion-blocked'),
        icon: const Icon(Icons.info_outline),
        title: Text(context.tr('Pas encore possible')),
        content: Text(context.tr(p.blocked!)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('Compris'))),
        ],
      ),
    );
    return;
  }
  final go = delete ??
      (List<String> orgs) async {
        final s = AppScope.of(context);
        if (!s.admin.canManageAccounts) {
          throw StateError(
              'La suppression en ligne n\'est pas encore ouverte : écrivez à Mara et votre compte sera supprimé.');
        }
        // An Apple account, on the iPhone: Apple's sheet once more, for the
        // code that revokes Apple's token.
        final code = await s.auth.appleReauthorizationCode();
        await s.admin.deleteMyAccount(confirmedOrgs: orgs, appleAuthorizationCode: code);
      };
  final gone = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteAccountDialog(
      message: p.businesses.isEmpty
          ? context.tr('Votre compte et vos données personnelles seront effacés pour toujours. Vous quittez les activités dont vous faites partie ; ce que vous y avez inscrit leur reste, sans votre nom.')
          : context.tr('Votre compte et vos données personnelles seront effacés pour toujours, et avec eux ces activités :'),
      details: DeletionSummary(plan: p),
      confirmLabel: context.tr('Supprimer définitivement'),
      delete: () => go(p.businessIds),
    ),
  );
  if (gone == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.tr('Votre compte est supprimé. Au revoir !'))));
    await (signOut ?? scope?.session.signOut)?.call();
  }
}

/// What disappears, business by business — the confirmation's middle.
class DeletionSummary extends StatelessWidget {
  const DeletionSummary({super.key, required this.plan});

  final AccountDeletionPlan plan;

  String _kind(BuildContext context, String profile) => switch (profile) {
        'farm' => context.tr('ferme'),
        'association' || 'church' => context.tr('association'),
        _ => context.tr('boutique'),
      };

  String _line(BuildContext context, DoomedBusiness b) {
    final parts = <String>[
      _kind(context, b.profile),
      if (b.members == 1) context.tr('1 membre redevient simple client'),
      if (b.members > 1) context.tr('{n} membres redeviennent simples clients', {'n': b.members}),
      if (b.orders == 1) context.tr('1 commande en cours annulée, le client prévenu'),
      if (b.orders > 1) context.tr('{n} commandes en cours annulées, les clients prévenus', {'n': b.orders}),
      if (b.storePlatforms.contains('google')) context.tr('l\'abonnement Google Play arrêté'),
      if (b.stripe && sellsDigitalInApp) context.tr('l\'abonnement par carte arrêté'),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('deletion-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in plan.businesses)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.store_mall_directory_outlined, size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: b.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' — ${_line(context, b)}'),
                    ]),
                    key: Key('deletion-business-${b.id}'),
                  ),
                ),
              ],
            ),
          ),
        if (plan.businesses.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(context.tr('Leurs ventes, leur stock, leurs comptes et leur vitrine disparaissent aussi : c\'est définitif.'),
              style: theme.textTheme.bodySmall),
        ],
        if (plan.appleStore > 0) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('deletion-apple-store'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(context.tr('Votre abonnement Mara Pro de l\'App Store continue d\'être facturé par Apple tant que vous ne l\'annulez pas : Réglages › votre nom › Abonnements › Mara Pro. Mara ne peut pas l\'annuler pour vous.')),
          ),
        ],
        if (plan.leaves.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(context.tr('Vous quittez aussi : {names}.', {'names': plan.leaves.join(', ')}),
              key: const Key('deletion-leaves')),
        ],
      ],
    );
  }
}

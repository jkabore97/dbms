import 'package:flutter/material.dart';

import '../../core/access/store_rules.dart';
import '../../core/admin/admin_repository.dart' show AccountDeletionPlan, AccountRefused, DoomedBusiness;
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
  // The website's Apple popup, ready before the confirmation (139).
  scope?.auth.warmAppleWeb();
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
        content: Text(deletionBlockedText(context, p)),
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
        // code that revokes Apple's token; on the website, Apple's popup
        // (139).
        final code = await s.auth.appleReauthorizationCode();
        await s.admin.deleteMyAccount(
            confirmedOrgs: orgs, appleAuthorizationCode: code, appleClient: s.auth.appleCodeClient);
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
      // S8: a sign-in older than ten minutes — signed out, to sign in again.
      reauth: signOut ?? scope?.session.signOut,
    ),
  );
  if (gone == true && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.tr('Votre compte est supprimé. Au revoir !'))));
    await (signOut ?? scope?.session.signOut)?.call();
  }
}

/// Why a deletion cannot be done now, in the reader's language: by the
/// server's code (128's blocked_code) and the business it names; the
/// server's own French only for a code this build does not know.
String deletionBlockedText(BuildContext context, AccountDeletionPlan p) => switch (p.blockedCode) {
      'platform' => context.tr('Ce compte gère la plateforme Mara : il ne peut pas être supprimé, sinon plus personne ne pourrait la gérer. Pour essayer la suppression, utilisez un autre compte.'),
      'own_order' => context.tr('Une commande est en cours : attendez qu\'elle soit terminée, ou annulez-la, puis supprimez votre compte.'),
      'delivering' => context.tr('Une livraison est en cours : terminez-la, puis supprimez votre compte.'),
      'business_order' => context.tr('Une commande de « {name} » est en route ou déjà payée en ligne : livrez-la ou remboursez-la, puis supprimez votre compte.', {'name': p.blockedShop ?? ''}),
      'payout' => context.tr('Mara doit encore verser à « {name} » l\'argent d\'une commande payée par Wave (versement en attente ou en échec) : attendez qu\'il arrive, ou écrivez à l\'aide Mara, puis supprimez votre compte.', {'name': p.blockedShop ?? ''}),
      _ => context.tr(p.blocked ?? ''),
    };

/// The account Worker's refusal of a deletion, in the reader's language
/// (by its code and the business it names; its French otherwise).
String accountRefusalText(BuildContext context, AccountRefused e) => switch (e.code) {
      'reauth' => context.tr('Par sécurité, reconnectez-vous avant de supprimer votre compte : la connexion doit dater de moins de 10 minutes.'),
      'not_stopped' => context.tr('Nous n\'avons pas pu arrêter l\'abonnement de « {name} » : rien n\'a été supprimé. Réessayez dans un moment ou écrivez à l\'aide.', {'name': e.name ?? ''}),
      'platform' => context.tr('Ce compte gère la plateforme Mara : il ne peut pas être supprimé, sinon plus personne ne pourrait la gérer. Pour essayer la suppression, utilisez un autre compte.'),
      'own_order' => context.tr('Une commande est en cours : attendez qu\'elle soit terminée, ou annulez-la, puis supprimez votre compte.'),
      'delivering' => context.tr('Une livraison est en cours : terminez-la, puis supprimez votre compte.'),
      'business_order' => context.tr('Une commande de « {name} » est en route ou déjà payée en ligne : livrez-la ou remboursez-la, puis supprimez votre compte.', {'name': e.name ?? ''}),
      'payout' => context.tr('Mara doit encore verser à « {name} » l\'argent d\'une commande payée par Wave (versement en attente ou en échec) : attendez qu\'il arrive, ou écrivez à l\'aide Mara, puis supprimez votre compte.', {'name': e.name ?? ''}),
      'list_changed' => context.tr('La liste de vos activités a changé : relisez-la avant de supprimer votre compte.'),
      'old_app' => context.tr('Mettez Mara à jour : la suppression d\'un compte qui tient une activité se confirme dans la dernière version de l\'application.'),
      _ => context.tr(e.message),
    };

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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/whatsapp_phone.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/shopper/shopper_repository.dart';
import '../../core/site/site.dart';
import '../../core/storefront/storefront_repository.dart' show whatsappShareUrl, whatsappUrl;
import '../../core/theme/mara_mark.dart';
import '../../l10n/strings.dart';
import '../account/alert_tone_tile.dart';
import '../storefront/shop_style.dart';
import '../storefront/whatsapp_verify_screen.dart';
import 'report_sheet.dart';

/// « Mon compte » for somebody who shops (113): the approved proposal, in
/// the street's own look. Who they are (photo, name, WhatsApp number, city);
/// what they bought (orders, bookings, the vitrines they follow, where they
/// are delivered); how they like to pay — cash, and Wave only when the
/// platform allows it (RULE M); the settings that already exist, linked;
/// the two ways to do more on Mara (courier, own business); a friend; help;
/// their data. A business's people keep their Compte; it links here for
/// « Mes achats ».
class ShopperProfileScreen extends StatefulWidget {
  const ShopperProfileScreen({super.key, required this.shopper, this.whatsApp});

  final ShopperRepository shopper;

  /// The WhatsApp proof (109); null: Supabase's, through the scope.
  final WhatsAppPhone? whatsApp;

  @override
  State<ShopperProfileScreen> createState() => _ShopperProfileScreenState();
}

class _ShopperProfileScreenState extends State<ShopperProfileScreen> {
  ShopperProfile? _profile;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.shopper.isConfigured) {
      setState(() => _error = context.tr('Votre compte a besoin d\'une connexion.'));
      return;
    }
    try {
      final p = await widget.shopper.profile();
      if (mounted) {
        setState(() {
          _profile = p;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.tr('Votre compte n\'a pas pu être chargé. Vérifiez le réseau.'));
      }
    }
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save({String? city, String? payment}) async {
    setState(() => _busy = true);
    try {
      await widget.shopper.setSettings(city: city, payment: payment);
      await _load();
    } catch (e) {
      _say(describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCity() async {
    final city = await showDialog<String>(
      context: context,
      builder: (_) => _CityDialog(current: _profile?.city),
    );
    if (city != null && mounted) await _save(city: city);
  }

  Future<void> _verify() async {
    final phone = widget.whatsApp ??
        SupabaseWhatsAppPhone(AppScope.read(context)?.auth.client);
    final proved = await Navigator.of(context).push(WhatsAppVerifyScreen.route(phone));
    if (proved != null && mounted) {
      _say(context.tr('Numéro WhatsApp vérifié.'));
      await _load();
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _say(context.tr('Impossible d\'ouvrir WhatsApp sur cet appareil.'));
    } catch (_) {
      if (mounted) _say(context.tr('Impossible d\'ouvrir WhatsApp sur cet appareil.'));
    }
  }

  /// « Parrainer un ami »: shoppers have no referral code (a code names a
  /// business, 084), so the street's own address travels, on WhatsApp.
  void _invite() => _open(whatsappShareUrl(context.tr(
      'Je fais mes achats sur Mara : les vitrines des boutiques, des fermes et des associations de chez nous. {url}',
      {'url': siteOrigin})));

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final text = await widget.shopper.exportData();
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(text),
            mimeType: 'application/json',
            name: 'mes-donnees-mara.json',
          ),
        ],
        fileNameOverrides: const ['mes-donnees-mara.json'],
      ));
    } catch (e) {
      if (mounted) _say(context.tr('Téléchargement impossible : {error}', {'error': describeError(e)}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final scope = AppScope.of(context);
    final gone = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(
        delete: () async {
          if (!scope.admin.canManageAccounts) {
            throw StateError(
                'La suppression en ligne n\'est pas encore ouverte : écrivez à Mara et votre compte sera supprimé.');
          }
          await scope.admin.deleteMyAccount();
        },
      ),
    );
    if (gone == true && mounted) {
      _say(context.tr('Votre compte est supprimé. Au revoir !'));
      await scope.session.signOut();
    }
  }

  Future<void> _signOut() async {
    final session = AppScope.of(context).session;
    await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return ShopPage(
      title: context.tr('Mon profil'),
      leading: IconButton(
        tooltip: context.tr('Les vitrines'),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go(Routes.directory),
      ),
      body: p == null
          ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : ShopNotice(
                  text: _error!,
                  action: OutlinedButton(onPressed: _load, child: Text(context.tr('Réessayer'))),
                ))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ShopWidth(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _sections(context, p),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _sections(BuildContext context, ShopperProfile p) {
    final scope = AppScope.of(context);
    final english = scope.localeController.effective.languageCode == 'en';
    final courier = p.courier != null;
    return [
      const SizedBox(height: 20),
      _Header(
        profile: p,
        picture: widget.shopper.picture,
        onName: () => context.push(Routes.myProfile),
        onVerify: p.verifiedPhone == null && p.verifyOn ? _verify : null,
        onCity: _busy ? null : _editCity,
      ),
      _Section(context.tr('Mes achats'), [
        _Row(
          key: const Key('shopper-orders'),
          icon: Icons.receipt_long_outlined,
          title: context.tr('Mes commandes'),
          subtitle: p.ordersOpen > 0
              ? context.tr('{n} en cours', {'n': p.ordersOpen})
              : context.tr('En cours et passées, avec « Recommander »'),
          onTap: () => context.push(Routes.myOrders),
        ),
        _Row(
          key: const Key('shopper-bookings'),
          icon: Icons.event_available_outlined,
          title: context.tr('Mes réservations'),
          subtitle: context.tr('Les services réservés sur rendez-vous'),
          onTap: () => context.push(Routes.bookings),
        ),
        _Row(
          key: const Key('shopper-favourites'),
          icon: Icons.favorite_border,
          title: context.tr('Mes vitrines favorites'),
          subtitle: p.follows == 0
              ? context.tr('Touchez ♥ sur une vitrine pour la suivre')
              : context.tr('{n} suivies', {'n': p.follows}),
          onTap: () async {
            await context.push(Routes.favourites);
            if (mounted) await _load();
          },
        ),
        _Row(
          key: const Key('shopper-addresses'),
          icon: Icons.home_work_outlined,
          title: context.tr('Mes adresses de livraison'),
          subtitle: p.addresses.isEmpty
              ? context.tr('Maison, travail : choisies à la commande')
              : p.addresses.map((a) => addressName(context, a)).join(' · '),
          onTap: () async {
            await context.push(Routes.addresses);
            if (mounted) await _load();
          },
        ),
      ]),
      _Section(context.tr('Paiement préféré'), [
        _PaymentChoice(
          profile: p,
          busy: _busy,
          onChanged: (v) => _save(payment: v),
        ),
      ]),
      _Section(context.tr('Réglages'), [
        _Row(
          key: const Key('shopper-notifications'),
          icon: Icons.notifications_outlined,
          title: context.tr('Notifications'),
          subtitle: context.tr('Vos commandes et les nouveautés de vos vitrines'),
          onTap: () => context.push(Routes.myNotifications),
        ),
        AlertToneTile(db: scope.db),
        _Row(
          key: const Key('shopper-language'),
          icon: Icons.translate,
          title: Strings.of(context).language,
          subtitle: english ? 'English' : 'Français',
          onTap: () => context.push(Routes.language),
        ),
      ]),
      _Section(context.tr('Avec Mara'), [
        _Row(
          key: const Key('shopper-courier'),
          icon: Icons.sports_motorsports_outlined,
          title: courier ? context.tr('Espace livreur') : context.tr('Devenir livreur'),
          subtitle: courier
              ? context.tr('Vos courses et vos gains')
              : context.tr('Livrez les commandes de votre quartier'),
          onTap: () => context.push(courier ? Routes.courier : Routes.becomeCourier),
        ),
        if (!p.member)
          _Row(
            key: const Key('shopper-create'),
            icon: Icons.add_business_outlined,
            title: context.tr('Créer mon activité'),
            subtitle: context.tr('Une boutique, une ferme ou une association'),
            onTap: () => context.push(Routes.createBusiness),
          ),
        _Row(
          key: const Key('shopper-invite'),
          icon: Icons.share_outlined,
          title: context.tr('Parrainer un ami'),
          subtitle: context.tr('Envoyez-lui Mara sur WhatsApp'),
          onTap: _invite,
        ),
      ]),
      _Section(context.tr('Aide'), [
        if (p.supportWhatsApp != null)
          _Row(
            key: const Key('shopper-support'),
            icon: Icons.support_agent_outlined,
            title: context.tr('Écrire à Mara sur WhatsApp'),
            onTap: () => _open(whatsappUrl(p.supportWhatsApp,
                text: context.tr('Bonjour Mara, j\'ai besoin d\'aide.'))!),
          ),
        _Row(
          key: const Key('shopper-report'),
          icon: Icons.flag_outlined,
          title: context.tr('Signaler un problème'),
          subtitle: context.tr('Une commande, une vitrine, l\'application'),
          onTap: () => showReportSheet(context, shopper: widget.shopper),
        ),
        _Row(
          icon: Icons.help_outline,
          title: context.tr('Questions fréquentes'),
          onTap: () => context.push(Routes.faq),
        ),
      ]),
      _Section(context.tr('Mes données'), [
        _Row(
          key: const Key('shopper-download'),
          icon: Icons.download_outlined,
          title: context.tr('Télécharger mes données'),
          subtitle: context.tr('Profil, commandes, adresses, favoris'),
          onTap: _busy ? null : _download,
        ),
        _Row(
          key: const Key('shopper-delete'),
          icon: Icons.delete_outline,
          title: context.tr('Supprimer mon compte'),
          danger: true,
          onTap: _delete,
        ),
        _Row(
          icon: Icons.privacy_tip_outlined,
          title: context.tr('Politique de confidentialité'),
          onTap: () => context.push(Routes.privacy),
        ),
        _Row(
          icon: Icons.description_outlined,
          title: context.tr('Conditions d\'utilisation'),
          onTap: () => context.push(Routes.terms),
        ),
      ]),
      const SizedBox(height: 28),
      OutlinedButton.icon(
        key: const Key('shopper-sign-out'),
        onPressed: _signOut,
        icon: const Icon(Icons.logout),
        label: Text(context.tr('Se déconnecter')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: ShopStyle.ink,
        ),
      ),
      const ShopFooter(),
    ];
  }
}

/// « Maison », « Travail », or the other place's own name.
String addressName(BuildContext context, SavedAddress a) => switch (a.kind) {
      'home' => context.tr('Maison'),
      'work' => context.tr('Travail'),
      _ => a.label ?? context.tr('Autre'),
    };

/// Who is holding the phone: the photo (Google's, or the initial), the
/// name and the way to change it, the WhatsApp number — proved, or the
/// way to prove it — and the city.
class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.picture,
    required this.onName,
    required this.onVerify,
    required this.onCity,
  });

  final ShopperProfile profile;
  final String? picture;
  final VoidCallback onName;
  final VoidCallback? onVerify;
  final VoidCallback? onCity;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p.name ?? context.tr('Mon profil');
    final initial = name.characters.isEmpty ? '?' : name.characters.first.toUpperCase();
    final proved = p.verifiedPhone;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
      decoration: BoxDecoration(
        color: ShopStyle.stone,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const Key('shopper-name'),
            onTap: onName,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: maraDeep,
                  foregroundImage: picture == null ? null : NetworkImage(picture!),
                  onForegroundImageError: picture == null ? null : (_, _) {},
                  child: Text(initial,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w700, color: maraCaramel)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w700, color: ShopStyle.ink)),
                      const SizedBox(height: 2),
                      Text(context.tr('Mes informations'),
                          style: const TextStyle(
                              fontSize: 14,
                              color: ShopStyle.mist,
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: ShopStyle.mist),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // The number: proved on WhatsApp, or the way to prove it.
          Row(
            key: const Key('shopper-phone'),
            children: [
              Icon(proved != null ? Icons.verified : Icons.chat_outlined,
                  size: 20, color: proved != null ? maraGreen : ShopStyle.mist),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  proved != null
                      ? context.tr('{phone} · WhatsApp vérifié', {'phone': proved})
                      : (p.phone ?? context.tr('Pas encore de numéro')),
                  style: const TextStyle(fontSize: 15, color: ShopStyle.ink),
                ),
              ),
              if (onVerify != null)
                TextButton(
                  key: const Key('shopper-verify'),
                  onPressed: onVerify,
                  child: Text(context.tr('Vérifier')),
                ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            key: const Key('shopper-city'),
            onTap: onCity,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.location_city_outlined, size: 20, color: ShopStyle.mist),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.city ?? context.tr('Ajouter ma ville'),
                      style: TextStyle(
                        fontSize: 15,
                        color: p.city == null ? ShopStyle.mist : ShopStyle.ink,
                        decoration: p.city == null ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 18, color: ShopStyle.mist),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A heading and its rows, on a stone card with hairlines between.
class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: ShopSectionLabel(title),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(color: ShopStyle.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: ShopStyle.paper,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Theme.of(context).colorScheme.error : ShopStyle.ink;
    return ListTile(
      minTileHeight: 60,
      leading: Icon(icon, color: color),
      title: Text(title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, color: ShopStyle.mist)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: ShopStyle.mist),
      onTap: onTap,
    );
  }
}

/// Cash; Wave beside it only while the platform allows it (RULE M) — not
/// greyed, not drawn.
class _PaymentChoice extends StatelessWidget {
  const _PaymentChoice({required this.profile, required this.busy, required this.onChanged});

  final ShopperProfile profile;
  final bool busy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!profile.waveAllowed) {
      return ListTile(
        key: const Key('shopper-payment-cash'),
        minTileHeight: 60,
        leading: const Icon(Icons.payments_outlined, color: ShopStyle.ink),
        title: Text(context.tr('Espèces'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ShopStyle.ink)),
        subtitle: Text(context.tr('Vous payez au retrait ou à la livraison.'),
            style: const TextStyle(fontSize: 13.5, color: ShopStyle.mist)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            key: const Key('shopper-payment'),
            segments: [
              ButtonSegment(
                value: 'cash',
                label: Text(context.tr('Espèces')),
                icon: const Icon(Icons.payments_outlined),
              ),
              ButtonSegment(
                value: 'wave',
                label: Text(context.tr('Wave')),
                icon: const Icon(Icons.phone_iphone_outlined),
              ),
            ],
            selected: {profile.payment},
            onSelectionChanged: busy ? null : (s) => onChanged(s.first),
          ),
          const SizedBox(height: 8),
          Text(context.tr('Choisi d\'avance à la commande, quand la vitrine le propose.'),
              style: const TextStyle(fontSize: 13, color: ShopStyle.mist)),
        ],
      ),
    );
  }
}

/// The city, typed or picked.
class _CityDialog extends StatefulWidget {
  const _CityDialog({this.current});

  final String? current;

  @override
  State<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends State<_CityDialog> {
  late final _text = TextEditingController(text: widget.current ?? '');

  static const _cities = ['Ouagadougou', 'Bobo-Dioulasso', 'Koudougou', 'Abidjan'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Ma ville')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('city-field'),
              controller: _text,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Ouagadougou'),
              onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in _cities)
                  ActionChip(label: Text(c), onPressed: () => Navigator.of(context).pop(c)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          key: const Key('city-save'),
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: Text(context.tr('Enregistrer')),
        ),
      ],
    );
  }
}

/// « Supprimer mon compte »: said plainly, confirmed by typing a word.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.delete});

  final Future<void> Function() delete;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The word to type, in the reader's language.
  String _word(BuildContext context) => context.tr('SUPPRIMER');

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.delete();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is StateError ? context.tr(e.message) : describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final word = _word(context);
    final ready = _typed.text.trim().toUpperCase() == word && !_busy;
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: error),
      title: Text(context.tr('Supprimer mon compte ?')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Votre compte, vos commandes, vos adresses et vos favoris seront effacés pour toujours. Les boutiques ne verront plus vos commandes.')),
            const SizedBox(height: 14),
            Text(context.tr('Pour confirmer, tapez {word} :', {'word': word}),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              key: const Key('delete-word'),
              controller: _typed,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: word),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('Garder mon compte')),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: error),
          onPressed: ready ? _go : null,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('Supprimer')),
        ),
      ],
    );
  }
}

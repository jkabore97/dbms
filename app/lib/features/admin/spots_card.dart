import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/access/store_rules.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../pay/wave_buttons.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// "Mettre en avant" (071): the shop's spots on the street, and the door to
/// buy one.
///
/// The audit: À la une existed, but only the platform could put an article
/// there, by hand, and an owner had no way to ask, no price, no way to pay
/// and no figure to judge it by. The card lists the shop's spots with what
/// each earned (seen, opened, added, ordered) and opens the sheet that sells
/// one.
class SpotsCard extends StatefulWidget {
  const SpotsCard({
    super.key,
    required this.orgId,
    required this.admin,
    required this.retail,
    this.isPro = false,
    this.vitrineOnly = false,
  });

  final String orgId;
  final AdminRepository admin;
  final RetailRepository? retail;

  /// Pro includes one 7-day article spot a month; the sheet says so.
  final bool isPro;

  /// An association (no stock): only the whole-vitrine spot is offered.
  final bool vitrineOnly;

  @override
  State<SpotsCard> createState() => _SpotsCardState();
}

class _SpotsCardState extends State<SpotsCard> {
  List<Promotion> _spots = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final spots = await widget.admin.myPromotions(widget.orgId);
      if (!mounted) return;
      setState(() {
        _spots = spots;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  bool get _isPro =>
      widget.isPro ||
      (AppScope.maybeOf(context)?.session.orgById(widget.orgId)?.isPro ??
          false);

  Future<void> _buy() async {
    final changed = await SpotSheet.open(context,
        orgId: widget.orgId,
        admin: widget.admin,
        retail: widget.retail,
        isPro: _isPro,
        vitrineOnly: widget.vitrineOnly);
    if (changed == true) await _load();
  }

  Future<void> _claim(Promotion spot) async {
    final changed = await SpotSheet.pay(context,
        spot: spot, admin: widget.admin);
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return KajCard(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('Mettre en avant'),
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.vitrineOnly
                  ? context.tr('Votre vitrine en haut de la liste des vitrines, pour 7 ou 30 jours.')
                  : context.tr('Un article en tête de « À la une » sur la page d\'accueil, ou toute la vitrine en haut de la liste, pour 7 ou 30 jours.'),
              style: muted,
            ),
            if (_loaded && _spots.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final s in _spots.take(5))
                _SpotRow(spot: s, onPay: () => _claim(s)),
            ],
            // The iPhone app sells no spot (125): the card is not drawn
            // there (OrgSettingsScreen), and never offers one if it were.
            if (sellsDigitalInApp) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _buy,
                icon: const Icon(Icons.add),
                label: Text(context.tr('Mettre en avant')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpotRow extends StatelessWidget {
  const _SpotRow({required this.spot, required this.onPay});

  final Promotion spot;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat('d MMM', intlLocale());
    final state = spot.stateLabel();
    final running = state == 'En cours' || state == 'Terminée';
    final dates = spot.startsAt == null
        ? context.tr('{days} jours', {'days': spot.days})
        : context.tr('du {from} au {to}', {'from': date.format(spot.startsAt!), 'to': date.format(spot.endsAt!)});
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(spot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                _StateChip(label: state),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [dates, if (spot.free) context.tr('offerte par Mara Pro')].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (running) ...[
              const SizedBox(height: 6),
              Text(
                context.tr('{seen} vues · {opened} ouvertures · {added} au panier · {ordered} commandes', {'seen': spot.seen, 'opened': spot.opened, 'added': spot.added, 'ordered': spot.ordered}),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            if (spot.status == 'requested' && sellsDigitalInApp)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(context.tr('Payer et confirmer')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (label) {
      'En cours' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'Refusée' => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(context.tr(label),
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// The sheet that sells a spot: what, how long, the price, where to pay,
/// and "J'ai payé". Two steps in one sheet — ask, then pay — so a shop that
/// asks and pays later finds the second step on the card.
class SpotSheet {
  static Future<bool?> open(
    BuildContext context, {
    required String orgId,
    required AdminRepository admin,
    required RetailRepository? retail,
    bool isPro = false,
    String? productId,
    bool vitrineOnly = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SpotSheetBody(
        orgId: orgId,
        admin: admin,
        retail: retail,
        isPro: isPro,
        productId: productId,
        vitrineOnly: vitrineOnly,
      ),
    );
  }

  /// Straight to the payment step of a spot already asked for.
  static Future<bool?> pay(
    BuildContext context, {
    required Promotion spot,
    required AdminRepository admin,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _SpotSheetBody(
        orgId: '',
        admin: admin,
        retail: null,
        asked: spot,
      ),
    );
  }
}

class _SpotSheetBody extends StatefulWidget {
  const _SpotSheetBody({
    required this.orgId,
    required this.admin,
    required this.retail,
    this.isPro = false,
    this.productId,
    this.asked,
    this.vitrineOnly = false,
  });

  final String orgId;
  final AdminRepository admin;
  final RetailRepository? retail;
  final bool isPro;
  final String? productId;

  /// No article choice: the whole vitrine only (an association).
  final bool vitrineOnly;

  /// A spot already asked for: the sheet opens on its payment.
  final Promotion? asked;

  @override
  State<_SpotSheetBody> createState() => _SpotSheetBodyState();
}

class _SpotSheetBodyState extends State<_SpotSheetBody> {
  SpotTerms _terms = const SpotTerms();
  List<Product> _articles = const [];

  /// The whole shop rather than one article.
  late bool _shop = widget.vitrineOnly;
  String? _productId;
  int _days = 7;
  bool _busy = false;
  String? _error;
  final _note = TextEditingController();

  /// Set once asked: the sheet moves on to paying for it.
  Promotion? _asked;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _productId = widget.productId;
    _asked = widget.asked;
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final terms = await widget.admin.spotTerms();
      final products = widget.retail == null
          ? const <Product>[]
          : await widget.retail!.products(widget.orgId);
      if (!mounted) return;
      setState(() {
        _terms = terms;
        _articles = products
            .where((p) =>
                p.isPublished &&
                !p.isIngredient &&
                p.salePrice > 0 &&
                p.quantity > 0)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (_productId == null && _articles.isNotEmpty) {
          _productId = _articles.first.id;
        }
      });
    } catch (_) {}
  }

  String _money(double v) => moneyFormat(_terms.currency).format(v);

  bool get _proFree => widget.isPro && !_shop && _days == 7;

  Future<void> _ask() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.admin
          .requestPromotion(widget.orgId,
              productId: _shop ? null : _productId, days: _days);
      final mine = await widget.admin.myPromotions(widget.orgId);
      if (!mounted) return;
      final spot = mine.where((p) => p.id == id).firstOrNull;
      setState(() {
        _busy = false;
        _asked = spot;
        // Pro's included spot is approved on the spot: nothing to pay.
        _done = spot == null || spot.status == 'approved';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _paid() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.claimPromotionPaid(_asked!.id, note: _note.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('Mettre en avant'), style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              if (_done)
                ..._doneView(theme)
              else if (_asked != null)
                ..._payView(theme, muted)
              else
                ..._askView(theme, muted),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _askView(ThemeData theme, TextStyle? muted) {
    final shop = _shop;
    final price = _terms.price(shop: shop, days: _days);
    return [
      if (!widget.vitrineOnly) ...[
      Text(context.tr('Quoi ?'), style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
              value: false,
              icon: const Icon(Icons.sell_outlined),
              label: Text(context.tr('Un article'))),
          ButtonSegment(
              value: true,
              icon: const Icon(Icons.storefront_outlined),
              label: Text(context.tr('La vitrine'))),
        ],
        selected: {shop},
        onSelectionChanged: _busy
            ? null
            : (v) => setState(() => _shop = v.first),
      ),
      ],
      const SizedBox(height: 10),
      if (!shop && _articles.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.tr('Aucun article prêt : mettez sur la vitrine un article avec un prix et du stock.'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      if (!shop && _articles.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          initialValue: _articles.any((a) => a.id == _productId)
              ? _productId
              : _articles.first.id,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: context.tr('Article'), border: const OutlineInputBorder()),
          items: [
            for (final a in _articles)
              DropdownMenuItem(
                value: a.id,
                child: Text('${a.name} · ${_money(a.salePrice)}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _productId = v),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        shop
            ? context.tr('La vitrine apparaît en tête de la liste des vitrines, marquée « Sponsorisé ».')
            : context.tr('L\'article apparaît en tête de « À la une » sur la page d\'accueil, marqué « Sponsorisé ». Il lui faut une photo, un prix et du stock.'),
        style: muted,
      ),
      const SizedBox(height: 14),
      Text(context.tr('Combien de temps ?'), style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 7, label: Text(context.tr('7 jours'))),
          ButtonSegment(value: 30, label: Text(context.tr('30 jours'))),
        ],
        selected: {_days},
        onSelectionChanged:
            _busy ? null : (v) => setState(() => _days = v.first),
      ),
      const SizedBox(height: 16),
      Text(
        _proFree
            ? context.tr('Offert : Mara Pro inclut une mise en avant de 7 jours par mois.')
            : context.tr('Prix : {price}', {'price': _money(price)}),
        style: theme.textTheme.titleMedium,
      ),
      Text(
        context.tr('Au plus {maxLive} articles à la une en même temps : si la place est prise, votre période commence dès qu\'une se libère.', {'maxLive': _terms.maxLive}),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: _busy || (!shop && _productId == null) ? null : _ask,
          child: Text(_proFree ? context.tr('Mettre en avant') : context.tr('Continuer vers le paiement'),
              style: const TextStyle(fontSize: 16)),
        ),
      ),
    ];
  }

  List<Widget> _payView(ThemeData theme, TextStyle? muted) {
    final spot = _asked!;
    return [
      Text(context.tr('{label} · {days} jours', {'label': spot.label, 'days': spot.days}),
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(context.tr('À payer : {amount}', {'amount': moneyFormat(spot.currency).format(spot.price)}),
          style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      // Paid and programmed at once, by Wave or card (076), when the
      // platform has opened it.
      WaveButtons(
        kind: 'spot',
        ref: spot.id,
        below: Text(context.tr('Ou à la main :'), style: muted),
      ),
      const SizedBox(height: 8),
      if (_terms.hasWave)
        KajCard(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: const Icon(Icons.phone_android_outlined),
            title: Text(_terms.wave),
            subtitle: Text(_terms.waveName.isEmpty
                ? context.tr('Payez par Wave ou Orange Money à ce numéro')
                : context.tr('Wave · {waveName}', {'waveName': _terms.waveName})),
            trailing: IconButton(
              tooltip: context.tr('Copier le numéro'),
              icon: const Icon(Icons.copy_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _terms.wave));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(content: Text(context.tr('Numéro copié'))));
              },
            ),
          ),
        )
      else
        Text(
            context.tr('Pour payer, contactez Mara : le numéro de paiement vous sera donné directement.'),
            style: muted),
      const SizedBox(height: 12),
      Text(
          context.tr('Une fois le paiement envoyé, dites-le ici : Mara le vérifie et la mise en avant commence.'),
          style: muted),
      const SizedBox(height: 10),
      TextField(
        controller: _note,
        enabled: !_busy,
        decoration: InputDecoration(
          labelText: context.tr('Précision (facultatif)'),
          hintText: context.tr('Nom Wave, référence…'),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: _busy ? null : _paid,
          icon: const Icon(Icons.done_all),
          label: Text(context.tr('J\'ai payé'), style: const TextStyle(fontSize: 17)),
        ),
      ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(true),
        child: Text(context.tr('Payer plus tard')),
      ),
    ];
  }

  List<Widget> _doneView(ThemeData theme) {
    final free = _asked?.status == 'approved';
    return [
      KajCard(
        elevation: 0,
        color: theme.colorScheme.primaryContainer,
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(free ? context.tr('C\'est en ligne.') : context.tr('Merci, c\'est noté.')),
          subtitle: Text(free
              ? context.tr('Votre article est à la une. Ses vues et commandes s\'affichent dans « Mettre en avant ».')
              : context.tr('Mara vérifie le paiement et lance la mise en avant. Vous serez prévenu dans la cloche.')),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(context.tr('Fermer')),
      ),
    ];
  }
}

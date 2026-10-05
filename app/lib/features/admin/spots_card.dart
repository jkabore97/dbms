import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/format/money.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';

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
  });

  final String orgId;
  final AdminRepository admin;
  final RetailRepository? retail;

  /// Pro includes one 7-day article spot a month; the sheet says so.
  final bool isPro;

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
        isPro: _isPro);
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
    return Card(
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
                  child: Text('Mettre en avant',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Un article en tête de « À la une » sur la page d\'accueil, ou '
              'toute la boutique en haut de la liste, pour 7 ou 30 jours.',
              style: muted,
            ),
            if (_loaded && _spots.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final s in _spots.take(5))
                _SpotRow(spot: s, onPay: () => _claim(s)),
            ],
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _buy,
              icon: const Icon(Icons.add),
              label: const Text('Mettre en avant'),
            ),
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
    final date = DateFormat('d MMM', 'fr_FR');
    final state = spot.stateLabel();
    final running = state == 'En cours' || state == 'Terminée';
    final dates = spot.startsAt == null
        ? '${spot.days} jours'
        : 'du ${date.format(spot.startsAt!)} au ${date.format(spot.endsAt!)}';
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
              [dates, if (spot.free) 'offerte par Kaj Pro'].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (running) ...[
              const SizedBox(height: 6),
              Text(
                '${spot.seen} vues · ${spot.opened} ouvertures · '
                '${spot.added} au panier · ${spot.ordered} commandes',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
            if (spot.status == 'requested')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onPay,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Payer et confirmer'),
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
      child: Text(label,
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
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SpotSheetBody(
        orgId: orgId,
        admin: admin,
        retail: retail,
        isPro: isPro,
        productId: productId,
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
  });

  final String orgId;
  final AdminRepository admin;
  final RetailRepository? retail;
  final bool isPro;
  final String? productId;

  /// A spot already asked for: the sheet opens on its payment.
  final Promotion? asked;

  @override
  State<_SpotSheetBody> createState() => _SpotSheetBodyState();
}

class _SpotSheetBodyState extends State<_SpotSheetBody> {
  SpotTerms _terms = const SpotTerms();
  List<Product> _articles = const [];

  /// The whole shop rather than one article.
  bool _shop = false;
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
              Text('Mettre en avant', style: theme.textTheme.headlineSmall),
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
      Text('Quoi ?', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
              value: false,
              icon: Icon(Icons.sell_outlined),
              label: Text('Un article')),
          ButtonSegment(
              value: true,
              icon: Icon(Icons.storefront_outlined),
              label: Text('La boutique')),
        ],
        selected: {shop},
        onSelectionChanged: _busy
            ? null
            : (v) => setState(() => _shop = v.first),
      ),
      const SizedBox(height: 10),
      if (!shop && _articles.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            "Aucun article prêt : mettez sur la vitrine un article avec un "
            'prix et du stock.',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      if (!shop && _articles.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          initialValue: _articles.any((a) => a.id == _productId)
              ? _productId
              : _articles.first.id,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Article', border: OutlineInputBorder()),
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
            ? 'La boutique apparaît en tête de la liste des boutiques, '
                'marquée « Sponsorisé ».'
            : "L'article apparaît en tête de « À la une » sur la page "
                "d'accueil, marqué « Sponsorisé ». Il lui faut une photo, "
                'un prix et du stock.',
        style: muted,
      ),
      const SizedBox(height: 14),
      Text('Combien de temps ?', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('7 jours')),
          ButtonSegment(value: 30, label: Text('30 jours')),
        ],
        selected: {_days},
        onSelectionChanged:
            _busy ? null : (v) => setState(() => _days = v.first),
      ),
      const SizedBox(height: 16),
      Text(
        _proFree
            ? 'Offert : Kaj Pro inclut une mise en avant de 7 jours par mois.'
            : 'Prix : ${_money(price)}',
        style: theme.textTheme.titleMedium,
      ),
      Text(
        'Au plus ${_terms.maxLive} articles à la une en même temps : si la '
        'place est prise, votre période commence dès qu\'une se libère.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: _busy || (!shop && _productId == null) ? null : _ask,
          child: Text(_proFree ? 'Mettre en avant' : 'Continuer vers le paiement',
              style: const TextStyle(fontSize: 16)),
        ),
      ),
    ];
  }

  List<Widget> _payView(ThemeData theme, TextStyle? muted) {
    final spot = _asked!;
    return [
      Text('${spot.label} · ${spot.days} jours',
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('À payer : ${moneyFormat(spot.currency).format(spot.price)}',
          style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      if (_terms.hasWave)
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: const Icon(Icons.phone_android_outlined),
            title: Text(_terms.wave),
            subtitle: Text(_terms.waveName.isEmpty
                ? 'Payez par Wave ou Orange Money à ce numéro'
                : 'Wave · ${_terms.waveName}'),
            trailing: IconButton(
              tooltip: 'Copier le numéro',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _terms.wave));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Numéro copié')));
              },
            ),
          ),
        )
      else
        Text(
            'Pour payer, contactez Kaj : le numéro de paiement vous sera '
            'donné directement.',
            style: muted),
      const SizedBox(height: 12),
      Text(
          "Une fois le paiement envoyé, dites-le ici : Kaj le vérifie et la "
          'mise en avant commence.',
          style: muted),
      const SizedBox(height: 10),
      TextField(
        controller: _note,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Précision (facultatif)',
          hintText: 'Nom Wave, référence…',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: _busy ? null : _paid,
          icon: const Icon(Icons.done_all),
          label: const Text("J'ai payé", style: TextStyle(fontSize: 17)),
        ),
      ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(true),
        child: const Text('Payer plus tard'),
      ),
    ];
  }

  List<Widget> _doneView(ThemeData theme) {
    final free = _asked?.status == 'approved';
    return [
      Card(
        elevation: 0,
        color: theme.colorScheme.primaryContainer,
        child: ListTile(
          leading: const Icon(Icons.check_circle_outline),
          title: Text(free ? 'C\'est en ligne.' : 'Merci, c\'est noté.'),
          subtitle: Text(free
              ? 'Votre article est à la une. Ses vues et commandes '
                  's\'affichent dans « Mettre en avant ».'
              : 'Kaj vérifie le paiement et lance la mise en avant. Vous '
                  'serez prévenu dans la cloche.'),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Fermer'),
      ),
    ];
  }
}

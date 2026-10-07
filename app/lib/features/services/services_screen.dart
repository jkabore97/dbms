import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/nav/app_scope.dart';
import '../capture/capture_action.dart';
import '../retail/photo_quota.dart';
import '../retail/product_photo.dart';

/// « Mes services » (098): what a business does rather than sells — a
/// haircut, a lesson, a room for the evening, a repair — with its price, on
/// the vitrine. One screen for the shop, the farm and the association.
///
/// A service is a product row with `is_service` set, so the basket, the
/// order, the till and the photos work as they do for goods; what it does
/// not have is stock. Nothing here counts, and nothing runs out.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final CaptureRepository? capture;

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<Product> _services = const [];
  Map<String, String> _photos = const {};
  bool _loading = true;
  String? _error;

  /// A database before 098: no service can be saved as one (it would land
  /// as an article), so the page says so and adds nothing.
  bool _missing = false;

  bool get _canWrite => !widget.org.isObserverOnly;

  bool get _association =>
      widget.org.profile == 'association' || widget.org.profile == 'church';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await widget.retail.products(widget.org.id);
      final photos = await widget.retail.photoKeys(widget.org.id);
      if (!mounted) return;
      setState(() {
        _services = [
          for (final p in all)
            if (p.isService) p,
        ];
        _missing = widget.retail.servicesMissing;
        _photos = photos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _open([Product? service]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ServiceSheet(
        org: widget.org,
        retail: widget.retail,
        capture: widget.capture,
        service: service,
        photoKey: service == null ? null : _photos[service.id],
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = moneyFormat(widget.org.currency);
    final slug = widget.org.slug;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Mes services')),
        actions: [
          if (slug != null && slug.isNotEmpty)
            TextButton.icon(
              key: const Key('services-see-vitrine'),
              onPressed: () => context.push(Routes.storefront(slug)),
              icon: const Icon(Icons.storefront_outlined),
              label: Text(context.tr('Ma vitrine')),
            ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton.extended(
              key: const Key('services-add'),
              onPressed: _missing || _loading ? null : () => _open(),
              backgroundColor: _missing
                  ? theme.colorScheme.surfaceContainerHighest
                  : null,
              foregroundColor: _missing
                  ? theme.colorScheme.onSurfaceVariant
                  : null,
              icon: const Icon(Icons.add),
              label: Text(context.tr('Ajouter un service')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _Intro(
              association: _association,
              onSettings: widget.org.isAdmin
                  ? () => context.push(Routes.orgSettings(widget.org.id))
                  : null,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (_missing)
              KajCard(
                key: const Key('services-missing'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.update, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr(
                            'Les services ne sont pas encore disponibles : la base de données n\'est pas à jour (migration 098). Demandez à l\'administrateur de Mara de l\'appliquer.',
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_services.isEmpty)
              KajCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _association
                        ? context.tr(
                            'Aucun service pour le moment. « Ajouter un service » : une adhésion, un cours, la salle pour une soirée…',
                          )
                        : context.tr(
                            'Aucun service pour le moment. « Ajouter un service » : une coupe, une réparation, une livraison, une heure de cours…',
                          ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              for (final p in _services)
                KajCard(
                  key: ValueKey('service-${p.id}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    minVerticalPadding: 12,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    onTap: _canWrite ? () => _open(p) : null,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: ProductPhoto(
                          name: p.name,
                          photoKey: _photos[p.id],
                          capture: widget.capture,
                        ),
                      ),
                    ),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      servicePriceLine(p, money, context.trLanguage),
                    ),
                    trailing: Icon(
                      p.isPublished
                          ? Icons.storefront
                          : Icons.visibility_off_outlined,
                      color: p.isPublished
                          ? maraGreen
                          : theme.colorScheme.onSurfaceVariant,
                      semanticLabel: p.isPublished
                          ? context.tr('Sur la vitrine')
                          : context.tr('Pas sur la vitrine'),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// « 5 000 F », « à partir de 5 000 F / heure » — the way the vitrine
/// reads it.
String servicePriceLine(Product p, NumberFormat money, [String lang = 'fr']) {
  final amount = p.priceFrom
      ? translate(lang, 'à partir de {price}', {
          'price': money.format(p.salePrice),
        })
      : money.format(p.salePrice);
  return p.unit == null ? amount : '$amount / ${p.unit}';
}

/// The page's first words, on the graphite ground: what a service is here,
/// and the way to the vitrine's own settings.
class _Intro extends StatelessWidget {
  const _Intro({required this.association, this.onSettings});

  final bool association;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: maraDeep,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: maraCaramel.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  color: maraCaramel,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  association
                      ? context.tr(
                          'Vos services, sur votre vitrine. On réserve en ligne, on règle sur place.',
                        )
                      : context.tr(
                          'Ce que vous faites, avec son prix, sur votre vitrine. Les clients réservent, vous fixez le rendez-vous.',
                        ),
                  style: const TextStyle(
                    color: maraPaper,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (onSettings != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('services-settings'),
                style: TextButton.styleFrom(foregroundColor: maraCaramel),
                onPressed: onSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(context.tr('Ouvrir ou régler la vitrine')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One service: new or edited, saved in one go.
class ServiceSheet extends StatefulWidget {
  const ServiceSheet({
    super.key,
    required this.org,
    required this.retail,
    this.capture,
    this.service,
    this.photoKey,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final CaptureRepository? capture;
  final Product? service;

  /// The service's current photo, shown until another is picked.
  final String? photoKey;

  @override
  State<ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<ServiceSheet> {
  /// What a service is counted by, offered as one tap; anything else typed.
  static const units = ['heure', 'séance', 'personne', 'jour', 'mois'];

  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _price = TextEditingController(
    text: widget.service == null || widget.service!.salePrice == 0
        ? ''
        : _plain(widget.service!.salePrice),
  );
  late final _unit = TextEditingController(text: widget.service?.unit ?? '');
  late final _description = TextEditingController(
    text: widget.service?.description ?? '',
  );
  late bool _from = widget.service?.priceFrom ?? false;
  late bool _published = widget.service?.isPublished ?? true;

  Uint8List? _photo;
  String? _photoType;
  bool _busy = false;
  String? _error;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _unit.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // Every place taken on Basic (100): one more first, or nothing.
    if (!await photoAllowed(context, widget.org, hasPhoto: widget.photoKey != null) ||
        !mounted) {
      return;
    }
    final picked = await CaptureAction.pick(context);
    if (picked == null || !mounted) return;
    setState(() {
      _photo = picked.bytes;
      _photoType = picked.contentType;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = _num(_price);
    if (name.isEmpty || price == null || price <= 0) {
      setState(
        () => _error = context.tr('Un nom et un prix, s\'il vous plaît.'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id =
          widget.service?.id ??
          // The server refuses a name an article holds, retired or not
          // (098): a service never turns an article into one.
          await widget.retail.ensureProduct(
            orgId: widget.org.id,
            name: name,
            salePrice: price,
            isService: true,
          );
      await widget.retail.updateProduct(
        id,
        name: name,
        salePrice: price,
        unit: _unit.text,
        isPublished: _published,
        description: _description.text,
        isService: true,
        priceFrom: _from,
      );
      final capture = widget.capture;
      if (_photo != null && capture != null) {
        final doc = await capture.capture(
          orgId: widget.org.id,
          bytes: _photo!,
          contentType: _photoType ?? 'image/jpeg',
          kind: 'product_photo',
          caption: name,
        );
        if (doc != null) {
          await capture.file(documentId: doc, productId: id);
          if (mounted) await AppScope.read(context)?.session.reloadFeatures(widget.org.id);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Off the vitrine and the till for good; every order and sale that
  /// named it keeps it.
  Future<void> _remove() async {
    final service = widget.service;
    if (service == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('service-remove-confirm'),
        title: Text(dialog.tr('Retirer ce service ?')),
        content: Text(
          dialog.tr(
            '« {name} » quitte la vitrine et la caisse. Les commandes et les ventes passées le gardent.',
            {'name': service.name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(dialog.tr('Retour')),
          ),
          FilledButton(
            key: const Key('service-remove-yes'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(dialog.tr('Retirer')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.retail.archiveProduct(service.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeError(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.service != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              editing
                  ? context.tr('Modifier le service')
                  : context.tr('Nouveau service'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                InkWell(
                  key: const Key('service-photo'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.capture == null || _busy ? null : _pickPhoto,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 76,
                      height: 76,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: _photo != null
                          ? Image.memory(_photo!, fit: BoxFit.cover)
                          : widget.photoKey != null
                          ? ProductPhoto(
                              key: const Key('service-photo-current'),
                              name: widget.service?.name ?? '',
                              photoKey: widget.photoKey,
                              capture: widget.capture,
                            )
                          : const Icon(Icons.add_a_photo_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    key: const Key('service-name'),
                    controller: _name,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: context.tr('Quel service ?'),
                      hintText: context.tr('Coupe homme, cours de maths…'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            PhotoCounter(org: widget.org, hasPhoto: widget.photoKey != null),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('service-price'),
                    controller: _price,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.tr('Prix ({currency})', {
                        'currency': widget.org.currency,
                      }),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('service-unit'),
                    controller: _unit,
                    enabled: !_busy,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: context.tr('Par (facultatif)'),
                      hintText: context.tr('heure, séance…'),
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final u in units)
                  ChoiceChip(
                    label: Text(u),
                    selected: _unit.text.trim() == u,
                    onSelected: _busy
                        ? null
                        : (on) => setState(() => _unit.text = on ? u : ''),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('service-from'),
              contentPadding: EdgeInsets.zero,
              value: _from,
              onChanged: _busy ? null : (v) => setState(() => _from = v),
              title: Text(context.tr('« À partir de »')),
              subtitle: Text(
                context.tr(
                  'Le prix de départ : le client sait que cela peut coûter plus.',
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('service-description'),
              controller: _description,
              enabled: !_busy,
              maxLength: 300,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: context.tr('En deux mots (facultatif)'),
                hintText: context.tr('Durée, ce qui est compris, où.'),
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              key: const Key('service-published'),
              contentPadding: EdgeInsets.zero,
              value: _published,
              onChanged: _busy ? null : (v) => setState(() => _published = v),
              title: Text(context.tr('Sur la vitrine')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('service-save'),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        editing
                            ? context.tr('Enregistrer')
                            : context.tr('Ajouter le service'),
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ),
            if (editing) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('service-remove'),
                onPressed: _busy ? null : _remove,
                child: Text(context.tr('Retirer ce service')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

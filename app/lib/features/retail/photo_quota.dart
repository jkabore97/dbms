import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/store_rules.dart';
import '../../core/auth/models.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../cauris/cauri_icon.dart';

/// The photographed articles a Basic business keeps (100), as the session
/// last read them; null when there is no limit to say, or no reading yet.
PhotoQuota? photoQuotaOf(BuildContext context, OrgSummary org) {
  final q = AppScope.maybeOf(context)?.session.featuresFor(org.id)?.photos;
  return q != null && q.limited ? q : null;
}

/// Whether a photo may be hung on this article now: always for one that
/// already has a photo, or with room left; otherwise the slot sheet opens,
/// and the answer is whether a slot was bought there.
///
/// Asked before the picture is taken, with a fresh count (another phone
/// may have taken the last place): the picture is sent first and hung on
/// the article after, so a refusal at the hanging would leave it in
/// Documents with no article — which the server then says.
Future<bool> photoAllowed(BuildContext context, OrgSummary org,
    {required bool hasPhoto}) async {
  if (hasPhoto) return true;
  final session = AppScope.maybeOf(context)?.session;
  if (session != null && photoQuotaOf(context, org) != null) {
    try {
      await session.reloadFeatures(org.id);
    } catch (_) {
      // No signal: the last count stands; the server still holds the door.
    }
    if (!context.mounted) return false;
  }
  final q = photoQuotaOf(context, org);
  if (q == null || !q.full) return true;
  final bought = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PhotoSlotSheet(org: org, quota: q),
  );
  return bought == true;
}

/// « 7 / 10 photos » beside a photo button; full, the way to one more.
class PhotoCounter extends StatelessWidget {
  const PhotoCounter({super.key, required this.org, this.hasPhoto = false, this.quota});

  final OrgSummary org;

  /// The session's unless a test gives its own.
  final PhotoQuota? quota;

  /// The article already has a photo: changing it takes no new place.
  final bool hasPhoto;

  @override
  Widget build(BuildContext context) {
    final q = quota ?? photoQuotaOf(context, org);
    if (q == null || !q.limited) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final full = q.full && !hasPhoto;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Container(
            key: const Key('photo-counter'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: full ? maraBrown : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_camera_outlined,
                    size: 15, color: full ? maraPaper : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  context.tr('{used} / {limit} photos', {'used': q.used, 'limit': q.limit}),
                  style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: full ? maraPaper : null),
                ),
              ],
            ),
          ),
          if (full)
            TextButton.icon(
              key: const Key('photo-buy'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact, foregroundColor: maraBrown),
              onPressed: () => showModalBottomSheet<bool>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => PhotoSlotSheet(org: org, quota: q),
              ),
              icon: const CauriIcon(size: 16),
              label: Text(q.slotCost == null
                  ? context.tr('Une photo de plus')
                  : context.tr('Acheter une photo ({cost} cauris)', {'cost': q.slotCost})),
            ),
        ],
      ),
    );
  }
}

/// Every place taken: one more for cauris (for good), or Mara Pro.
class PhotoSlotSheet extends StatefulWidget {
  const PhotoSlotSheet({super.key, required this.org, required this.quota, this.balance});

  final OrgSummary org;
  final PhotoQuota quota;

  /// The wallet; the session's unless a test gives its own.
  final int? balance;

  @override
  State<PhotoSlotSheet> createState() => _PhotoSlotSheetState();
}

class _PhotoSlotSheetState extends State<PhotoSlotSheet> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fresh();
  }

  /// The wallet as the server says it now (108): the session's copy can be
  /// minutes behind a step just paid, and kept « Acheter » grey for
  /// somebody who had enough.
  Future<void> _fresh() async {
    if (widget.balance != null) return;
    final session = AppScope.read(context)?.session;
    if (session == null) return;
    try {
      await session.reloadFeatures(widget.org.id);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _buy() async {
    final scope = AppScope.read(context);
    if (scope == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await scope.admin.buyPhotoSlot(widget.org.id);
      await scope.session.reloadFeatures(widget.org.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.quota;
    final balance = widget.balance ??
        AppScope.maybeOf(context)?.session.featuresFor(widget.org.id)?.balance ??
        0;
    final cost = q.slotCost;
    final canBuy = widget.org.isAdmin && cost != null && balance >= cost;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: maraDeep,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined, color: maraCaramel, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('Toutes vos places photo sont prises'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(context.tr('{used} / {limit} photos', {'used': q.used, 'limit': q.limit}),
                          style: theme.textTheme.bodyMedium?.copyWith(color: maraBrown)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (cost != null) ...[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.tr('Une place de plus, pour toujours : '),
                      style: theme.textTheme.bodyLarge),
                  CaurisAmount(cost,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(context.tr('Vous en avez '), style: theme.textTheme.bodyMedium),
                  CaurisAmount(balance, style: theme.textTheme.bodyMedium),
                ],
              ),
            ],
            if (!widget.org.isAdmin) ...[
              const SizedBox(height: 6),
              Text(context.tr('Le propriétaire ou un administrateur peut l\'acheter.'),
                  style: theme.textTheme.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            if (cost != null)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('photo-slot-buy'),
                  onPressed: canBuy && !_busy ? _buy : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const CauriIcon(size: 18),
                  label: Text(context.tr('Acheter une photo ({cost} cauris)', {'cost': cost}),
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
            // Not in the iPhone app, which sells no Pro (125).
            if (sellsDigitalInApp)
              TextButton(
                key: const Key('photo-slot-pro'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                  context.push(Routes.inside(widget.org.id, 'kaj-pro'));
                },
                child: Text(context.tr('Ou passer à Mara Pro : photos sans limite')),
              ),
          ],
        ),
      ),
    );
  }
}

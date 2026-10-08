import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/shopper/shopper_repository.dart';
import '../storefront/shop_style.dart';

/// The topics of « Signaler un problème » (113's problem_reports), in order.
const reportTopics = ['order', 'vitrine', 'payment', 'delivery', 'app', 'other'];

String reportTopicLabel(BuildContext context, String topic) => switch (topic) {
      'order' => context.tr('Une commande'),
      'vitrine' => context.tr('Une vitrine'),
      'payment' => context.tr('Un paiement'),
      'delivery' => context.tr('Une livraison'),
      'app' => context.tr('L\'application'),
      _ => context.tr('Autre chose'),
    };

/// « Signaler un problème »: what it is about, a few words, sent. Mara reads
/// it in the command center (À faire › Signalements) and answers in the bell.
/// [slug] or [orderId] say which vitrine or order, when it is opened from one.
Future<void> showReportSheet(
  BuildContext context, {
  required ShopperRepository shopper,
  String? slug,
  String? orderId,
}) =>
    showShopSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Theme(
        data: ShopStyle.theme(sheet),
        child: ReportSheet(shopper: shopper, slug: slug, orderId: orderId),
      ),
    );

class ReportSheet extends StatefulWidget {
  const ReportSheet({super.key, required this.shopper, this.slug, this.orderId});

  final ShopperRepository shopper;
  final String? slug;
  final String? orderId;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  late String _topic = widget.orderId != null
      ? 'order'
      : widget.slug != null
          ? 'vitrine'
          : 'app';
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < 10) {
      setState(() => _error = context.tr('Dites en quelques mots ce qui ne va pas (10 caractères au moins).'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final thanks = context.tr('Merci : Mara a reçu votre signalement et vous répondra dans vos notifications.');
    try {
      await widget.shopper.report(
        topic: _topic,
        message: text,
        slug: widget.slug,
        orderId: widget.orderId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(thanks)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Signaler un problème'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ShopStyle.ink)),
            const SizedBox(height: 6),
            Text(context.tr('De quoi s\'agit-il ?'),
                style: const TextStyle(fontSize: 14, color: ShopStyle.mist)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in reportTopics)
                  ChoiceChip(
                    key: Key('report-$t'),
                    label: Text(reportTopicLabel(context, t)),
                    selected: _topic == t,
                    onSelected: _busy ? null : (_) => setState(() => _topic = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('report-text'),
              controller: _text,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.tr('Ce qui ne va pas, en quelques mots'),
                hintText: context.tr('La commande n\'est pas arrivée, le prix est faux…'),
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('report-send'),
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ShopStyle.paper))
                    : Text(context.tr('Envoyer à Mara')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

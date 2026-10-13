import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/org_access.dart';
import '../../core/auth/models.dart';
import '../../core/capture/capture_repository.dart';
import '../../core/credit/credit_repository.dart';
import '../../core/format/money.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/theme/kaj_card.dart';
import '../cauris/path_card.dart';
import '../home/place_sections.dart';
import '../invoicing/invoices_screen.dart';
import '../orders/shop_orders_screen.dart';
import 'for_sale_screen.dart';

/// « Ventes » (134), the farm's fourth place: all of the farm's selling in
/// one tab — À vendre (083), the vitrine's Commandes and the Factures, a
/// switch at the top; and the carnet one tap below it (« Crédit · on me
/// doit … »). « À vendre » and « Commandes » came out of Plus for it.
///
/// One address, `ventes?partie=a-vendre|commandes|factures`; the old
/// `a-vendre`, `commandes` and `factures` land here, on their section.
/// Factures' lock (089) is asked from the switch as the bar asked it.
class FarmSalesScreen extends StatefulWidget {
  const FarmSalesScreen({
    super.key,
    required this.org,
    required this.retail,
    this.invoicing,
    this.credit,
    this.capture,
    this.access = OrgAccess.allEdit,
    this.initialPart,
    this.focusOrder,
  });

  final OrgSummary org;
  final RetailRepository retail;
  final InvoicingRepository? invoicing;
  final CreditRepository? credit;
  final CaptureRepository? capture;
  final OrgAccess access;

  /// `?partie=`: 'a-vendre', 'commandes' or 'factures'.
  final String? initialPart;

  /// `?commande=`: the order a notification opened (125).
  final String? focusOrder;

  @override
  State<FarmSalesScreen> createState() => _FarmSalesScreenState();
}

class _FarmSalesScreenState extends State<FarmSalesScreen> {
  int? _orders;
  double? _owed;

  bool get _ordersShown => widget.access.canSee('orders');
  bool get _invoicesShown =>
      widget.invoicing != null && widget.access.canSee('invoices');
  bool get _creditShown => widget.credit != null && widget.access.canSee('credits');

  @override
  void initState() {
    super.initState();
    _read();
  }

  /// What waits in Commandes, and what the carnet says is owed: each on its
  /// own, best-effort.
  Future<void> _read() async {
    if (_ordersShown && widget.retail.isConfigured) {
      try {
        final n = await widget.retail.pendingOrders(widget.org.id);
        if (mounted) setState(() => _orders = n);
      } catch (_) {}
    }
    final credit = widget.credit;
    if (_creditShown && credit != null && credit.isConfigured) {
      try {
        final rows = await credit.debtors(widget.org.id);
        if (mounted) {
          setState(() => _owed = rows.fold<double>(0, (s, r) => s + r.totalOwed));
        }
      } catch (_) {}
    }
  }

  void _enter(BuildContext context, String id, VoidCallback open) {
    if (id == 'factures') {
      PathGate.open(context, widget.org, 'invoices', open);
    } else {
      open();
    }
  }

  Future<void> _openCredit() => PathGate.open(context, widget.org, 'credits', () async {
        await context.push(Routes.inside(widget.org.id, 'credits'));
        if (mounted) await _read();
      });

  @override
  Widget build(BuildContext context) {
    final org = widget.org;
    final owed = _owed;
    return PlaceSections(
      title: context.tr('Ventes'),
      initial: widget.initialPart,
      fallback: 'a-vendre',
      enter: _enter,
      below: _creditShown
          ? KajCard(
              key: const Key('farm-sales-credit'),
              margin: EdgeInsets.zero,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(context.tr('Crédit'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: owed == null
                    ? null
                    : Text(context.tr('On me doit {amount}',
                        {'amount': moneyFormat(org.currency).format(owed)})),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openCredit,
              ),
            )
          : null,
      sections: [
        PlaceSection(
          id: 'a-vendre',
          label: context.tr('À vendre'),
          build: (_) =>
              ForSaleScreen(org: org, retail: widget.retail, capture: widget.capture),
        ),
        if (_ordersShown)
          PlaceSection(
            id: 'commandes',
            label: context.tr('Commandes'),
            count: _orders,
            build: (_) => ShopOrdersScreen(
                org: org, retail: widget.retail, focusId: widget.focusOrder),
          ),
        if (_invoicesShown)
          PlaceSection(
            id: 'factures',
            label: context.tr('Factures'),
            build: (_) => InvoicesScreen(org: org, invoicing: widget.invoicing!),
          ),
      ],
    );
  }
}

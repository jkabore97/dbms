import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/capture/capture_repository.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/rates/currency_rates.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/retail/stock_rule.dart';
import '../capture/barcode_sheet.dart';
import '../common/step_flow.dart';
import '../common/keyboard_sheet.dart';

/// « Vente », one entry at a time (115) — the shop's till and the farm's,
/// replacing the one-form sale sheet.
///
/// The articles the customer asks for → how many of each (with what is
/// left on the shelf) → who (or « client de passage ») → how they pay
/// (Espèces; mobile money only where Mara allows it for this business;
/// Crédit) → the summary → « Enregistrer » → « C'est fait », with the
/// receipt to share on WhatsApp and « Nouvelle vente ».
///
/// The rules of the sheet it replaces stand, unchanged:
///
/// The basket carries one `client_uuid`, made when the flow opens, kept in
/// the draft and reused for every attempt. `record_sale()` returns the
/// original sale for a repeated uuid, so a double tap, a retry after a
/// timeout, or a sale resumed after the phone died cannot sell the same
/// goods twice. Only « Nouvelle vente » makes another.
///
/// A line can be an article from the shelf or a name typed on the spot:
/// refusing a sale because it was never entered would make the catalogue
/// more important than the customer.
///
/// No signal (package 7): the sale is kept on the phone and sent when the
/// network returns — the same outbox, the same parameters. A sale paid in
/// a foreign currency, or by Wave, needs the server's answer and is not.
///
/// Stock never goes below zero (101): the quantities step says what is
/// left, counting this phone's sales still waiting for the network.
/// « Banque » at the till (the old sale sheet had it): left out until the
/// owner decides (batch 115). THE ONE-LINE SWITCH — put 'bank' in this list
/// and the till offers it after Mobile, labelled « Banque »; record_sale
/// already takes it (it books it as the sheet of before did).
const tillExtraMethods = <String>[];

class SaleFlow extends StatefulWidget {
  const SaleFlow({
    super.key,
    required this.orgId,
    required this.retail,
    this.currency = 'XOF',
    this.capture,
    this.products = const [],
    this.canCredit = true,
    this.allowWave = false,
    this.initialMethod = 'cash',
    this.orgName = '',
    this.farm = false,
    this.store,
    this.customerName,
    this.customerPhone,
    this.initialLines = const [],
    this.onSaved,
  });

  /// The customer, already known (the carnet's « Nouveau crédit »): the
  /// customer step opens on this name.
  final String? customerName;

  /// Their phone, for a debt's new customer (record_sale's
  /// p_customer_phone; online only, as the outbox has no phone).
  final String? customerPhone;

  /// Lines the basket opens with (a harvest just sold: its article and
  /// how many) — the person still sees every step.
  final List<SaleLineDraft> initialLines;

  /// Told the sale's client_uuid each time one is saved — sent, or kept on
  /// the phone. The carnet asks its due date with it.
  final ValueChanged<String>? onSaved;

  /// A farm's sale: its things are « produits », not « articles » (108).
  final bool farm;

  /// The business's name, at the head of the receipt.
  final String orgName;

  /// Whether « Crédit » is offered at all — the owner's dial (031). The
  /// server refuses regardless; this keeps the refused choice off screen.
  final bool canCredit;

  /// Mara allows mobile payment for this business (090's wave_allowed, the
  /// « Espèces seulement » switch of its fiche): RULE M (111). Without it
  /// the till takes cash and credit only — « Mobile » is not drawn.
  final bool allowWave;

  /// 'credit' when the carnet opens the flow: the customer is asked by
  /// name and Crédit is chosen.
  final String initialMethod;

  final String orgId;
  final String currency;
  final RetailRepository retail;

  /// What is on the shelves. Empty is not an error — a shop with no
  /// catalogue still sells things.
  final List<Product> products;

  /// Only for `product_by_barcode()`. Null hides the scan button.
  final CaptureRepository? capture;

  /// Where the draft is kept (tests); the device's preferences otherwise.
  final FlowStore? store;

  @override
  State<SaleFlow> createState() => _SaleFlowState();
}

/// A line of the basket while it is being made.
class _Line {
  _Line({this.productId, required this.name, double quantity = 1, double? price})
      : quantity = TextEditingController(text: stockQty(quantity)),
        price = TextEditingController(
            text: price == null || price <= 0 ? '' : _plain(price));

  final String? productId;
  final String name;
  final TextEditingController quantity;
  final TextEditingController price;

  double get qty => FlowNumberField.read(quantity) ?? 0;
  double? get unitPrice => FlowNumberField.read(price);
  double get total => qty * (unitPrice ?? 0);

  SaleLineDraft get draft => SaleLineDraft(
      productId: productId, name: name, quantity: qty, unitPrice: unitPrice ?? 0);

  void dispose() {
    quantity.dispose();
    price.dispose();
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';
}

class _SaleFlowState extends State<SaleFlow> {
  final _flow = StepFlowController();
  final _lines = <_Line>[];
  final _search = TextEditingController();
  final _typedName = TextEditingController();
  final _typedPrice = TextEditingController();
  final _customer = TextEditingController();

  /// One per basket — see the class comment. Kept in the draft.
  String _clientUuid = const Uuid().v4();

  late String _method =
      widget.canCredit || widget.initialMethod != 'credit' ? widget.initialMethod : 'cash';

  /// « Client de passage » (false) or a named customer (true).
  late bool _named = widget.initialMethod == 'credit' ||
      (widget.customerName?.trim().isNotEmpty ?? false);

  bool _typing = false;

  String? _waveMerchant;
  List<CurrencyRate> _rates = const [];

  /// Null is the home currency — always the default.
  CurrencyRate? _tender;

  /// What this phone's sales still waiting for the network will take.
  Map<String, double> _waiting = const {};

  // What « C'est fait » says: pinned when saved.
  bool _queued = false;
  String? _sender;
  double _savedTotal = 0;
  double? _savedTendered;
  String? _savedTenderCurrency;
  double? _savedRate;
  String _receipt = '';

  NumberFormat get _money => moneyFormat(widget.currency);

  bool get _credit => _method == 'credit';

  /// Opened from the carnet (« Nouveau crédit »): a credit for the customer
  /// it names — Crédit is the only method, the draft its own
  /// (`sale-credit:<org>`, never the till's), the name the carnet's.
  bool get _fromCarnet => widget.initialMethod == 'credit' && widget.canCredit;

  /// The carnet's customer, when it named one.
  String? get _passedCustomer {
    final n = widget.customerName?.trim() ?? '';
    return n.isEmpty ? null : n;
  }

  /// The shelf without the kitchen: production ingredients stay out of the
  /// picker so a thumb cannot sell the flour at 0 F. Typing the name still
  /// works — the flag is a signpost, not a rule.
  late final List<Product> _sellable =
      widget.products.where((p) => !p.isIngredient).toList();

  List<Product> get _pickable {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _sellable;
    return _sellable.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  double get _total => _lines.fold<double>(0, (s, l) => s + l.total);

  String get _customerName => _named ? _customer.text.trim() : '';

  @override
  void initState() {
    super.initState();
    _customer.text = widget.customerName?.trim() ?? '';
    for (final l in widget.initialLines) {
      _lines.add(_Line(
          productId: l.productId,
          name: l.name,
          quantity: l.quantity,
          price: l.unitPrice));
    }
    _loadPaymentOptions();
    _loadWaiting();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _search.dispose();
    _typedName.dispose();
    _typedPrice.dispose();
    _customer.dispose();
    super.dispose();
  }

  Future<void> _loadWaiting() async {
    try {
      final waiting = await widget.retail.pendingSaleQuantities(widget.orgId);
      if (mounted) setState(() => _waiting = waiting);
    } catch (_) {}
  }

  Future<void> _loadPaymentOptions() async {
    // Tolerated separately: no Wave handle, no rates, no signal — fewer
    // choices, never the reason a sale cannot be recorded.
    if (widget.allowWave) {
      try {
        final merchant = await widget.retail.waveMerchant(widget.orgId);
        if (mounted) setState(() => _waveMerchant = merchant);
      } catch (_) {}
    }
    try {
      final rates = await widget.retail.currencyRates(widget.orgId);
      final foreign = rates.where((r) => r.currency != widget.currency).toList();
      if (mounted) {
        setState(() {
          _rates = foreign;
          // A tender kept in the draft, matched again once the rates are in.
          final want = _pendingTender;
          if (want != null) {
            for (final r in foreign) {
              if (r.currency == want) _tender = r;
            }
            _pendingTender = null;
          }
        });
      }
    } catch (_) {}
  }

  String? _pendingTender;

  // ----------------------------------------------------------------
  // The draft
  // ----------------------------------------------------------------

  Map<String, Object?> _save() => {
        'uuid': _clientUuid,
        'lines': [
          for (final l in _lines)
            {
              'id': l.productId,
              'name': l.name,
              'q': l.quantity.text,
              'p': l.price.text,
            },
        ],
        'named': _named,
        'customer': _customer.text,
        'method': _method,
        'tender': _tender?.currency,
      };

  void _restore(Map<String, Object?> a) {
    setState(() {
      _lines.forEach(_later);
      _lines.clear();
      final lines = a['lines'];
      if (lines is List) {
        for (final raw in lines) {
          if (raw is! Map) continue;
          final line = _Line(
              productId: raw['id'] as String?, name: '${raw['name'] ?? ''}');
          line.quantity.text = '${raw['q'] ?? '1'}';
          line.price.text = '${raw['p'] ?? ''}';
          if (line.name.isNotEmpty) _lines.add(line);
        }
      }
      final uuid = a['uuid'];
      _clientUuid = uuid is String && uuid.isNotEmpty ? uuid : const Uuid().v4();
      _named = a['named'] is bool
          ? a['named'] as bool
          : widget.initialMethod == 'credit' ||
              (widget.customerName?.trim().isNotEmpty ?? false);
      // The carnet's customer stays the carnet's: a kept draft never puts
      // another name on this credit.
      _customer.text = (_fromCarnet ? _passedCustomer : null) ??
          (a['customer'] as String?) ??
          widget.customerName?.trim() ??
          '';
      final method = a['method'];
      _method = method is String && _methods.contains(method)
          ? method
          : widget.initialMethod;
      final tender = a['tender'];
      _tender = null;
      _pendingTender = tender is String ? tender : null;
      for (final r in _rates) {
        if (r.currency == _pendingTender) _tender = r;
      }
      if (_tender != null) _pendingTender = null;
      _search.clear();
      _typing = false;
    });
  }

  // ----------------------------------------------------------------
  // The basket
  // ----------------------------------------------------------------

  Product? _productOf(_Line line) {
    for (final p in widget.products) {
      if (line.productId != null
          ? p.id == line.productId
          : p.name.trim().toLowerCase() == line.name.trim().toLowerCase()) {
        return p;
      }
    }
    return null;
  }

  /// What is left of [p] on the shelf, this phone's waiting sales taken
  /// off. [fresh]: the shelf as the server holds it now.
  double _left(Product p, {Map<String, double>? fresh}) =>
      (fresh?[p.id] ?? p.quantity) -
      (_waiting[p.id] ?? 0) -
      (_waiting['name:${p.name.trim().toLowerCase()}'] ?? 0);

  /// A line's fields are let go once the frame without them is drawn —
  /// never while a field still shows them.
  void _later(_Line l) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose());

  void _drop(_Line l) {
    setState(() => _lines.remove(l));
    _later(l);
    _flow.keep();
  }

  bool _inBasket(Product p) => _lines.any((l) => l.productId == p.id);

  void _toggle(Product p) {
    setState(() {
      final i = _lines.indexWhere((l) => l.productId == p.id);
      if (i >= 0) {
        _later(_lines.removeAt(i));
      } else {
        _lines.add(_Line(productId: p.id, name: p.name, price: p.salePrice));
      }
    });
    _flow.keep();
  }

  void _addTyped() {
    final name = _typedName.text.trim();
    final price = FlowNumberField.read(_typedPrice);
    if (name.isEmpty || price == null || price < 0) return;
    setState(() {
      _lines.add(_Line(name: name, price: price));
      _typedName.clear();
      _typedPrice.clear();
      _typing = false;
    });
    _flow.keep();
  }

  /// Scan, look up, and select — or say the shop has never seen this code.
  /// Nothing is created here: a barcode is an identifier, not an article.
  Future<void> _scan() async {
    final capture = widget.capture;
    if (capture == null) return;
    final code =
        await BarcodeSheet.scan(context, title: context.tr('Scanner un article'));
    if (code == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    for (final p in widget.products) {
      if (p.barcode == code) {
        if (!_inBasket(p)) _toggle(p);
        return;
      }
    }
    try {
      final row = await capture.productByBarcode(widget.orgId, code);
      if (!mounted) return;
      if (row == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(context.tr(
              'Code {code} inconnu dans cette boutique. Ajoutez l’article depuis Articles.',
              {'code': code})),
        ));
        return;
      }
      final price = row['sale_price'];
      setState(() => _lines.add(_Line(
            name: (row['name'] as String?) ?? code,
            price: price is num ? price.toDouble() : double.tryParse('$price'),
          )));
      _flow.keep();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// The first line asking more than the shelf holds, in the server's own
  /// sentence (101). Lines of one article are added up; a typed name is the
  /// article of that name, and one never received has nothing on the shelf.
  /// A service (098) has no stock. An article this flow was not given is
  /// left to the server.
  String? _stockProblem({Map<String, double>? fresh}) {
    final sold = <String, double>{};
    final names = <String, String>{};
    final left = <String, double>{};
    for (final line in _lines) {
      final p = _productOf(line);
      if (p == null) {
        if (line.productId == null && widget.products.isNotEmpty) {
          final key = 'typed:${line.name.trim().toLowerCase()}';
          sold[key] = (sold[key] ?? 0) + line.qty;
          names[key] = line.name.trim();
          left[key] = 0;
        }
        continue;
      }
      if (p.isService) continue;
      sold[p.id] = (sold[p.id] ?? 0) + line.qty;
      names[p.id] = p.name;
      left[p.id] = _left(p, fresh: fresh);
    }
    for (final e in sold.entries) {
      if (e.value > left[e.key]!) {
        return stockShortMessage(context.trLanguage, names[e.key]!, left[e.key]!);
      }
    }
    return null;
  }

  bool get _quantitiesValid =>
      _lines.isNotEmpty &&
      _lines.every((l) => l.qty > 0 && (l.unitPrice ?? -1) >= 0) &&
      _stockProblem() == null;

  // ----------------------------------------------------------------
  // Payment
  // ----------------------------------------------------------------

  List<String> get _methods => _fromCarnet
      ? const ['credit']
      : [
          'cash',
          // RULE M (111): mobile money only where Mara allows it.
          if (widget.allowWave) 'mobile_money',
          if (widget.allowWave && _waveMerchant != null) 'wave',
          ...tillExtraMethods,
          if (widget.canCredit) 'credit',
        ];

  String _methodLabel(String m) => switch (m) {
        'mobile_money' => context.tr('Mobile'),
        'wave' => context.tr('Wave'),
        'credit' => context.tr('Crédit'),
        'bank' => context.tr('Banque'),
        _ => context.tr('Espèces'),
      };

  // ----------------------------------------------------------------
  // Saving
  // ----------------------------------------------------------------

  /// A customer named for a sale that is not a credit is written on the
  /// sale's note — record_sale keeps a customer only for a debt.
  String? get _note => !_credit && _customerName.isNotEmpty
      ? context.tr('Client : {name}', {'name': _customerName})
      : null;

  Future<bool> _record() async {
    final problem = _stockProblem();
    if (problem != null) throw StateError(problem);
    if (_credit && _customerName.isEmpty) {
      throw StateError(context.tr('Entrez le nom du client pour un crédit.'));
    }
    if (_method == 'wave') return _recordWave();

    final lines = [for (final l in _lines) l.draft];
    final tender = _tender;
    final total = _total;
    final note = _note;
    try {
      final saleId = await widget.retail.recordSale(
        orgId: widget.orgId,
        lines: lines,
        method: _method,
        note: note,
        clientUuid: _clientUuid,
        customerName: _credit ? _customerName : null,
        customerPhone: _credit ? widget.customerPhone : null,
      );
      // Paid in a foreign currency: the cash that actually crossed the
      // counter, both amounts and the rate on the receipt.
      if (tender != null && total > 0 && !_credit) {
        final collected = tender.fromHome(total);
        await widget.retail.attachSaleTender(
          saleId: saleId,
          currency: tender.currency,
          amount: collected,
          rate: tender.rate,
        );
        _savedTendered = collected;
        _savedTenderCurrency = tender.currency;
        _savedRate = tender.rate;
      }
      _pin(total);
      return true;
    } catch (error) {
      // No signal: kept on the phone (package 7). Not a foreign-currency
      // sale — its receipt needs the server's answer.
      if (isOffline(error) &&
          widget.retail.canQueueSales &&
          (tender == null || _credit)) {
        await widget.retail.queueSale(
          orgId: widget.orgId,
          lines: lines,
          method: _method,
          note: note,
          clientUuid: _clientUuid,
          customerName: _credit ? _customerName : null,
        );
        _queued = true;
        _pin(total);
        return true;
      }
      rethrow;
    }
  }

  /// Wave: the shelf as the server holds it now (a QR scanned for what the
  /// server then refuses is money taken for nothing), the QR, the sender's
  /// name, the sale, the confirmation. Dismissed: nothing recorded.
  Future<bool> _recordWave() async {
    final merchant = _waveMerchant;
    if (merchant == null) return false;
    final ids = {for (final l in _lines) ?l.productId}.toList();
    if (ids.isNotEmpty) {
      Map<String, double>? fresh;
      try {
        fresh = await widget.retail.freshStock(widget.orgId, ids);
      } catch (_) {}
      if (fresh != null && mounted) {
        final problem = _stockProblem(fresh: fresh);
        if (problem != null) throw StateError(problem);
      }
    }
    if (!mounted) return false;
    final total = _total;
    final sender = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => WavePaymentSheet(
          merchant: merchant, amount: total, currency: widget.currency),
    );
    if (sender == null || !mounted) return false;
    final saleId = await widget.retail.recordSale(
      orgId: widget.orgId,
      lines: [for (final l in _lines) l.draft],
      method: 'wave',
      note: _note,
      clientUuid: _clientUuid,
    );
    await widget.retail.confirmWavePayment(saleId: saleId, sender: sender);
    _sender = sender;
    _pin(total);
    return true;
  }

  /// What « C'est fait » and the receipt say, fixed at the moment of saving.
  void _pin(double total) {
    _savedTotal = total;
    _receipt = _receiptText(total);
    // The carnet dates a debt with it: only a real credit has one.
    if (_credit) widget.onSaved?.call(_clientUuid);
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)}/${now.year} ${two(now.hour)}:${two(now.minute)}';
  }

  String _receiptText(double total) {
    final b = StringBuffer();
    b.writeln(widget.orgName.isNotEmpty ? widget.orgName : context.tr('Reçu'));
    b.writeln(_stamp());
    b.writeln();
    for (final l in _lines) {
      b.writeln('${stockQty(l.qty)} × ${l.name} — ${_money.format(l.total)}');
    }
    b.writeln();
    b.writeln(context.tr('Total : {total}', {'total': _money.format(total)}));
    final tender = _tender;
    if (tender != null && !_credit) {
      b.writeln(context.tr('Payé : {amount}',
          {'amount': foreignMoneyFormat(tender.currency).format(tender.fromHome(total))}));
      b.writeln(rateLabel(tender.currency, tender.rate, widget.currency));
    }
    b.writeln(context.tr('Paiement : {method}', {'method': _methodLabel(_method)}));
    if (_customerName.isNotEmpty) {
      b.writeln(context.tr('Client : {name}', {'name': _customerName}));
    }
    if (_sender != null) {
      b.writeln(context.tr('Payé par : {name}', {'name': _sender}));
    }
    b.writeln();
    b.write(context.tr('Merci !'));
    return b.toString();
  }

  Future<void> _shareReceipt() async {
    final uri = Uri.parse(
        'https://wa.me/?text=${Uri.encodeComponent(_receipt)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No WhatsApp here: the text is copied, ready to paste anywhere.
      await Clipboard.setData(ClipboardData(text: _receipt));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.tr('Reçu copié.'))));
    }
  }

  void _newSale() {
    setState(() {
      _lines.forEach(_later);
      _lines.clear();
      _clientUuid = const Uuid().v4();
      _method = widget.initialMethod == 'credit' && widget.canCredit
          ? 'credit'
          : 'cash';
      _named = widget.initialMethod == 'credit';
      // From the carnet the next sale is still that customer's credit;
      // at the till a new customer, a new basket.
      _customer.text = _fromCarnet ? (_passedCustomer ?? '') : '';
      _tender = null;
      _queued = false;
      _sender = null;
      _savedTendered = null;
      _savedTenderCurrency = null;
      _savedRate = null;
    });
    _loadWaiting();
    _flow.restart();
  }

  // ----------------------------------------------------------------
  // The steps
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StepFlow(
      title: context.tr('Vente'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
          key: _fromCarnet ? 'sale-credit:${widget.orgId}' : 'sale:${widget.orgId}',
          save: _save,
          restore: _restore),
      saveLabel: _method == 'wave'
          ? context.tr('Payer avec Wave')
          : context.tr('Enregistrer la vente'),
      steps: [
        FlowStep(
          id: 'articles',
          title: widget.farm ? context.tr('Quels produits ?') : context.tr('Quels articles ?'),
          help: widget.farm
              ? context.tr('Choisissez les produits demandés par le client ici')
              : context.tr('Choisissez les articles demandés par le client ici'),
          isValid: () => _lines.isNotEmpty,
          builder: _articlesStep,
        ),
        FlowStep(
          id: 'quantities',
          title: context.tr('Combien ?'),
          isValid: () => _quantitiesValid,
          builder: _quantitiesStep,
        ),
        FlowStep(
          id: 'customer',
          title: context.tr('Pour quel client ?'),
          isValid: () => !_named || _customer.text.trim().isNotEmpty,
          builder: _customerStep,
        ),
        FlowStep(
          id: 'payment',
          title: context.tr('Comment le client paie ?'),
          isValid: () =>
              _methods.contains(_method) &&
              (!_credit || _customer.text.trim().isNotEmpty),
          builder: _paymentStep,
        ),
      ],
      summary: _summary,
      onSave: _record,
      done: _done,
    );
  }

  Widget _articlesStep(BuildContext context) {
    final theme = Theme.of(context);
    final pickable = _pickable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (_sellable.length > 8)
              Expanded(
                child: TextField(
                  key: const Key('sale-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: widget.farm
                        ? context.tr('Rechercher un produit…')
                        : context.tr('Rechercher un article…'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: context.tr('Effacer'),
                            onPressed: () => setState(_search.clear),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              )
            else
              const Spacer(),
            if (widget.capture != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('sale-scan'),
                iconSize: 28,
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: context.tr('Scanner un code-barres'),
              ),
            ],
          ],
        ),
        if (_sellable.length > 8 || widget.capture != null)
          const SizedBox(height: 12),
        if (_sellable.isNotEmpty && pickable.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              context.tr('Aucun article ne correspond — tapez le nom ci-dessous pour le vendre quand même.'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 520 ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [for (final p in pickable) _tile(context, p)],
        ),
        // Lines typed on the spot, already in the basket.
        for (final l in _lines)
          if (l.productId == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: InputChip(
                key: ValueKey('sale-typed-${l.name}'),
                avatar: const Icon(Icons.edit_note, size: 18),
                label: Text('${l.name} · ${_money.format(l.unitPrice ?? 0)}'),
                onDeleted: () => _drop(l),
              ),
            ),
        const SizedBox(height: 12),
        if (!_typing && _sellable.isNotEmpty)
          OutlinedButton.icon(
            key: const Key('sale-type-open'),
            onPressed: () => setState(() => _typing = true),
            icon: const Icon(Icons.add),
            label: Text(widget.farm
                ? context.tr('Un produit qui n\'est pas dans la liste')
                : context.tr('Un article qui n\'est pas dans la liste')),
          )
        else ...[
          TextField(
            key: const Key('sale-typed-name'),
            controller: _typedName,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.farm ? context.tr('Produit') : context.tr('Article'),
              hintText: context.tr('Sucre 1kg'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('sale-typed-price'),
            controller: _typedPrice,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('Prix unitaire'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              key: const Key('sale-typed-add'),
              onPressed: _typedName.text.trim().isNotEmpty &&
                      FlowNumberField.read(_typedPrice) != null
                  ? _addTyped
                  : null,
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(context.tr('Ajouter au panier')),
            ),
          ),
        ],
        if (_lines.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            context.tr('{n} dans le panier · {total}',
                {'n': _lines.length, 'total': _money.format(_total)}),
            key: const Key('sale-basket-count'),
            style: theme.textTheme.titleMedium,
          ),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, Product p) {
    final theme = Theme.of(context);
    final picked = _inBasket(p);
    final left = _left(p);
    final empty = !p.isService && left <= 0;
    return Material(
      color: picked
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: picked ? theme.colorScheme.primary : Colors.transparent,
            width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('sale-pick-${p.id}'),
        // Nothing left: nothing to sell (101) — the tile says so instead
        // of letting the basket fill with what the server will refuse.
        onTap: empty && !picked ? null : () => _toggle(p),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (p.isService)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.event_available_outlined, size: 18),
                    ),
                  Expanded(
                    child: Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: empty ? theme.disabledColor : null)),
                  ),
                  if (picked)
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                ],
              ),
              const Spacer(),
              if (p.salePrice > 0)
                Text(_money.format(p.salePrice), style: theme.textTheme.bodyMedium),
              if (!p.isService)
                Text(
                  empty
                      ? context.tr('Plus en stock')
                      : context.tr('Reste : {n}', {'n': stockQty(left)}),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: empty
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quantitiesStep(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _stockProblem();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in _lines) ...[
          _quantityCard(context, l),
          const SizedBox(height: 10),
        ],
        if (problem != null)
          Text(problem,
              key: const Key('sale-stock-short'),
              style: TextStyle(color: theme.colorScheme.error, fontSize: 16)),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.tr('Total'), style: theme.textTheme.titleMedium),
            Text(_money.format(_total),
                key: const Key('sale-total'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _quantityCard(BuildContext context, _Line l) {
    final theme = Theme.of(context);
    final p = _productOf(l);
    void step(double by) {
      final next = (l.qty + by).clamp(0, double.infinity).toDouble();
      setState(() => l.quantity.text = stockQty(next));
      _flow.keep();
    }

    return Container(
      key: ValueKey('sale-line-${l.productId ?? l.name}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: context.tr('Retirer'),
                icon: const Icon(Icons.close),
                onPressed: () => _drop(l),
              ),
            ],
          ),
          if (p != null && !p.isService)
            Text(context.tr('Reste : {n}', {'n': stockQty(_left(p))}),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(
                key: ValueKey('sale-minus-${l.productId ?? l.name}'),
                iconSize: 28,
                onPressed: l.qty > 1 ? () => step(-1) : null,
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: TextField(
                  key: ValueKey('sale-qty-${l.productId ?? l.name}'),
                  controller: l.quantity,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: ValueKey('sale-plus-${l.productId ?? l.name}'),
                iconSize: 28,
                onPressed: () => step(1),
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: ValueKey('sale-price-${l.productId ?? l.name}'),
                  controller: l.price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr('Prix unitaire'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(_money.format(l.total),
                style: theme.textTheme.titleMedium),
          ),
        ],
      ),
    );
  }

  Widget _customerStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowChoice<bool>(
          options: [
            // A debt needs a name: no « de passage » for the carnet.
            if (widget.initialMethod != 'credit')
              FlowOption(false, context.tr('Client de passage'),
                  icon: Icons.directions_walk),
            FlowOption(true, context.tr('Un client que je connais'),
                icon: Icons.person_outline,
                detail: context.tr('Son nom va sur le reçu (et dans le carnet pour un crédit).')),
          ],
          value: _named,
          onChanged: (v) {
            setState(() {
              _named = v;
              if (!v && _credit) _method = 'cash';
            });
            _flow.keep();
          },
        ),
        if (_named) ...[
          const SizedBox(height: 8),
          _nameField(context),
        ],
      ],
    );
  }

  Widget _nameField(BuildContext context) => TextField(
        key: const Key('sale-customer'),
        controller: _customer,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: context.tr('Nom du client'),
          border: const OutlineInputBorder(),
        ),
      );

  Widget _paymentStep(BuildContext context) {
    final theme = Theme.of(context);
    final methods = _methods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowChoice<String>(
          options: [
            for (final m in methods)
              FlowOption(
                m,
                _methodLabel(m),
                icon: switch (m) {
                  'mobile_money' => Icons.phone_android,
                  'wave' => Icons.qr_code_2,
                  'credit' => Icons.menu_book_outlined,
                  'bank' => Icons.account_balance_outlined,
                  _ => Icons.payments_outlined,
                },
                detail: m == 'credit'
                    ? context.tr('La vente ira dans le carnet de crédit.')
                    : m == 'wave'
                        ? context.tr('Le client scanne le code avec Wave.')
                        : null,
              ),
          ],
          value: _method,
          onChanged: (m) {
            setState(() {
              _method = m;
              // A debt is owed in the home currency, and Wave pays in it.
              if (m == 'credit' || m == 'wave') _tender = null;
              if (m == 'credit') _named = true;
            });
            _flow.keep();
          },
        ),
        // A credit to « client de passage »: the name, right here.
        if (_credit && _customer.text.trim().isEmpty) ...[
          const SizedBox(height: 4),
          _nameField(context),
        ],
        // The customer's currency, only when the owner set rates.
        if (_rates.isNotEmpty && (_method == 'cash' || _method == 'mobile_money')) ...[
          const SizedBox(height: 12),
          Text(context.tr('Le client paie en'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(widget.currency == 'XOF' ? 'FCFA' : widget.currency),
                selected: _tender == null,
                onSelected: (_) => setState(() => _tender = null),
              ),
              for (final r in _rates)
                ChoiceChip(
                  label: Text(r.currency),
                  selected: _tender?.currency == r.currency,
                  onSelected: (_) {
                    setState(() => _tender = r);
                    _flow.keep();
                  },
                ),
            ],
          ),
          if (_tender != null && _total > 0) ...[
            const SizedBox(height: 10),
            _tenderRow(context),
          ],
        ],
      ],
    );
  }

  Widget _tenderRow(BuildContext context) {
    final theme = Theme.of(context);
    final tender = _tender!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(context.tr('À encaisser'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(foreignMoneyFormat(tender.currency).format(tender.fromHome(_total)),
                key: const Key('sale-tendered'),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(rateLabel(tender.currency, tender.rate, widget.currency),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) => FlowSummary(
        rows: [
          for (final l in _lines)
            FlowSummaryRow('${stockQty(l.qty)} × ${l.name}', _money.format(l.total),
                step: 'quantities'),
          FlowSummaryRow(
              context.tr('Client'),
              _customerName.isEmpty
                  ? context.tr('Client de passage')
                  : _customerName,
              step: 'customer'),
          FlowSummaryRow(context.tr('Paiement'), _methodLabel(_method),
              step: 'payment'),
          FlowSummaryRow(context.tr('Total'), _money.format(_total), bold: true),
        ],
        footer: _tender != null && !_credit && _total > 0 ? _tenderRow(context) : null,
      );

  Widget _done(BuildContext context) {
    final theme = Theme.of(context);
    final details = <Widget>[
      Text(_money.format(_savedTotal),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      if (_savedTendered != null)
        Text(
          '${foreignMoneyFormat(_savedTenderCurrency!).format(_savedTendered)} · '
          '${rateLabel(_savedTenderCurrency!, _savedRate!, widget.currency)}',
          key: const Key('sale-done-tender'),
          textAlign: TextAlign.center,
        ),
      if (_sender != null)
        Text(context.tr('Payé par : {name}', {'name': _sender}),
            key: const Key('sale-done-sender'), textAlign: TextAlign.center),
      if (_queued) ...[
        const SizedBox(height: 8),
        Text(
          context.tr('Pas de réseau : vente gardée sur le téléphone. Elle partira dès le retour de la connexion.'),
          key: const Key('sale-done-queued'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    ];
    return FlowDone(
      message: _method == 'wave'
          ? context.tr('Paiement Wave reçu')
          : _credit
              ? context.tr('Vente à crédit enregistrée')
              : context.tr('Vente enregistrée'),
      details: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: details),
      actions: [
        FlowAction(
          key: const Key('sale-share'),
          label: context.tr('Partager le reçu sur WhatsApp'),
          icon: Icons.share_outlined,
          primary: true,
          onPressed: _shareReceipt,
        ),
        FlowAction(
          key: const Key('sale-again'),
          label: context.tr('Nouvelle vente'),
          icon: Icons.add_shopping_cart,
          onPressed: _newSale,
        ),
      ],
    );
  }
}

/// The Wave payment step: the customer scans, pays, and the shopkeeper types
/// the name Wave shows for the payer before confirming.
///
/// Returns the sender's name on confirm, or null when dismissed. It records
/// nothing itself — the sale is written only after this returns a name, so a
/// customer who walks away leaves no sale behind.
class WavePaymentSheet extends StatefulWidget {
  const WavePaymentSheet({
    super.key,
    required this.merchant,
    required this.amount,
    required this.currency,
  });

  /// The business's Wave handle, encoded into the QR the customer scans.
  final String merchant;
  final double amount;
  final String currency;

  @override
  State<WavePaymentSheet> createState() => _WavePaymentSheetState();
}

class _WavePaymentSheetState extends State<WavePaymentSheet> {
  final _senderController = TextEditingController();
  NumberFormat get _money => moneyFormat(widget.currency);

  @override
  void dispose() {
    _senderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyboardSheet(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      // The fields scroll; the button stays above the keyboard (A6).
      footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.tr('Annuler')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _senderController.text.trim().isEmpty
                        ? null
                        : () => Navigator.of(context)
                            .pop(_senderController.text.trim()),
                    icon: const Icon(Icons.check),
                    label: Text(context.tr('Paiement reçu')),
                  ),
                ),
              ),
            ],
          ),
      children: [
          Text(context.tr('Paiement Wave'), style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(context.tr('Faites scanner ce code au client, puis entrez son nom Wave.'),
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              // Drawn on the device — nothing fetched, so it shows with no
              // signal, which is the whole point at a counter.
              child: QrImageView(
                data: widget.merchant,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _money.format(widget.amount),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _senderController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('Nom de l\'expéditeur Wave'),
              helperText: context.tr('Le nom qui apparaît sur le paiement Wave.'),
              border: const OutlineInputBorder(),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';

import '../../core/auth/models.dart';
import '../../core/format/money.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/invoicing/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/phone/country_codes.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../common/phone_field.dart';
import '../common/step_flow.dart';
import '../credit/customer_pick.dart';

/// « Facture », one entry at a time (115) — for a shop, a farm and an
/// association alike (create_invoice checks no profile: a shop bills a
/// wholesaler, a farm a hotel, an association a hall's hire).
///
/// For whom → how to reach them (optional) → what: the articles and
/// services of the business, picked one at a time, or a line typed → how
/// many, at what price → when it is due → an internal note (optional) →
/// the preview → « Créer la facture » → « C'est fait », with the document
/// to open and share (its WhatsApp and PDF buttons are there).
///
/// The same flow corrects an invoice ([revisionOf], owner only, 040):
/// opened filled from the document, saved through revise_invoice — the
/// server withdraws the old one and issues the replacement in one
/// transaction.
///
/// Needs signal, as the form it replaces did and for the same reason: the
/// number comes from the server (see [InvoicingRepository]). The answers
/// wait on the phone in the meantime, and a new invoice keeps one
/// client_uuid from the first screen to the last attempt, so a retry after
/// a timeout cannot raise it twice.
class InvoiceFlow extends StatefulWidget {
  const InvoiceFlow({
    super.key,
    required this.org,
    required this.invoicing,
    this.retail,
    this.revisionOf,
    this.onOpen,
    this.onSaved,
    this.store,
  });

  final OrgSummary org;
  final InvoicingRepository invoicing;

  /// The business's articles and services, to pick from. Null: lines typed.
  final RetailRepository? retail;
  final InvoiceDocument? revisionOf;

  /// « Voir et partager »: the caller opens the document (the flow has
  /// closed by then).
  final ValueChanged<String>? onOpen;

  /// The invoice written — its id — as soon as the server answered.
  final ValueChanged<String>? onSaved;
  final FlowStore? store;

  @override
  State<InvoiceFlow> createState() => _InvoiceFlowState();
}

class _Line {
  _Line({this.productId, required this.name, double quantity = 1, double? price})
      : quantity = TextEditingController(text: _plain(quantity)),
        price = TextEditingController(text: price == null ? '' : _plain(price));

  final String? productId;
  final String name;
  final TextEditingController quantity;
  final TextEditingController price;

  double get qty => parseAmount(quantity.text) ?? 0;
  double get unit => parseAmount(price.text) ?? 0;
  double get amount => qty * unit;
  bool get complete => name.trim().isNotEmpty && qty > 0 && unit > 0;

  InvoiceLine toLine() =>
      InvoiceLine(description: name, quantity: qty, unitPrice: unit);

  Map<String, Object?> toJson() => {
        'product': productId,
        'name': name,
        'qty': quantity.text,
        'price': price.text,
      };

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}

class _InvoiceFlowState extends State<InvoiceFlow> {
  static const _uuid = Uuid();
  final _flow = StepFlowController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _memo = TextEditingController();
  final _search = TextEditingController();
  final _typedName = TextEditingController();
  final _typedPrice = TextEditingController();
  final _lines = <_Line>[];
  CountryCode _country = defaultCountry;

  /// 'now' (à réception), `days:N` or `date:YYYY-MM-DD`.
  String _due = 'days:30';
  String _clientUuid = _uuid.v4();
  List<String> _known = const [];
  List<Product> _catalog = const [];
  bool _catalogLoading = false;
  String? _savedId;

  bool get _revising => widget.revisionOf != null;
  NumberFormat get _money => moneyFormat(widget.org.currency);
  double get _total => _lines.fold(0, (s, l) => s + l.amount);

  @override
  void initState() {
    super.initState();
    final doc = widget.revisionOf;
    if (doc != null) {
      _customer.text = doc.customerName;
      _address.text = doc.customerAddress ?? '';
      for (final l in doc.lines) {
        _lines.add(_Line(name: l.description, quantity: l.quantity, price: l.unitPrice));
      }
      final due = doc.dueOn;
      _due = due == null ? 'now' : 'date:${_day(due)}';
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_customer, _phone, _address, _memo, _search, _typedName, _typedPrice]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// Who was billed before (the names, newest first) and what the business
  /// sells — both best effort: the step works typed.
  Future<void> _load() async {
    final retail = widget.retail;
    if (retail != null && retail.isConfigured) {
      setState(() => _catalogLoading = true);
      try {
        final products = await retail.products(widget.org.id);
        if (mounted) setState(() => _catalog = products);
      } catch (_) {}
      if (mounted) setState(() => _catalogLoading = false);
    }
    if (!widget.invoicing.isConfigured) return;
    try {
      final invoices = await widget.invoicing.list(widget.org.id, limit: 100);
      final names = <String>[];
      for (final i in invoices) {
        final n = i.customerName.trim();
        if (n.isNotEmpty && !names.any((k) => k.toLowerCase() == n.toLowerCase())) {
          names.add(n);
        }
      }
      if (mounted) setState(() => _known = names);
    } catch (_) {}
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int? get _dueDays =>
      _due.startsWith('days:') ? int.tryParse(_due.substring(5)) : null;
  DateTime? get _dueOn =>
      _due.startsWith('date:') ? DateTime.tryParse(_due.substring(5)) : null;

  String _dueLabel() {
    final days = _dueDays;
    if (days != null) return context.tr('{days} jours', {'days': days});
    final on = _dueOn;
    if (on != null) {
      return DateFormat('d MMMM y', context.trLanguage == 'en' ? 'en' : 'fr_FR')
          .format(on);
    }
    return context.tr('À réception');
  }

  void _add(Product p) {
    setState(() {
      final at = _lines.indexWhere((l) => l.productId == p.id);
      if (at >= 0) {
        final l = _lines[at];
        l.quantity.text = _Line._plain(l.qty + 1);
      } else {
        _lines.add(_Line(
            productId: p.id,
            name: p.name,
            price: p.salePrice > 0 ? p.salePrice : null));
      }
    });
    _flow.keep();
  }

  void _addTyped() {
    final name = _typedName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _lines.add(_Line(name: name, price: parseAmount(_typedPrice.text)));
      _typedName.clear();
      _typedPrice.clear();
    });
    _flow.keep();
  }

  Map<String, Object?> _save() => {
        'customer': _customer.text,
        'phone': _phone.text,
        'country': _country.iso,
        'address': _address.text,
        'lines': [for (final l in _lines) l.toJson()],
        'due': _due,
        'memo': _memo.text,
        'uuid': _clientUuid,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _customer.text = (a['customer'] as String?) ?? (widget.revisionOf?.customerName ?? '');
        _phone.text = (a['phone'] as String?) ?? '';
        _country = countryByIso(a['country'] as String?);
        _address.text = (a['address'] as String?) ?? (widget.revisionOf?.customerAddress ?? '');
        for (final l in _lines) {
          l.dispose();
        }
        _lines.clear();
        final lines = a['lines'];
        if (lines is List) {
          for (final raw in lines.whereType<Map>()) {
            final line = _Line(
                productId: raw['product'] as String?,
                name: '${raw['name'] ?? ''}');
            line.quantity.text = '${raw['qty'] ?? '1'}';
            line.price.text = '${raw['price'] ?? ''}';
            _lines.add(line);
          }
        } else if (widget.revisionOf != null) {
          for (final l in widget.revisionOf!.lines) {
            _lines.add(_Line(name: l.description, quantity: l.quantity, price: l.unitPrice));
          }
        }
        _due = (a['due'] as String?) ?? 'days:30';
        _memo.text = (a['memo'] as String?) ?? '';
        _clientUuid = (a['uuid'] as String?) ?? _uuid.v4();
      });

  Future<bool> _create() async {
    final phone = _phone.text.trim().isEmpty ? null : _country.toE164(_phone.text);
    final lines = [for (final l in _lines) if (l.complete) l.toLine()];
    final revising = widget.revisionOf;
    final id = revising != null
        ? await widget.invoicing.revise(
            invoiceId: revising.id,
            customerName: _customer.text.trim(),
            customerAddress: _address.text.trim(),
            customerPhone: phone,
            lines: lines,
            dueDays: _dueDays,
            dueOn: _dueOn,
            memo: _memo.text.trim(),
          )
        : await widget.invoicing.create(
            orgId: widget.org.id,
            customerName: _customer.text.trim(),
            customerAddress: _address.text.trim(),
            customerPhone: phone,
            lines: lines,
            dueDays: _dueDays,
            dueOn: _dueOn,
            memo: _memo.text.trim(),
            clientUuid: _clientUuid,
          );
    _savedId = id;
    widget.onSaved?.call(id);
    return true;
  }

  void _another() {
    _restore(const {});
    _flow.restart();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueOn ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _due = 'date:${_day(picked)}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final p in _catalog)
        if (q.isEmpty || p.name.toLowerCase().contains(q)) p,
    ];
    return StepFlow(
      title: _revising
          ? context.tr('Corriger la facture {number}', {'number': widget.revisionOf!.number})
          : context.tr('Nouvelle facture'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
        key: _revising
            ? 'invoice-fix:${widget.revisionOf!.id}'
            : 'invoice:${widget.org.id}',
        save: _save,
        restore: _restore,
      ),
      steps: [
        FlowStep(
          id: 'customer',
          title: context.tr('Pour qui ?'),
          isValid: () => _customer.text.trim().isNotEmpty,
          builder: (_) => CustomerPick(
            controller: _customer,
            known: _known,
            hint: context.tr('Hôtel Indépendance'),
            onChanged: () => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'contact',
          title: context.tr('Comment le joindre ?'),
          optional: true,
          isValid: () => _country.lengthProblem(_phone.text) == null,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhoneField(
                controller: _phone,
                country: _country,
                onCountry: (c) => setState(() => _country = c),
                labelText: context.tr('Téléphone (facultatif)'),
                hintText: '70 12 34 56',
                errorText: _country.lengthProblem(_phone.text),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('invoice-address'),
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('Adresse (facultatif)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'items',
          title: context.tr('Qu\'est-ce que vous facturez ?'),
          help: context.tr('Touchez chaque article ou service, un à la fois.'),
          isValid: () => _lines.isNotEmpty,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_lines.isNotEmpty) ...[
                Container(
                  key: const Key('invoice-basket'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.tr('Sur la facture : {lines}', {
                      'lines': _lines
                          .map((l) => '${_Line._plain(l.qty)} × ${l.name}')
                          .join(', ')
                    }),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_catalogLoading) const LinearProgressIndicator(),
              if (_catalog.length > 6) ...[
                TextField(
                  key: const Key('invoice-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: context.tr('Chercher'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final p in shown.take(30))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    key: Key('invoice-product-${p.id}'),
                    minTileHeight: 60,
                    leading: Icon(p.isService
                        ? Icons.design_services_outlined
                        : Icons.inventory_2_outlined),
                    title: Text(p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: p.salePrice > 0
                        ? Text(_money.format(p.salePrice))
                        : null,
                    trailing: _lines.any((l) => l.productId == p.id)
                        ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                        : const Icon(Icons.add_circle_outline),
                    onTap: () => _add(p),
                  ),
                ),
              const SizedBox(height: 8),
              Text(context.tr('Autre chose'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                key: const Key('invoice-typed-name'),
                controller: _typedName,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr('Désignation'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('invoice-typed-price'),
                      controller: _typedPrice,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: context.tr('Prix unitaire'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: FilledButton.tonalIcon(
                      key: const Key('invoice-typed-add'),
                      onPressed: _typedName.text.trim().isEmpty ? null : _addTyped,
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Ajouter')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'quantities',
          title: context.tr('Combien, et à quel prix ?'),
          isValid: () => _lines.isNotEmpty && _lines.every((l) => l.complete),
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _lines.length; i++)
                Card(
                  key: ObjectKey(_lines[i]),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(_lines[i].name,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                            IconButton(
                              key: Key('invoice-remove-$i'),
                              tooltip: context.tr('Retirer la ligne'),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => setState(() {
                                _lines.removeAt(i).dispose();
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                key: Key('invoice-qty-$i'),
                                controller: _lines[i].quantity,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: theme.textTheme.titleLarge,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: context.tr('Qté'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                key: Key('invoice-price-$i'),
                                controller: _lines[i].price,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: theme.textTheme.titleLarge,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: context.tr('Prix unitaire'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _lines[i].amount > 0 ? _money.format(_lines[i].amount) : '—',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  Text(context.tr('Total'), style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Text(_money.format(_total),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'due',
          title: context.tr('À payer quand ?'),
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowChoice<String>(
                options: [
                  FlowOption('now', context.tr('À réception')),
                  for (final d in const [7, 15, 30, 60])
                    FlowOption('days:$d', context.tr('{days} jours', {'days': d})),
                  FlowOption(
                      _dueOn == null ? 'date' : _due,
                      _dueOn == null ? context.tr('Une date précise') : _dueLabel(),
                      icon: Icons.event_outlined),
                ],
                value: _due,
                onChanged: (v) => v == 'date' || v.startsWith('date:')
                    ? _pickDate()
                    : setState(() => _due = v),
              ),
            ],
          ),
        ),
        FlowStep(
          id: 'memo',
          title: context.tr('Une note pour vous ?'),
          help: context.tr('N\'apparaît pas sur la facture.'),
          optional: true,
          builder: (_) => TextField(
            key: const Key('invoice-memo'),
            controller: _memo,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ],
      summaryTitle: context.tr('La facture'),
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Client'), _customer.text.trim(), step: 'customer'),
          if (_phone.text.trim().isNotEmpty || _address.text.trim().isNotEmpty)
            FlowSummaryRow(
                context.tr('Contact'),
                [
                  if (_phone.text.trim().isNotEmpty) _country.toE164(_phone.text),
                  if (_address.text.trim().isNotEmpty) _address.text.trim(),
                ].join('\n'),
                step: 'contact'),
          for (final l in _lines)
            FlowSummaryRow('${_Line._plain(l.qty)} × ${l.name}',
                _money.format(l.amount),
                step: 'quantities'),
          FlowSummaryRow(context.tr('Total'), _money.format(_total), bold: true),
          FlowSummaryRow(context.tr('Échéance'), _dueLabel(), step: 'due'),
          if (_memo.text.trim().isNotEmpty)
            FlowSummaryRow(context.tr('Note interne'), _memo.text.trim(), step: 'memo'),
        ],
        footer: Text(
          context.tr('Il faut du réseau pour créer la facture : son numéro vient du serveur.'),
          style: theme.textTheme.bodySmall,
        ),
      ),
      saveLabel: _revising ? context.tr('Corriger la facture') : context.tr('Créer la facture'),
      onSave: _create,
      done: (_) => FlowDone(
        message: _revising
            ? context.tr('Facture corrigée : {total}', {'total': _money.format(_total)})
            : context.tr('Facture créée pour {customer} : {total}',
                {'customer': _customer.text.trim(), 'total': _money.format(_total)}),
        actions: [
          if (_savedId != null && widget.onOpen != null)
            FlowAction(
              key: const Key('invoice-open'),
              label: context.tr('Voir et partager la facture'),
              icon: Icons.ios_share,
              primary: true,
              onPressed: () {
                final id = _savedId!;
                Navigator.of(context).pop(true);
                widget.onOpen!(id);
              },
            ),
          if (!_revising)
            FlowAction(
              key: const Key('invoice-another'),
              label: context.tr('Nouvelle facture'),
              icon: Icons.add,
              onPressed: () {
                _savedId = null;
                _another();
              },
            ),
        ],
      ),
    );
  }
}

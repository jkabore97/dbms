import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth/models.dart';
import '../../core/credit/credit_repository.dart';
import '../../core/db/local_db.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/phone/country_codes.dart';
import '../../core/retail/models.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/storefront/storefront_repository.dart' show whatsappShareUrl, whatsappUrl;
import '../common/phone_field.dart';
import '../common/step_flow.dart';
import '../retail/sale_flow.dart';
import 'customer_pick.dart';

/// The carnet de crédit's two acts (115), one question a screen — for a
/// shop, a farm and an association alike.
///
/// « Nouveau crédit »: who → their WhatsApp number (optional) → a sum or
/// articles (a shop and a farm; an association lends sums only) → the sum
/// and what it is for → when they will pay (optional) → the summary →
/// « Enregistrer » → « C'est fait », with « Envoyer un rappel sur
/// WhatsApp ». A sum is record_credit_sale (024, online as before); the
/// articles are the « Vente » flow opened on Crédit with the customer
/// filled in — record_sale, stock and all, offline through the outbox as
/// any sale — and the date follows it (117's set_debt_due, queued behind
/// the sale when the sale itself waits on the phone).
///
/// « Remboursement »: who (the customers who owe) → how much → the
/// summary → « Enregistrer »: repay_customer (117) spreads it over their
/// debts, oldest first, in one transaction.

/// « Dans une semaine » …: 'none', `days:N` or `date:YYYY-MM-DD`.
DateTime? _dueFrom(String due) {
  if (due.startsWith('days:')) {
    final n = int.tryParse(due.substring(5)) ?? 0;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: n));
  }
  if (due.startsWith('date:')) return DateTime.tryParse(due.substring(5));
  return null;
}

String _dateWord(BuildContext context, DateTime d) =>
    DateFormat('d MMMM y', context.trLanguage == 'en' ? 'en' : 'fr_FR').format(d);

/// The reminder, typed for the customer: who is asking, how much, by when.
String creditReminder(BuildContext context,
    {required String customer,
    required String business,
    required String amount,
    DateTime? due}) {
  final hello = context.tr('Bonjour {name}, c\'est {business}.',
      {'name': customer, 'business': business});
  final owed = due == null
      ? context.tr('Il reste {amount} à payer.', {'amount': amount})
      : context.tr('Il reste {amount} à payer avant le {date}.',
          {'amount': amount, 'date': _dateWord(context, due)});
  return '$hello $owed ${context.tr('Merci !')}';
}

/// Opens WhatsApp on the customer's number, or the « send to… » picker
/// when there is none.
Future<void> sendReminder(String? phone, String text) async {
  final url = whatsappUrl(phone, text: text) ?? whatsappShareUrl(text);
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class NewCreditFlow extends StatefulWidget {
  const NewCreditFlow({
    super.key,
    required this.org,
    required this.credit,
    required this.retail,
    this.db,
    this.debtors = const [],
    this.store,
  });

  final OrgSummary org;
  final CreditRepository credit;
  final RetailRepository retail;

  /// Where a credit sale's date waits when the sale is still on the phone.
  final LocalDb? db;

  /// Who owes already — offered by name, with their number.
  final List<DebtorRow> debtors;
  final FlowStore? store;

  @override
  State<NewCreditFlow> createState() => _NewCreditFlowState();
}

class _NewCreditFlowState extends State<NewCreditFlow> {
  static const _uuid = Uuid();
  final _flow = StepFlowController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _label = TextEditingController();
  CountryCode _country = defaultCountry;

  /// 'sum' | 'articles'. An association lends sums only.
  String? _what;
  String _due = 'none';
  String _clientUuid = _uuid.v4();

  /// After an articles sale: it is recorded (or queued) — the summary's
  /// button no longer sells again.
  bool _sold = false;
  bool _dueQueued = false;

  bool get _sums => widget.org.isAssociation;
  NumberFormat get _money => moneyFormat(widget.org.currency);
  double get _value => parseAmount(_amount.text) ?? 0;
  bool get _articles => !_sums && _what == 'articles';

  @override
  void dispose() {
    for (final c in [_customer, _phone, _amount, _label]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _e164 =>
      _phone.text.trim().isEmpty ? null : _country.toE164(_phone.text);

  /// A customer the carnet knows: their number comes with the name.
  void _known() {
    final name = _customer.text.trim().toLowerCase();
    for (final d in widget.debtors) {
      if (d.name.trim().toLowerCase() == name && d.phone != null && _phone.text.isEmpty) {
        _country = countryOfNumber(d.phone!) ?? _country;
        _phone.text = _country.localPart(d.phone!);
      }
    }
    setState(() {});
  }

  Map<String, Object?> _save() => {
        'customer': _customer.text,
        'phone': _phone.text,
        'country': _country.iso,
        'what': _what,
        'amount': _amount.text,
        'label': _label.text,
        'due': _due,
        'uuid': _clientUuid,
      };

  void _restore(Map<String, Object?> a) => setState(() {
        _customer.text = (a['customer'] as String?) ?? '';
        _phone.text = (a['phone'] as String?) ?? '';
        _country = countryByIso(a['country'] as String?);
        _what = a['what'] as String?;
        _amount.text = (a['amount'] as String?) ?? '';
        _label.text = (a['label'] as String?) ?? '';
        _due = (a['due'] as String?) ?? 'none';
        _clientUuid = (a['uuid'] as String?) ?? _uuid.v4();
        _sold = false;
        _dueQueued = false;
      });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueFrom(_due) ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) {
      setState(() => _due = 'date:${CreditRepository.day(picked)}');
    }
  }

  Future<bool> _record() async {
    final due = _dueFrom(_due);
    final name = _customer.text.trim();
    if (!_articles) {
      final debt = await widget.credit.recordCreditSale(
        orgId: widget.org.id,
        customerName: name,
        customerPhone: _e164,
        amount: _value,
        label: _label.text.trim(),
        clientUuid: _clientUuid,
      );
      if (due != null) {
        await widget.credit.setDue(orgId: widget.org.id, dueOn: due, debtId: debt);
      }
      return true;
    }

    // The articles: the « Vente » flow, on Crédit, for this customer.
    if (!_sold) {
      String? saleUuid;
      List<Product> products = const [];
      try {
        products = await widget.retail.products(widget.org.id);
      } catch (_) {
        // Offline: the flow still lets a name be typed.
      }
      if (!mounted) return false;
      await StepFlow.push(
        context,
        SaleFlow(
          orgId: widget.org.id,
          orgName: widget.org.name,
          retail: widget.retail,
          currency: widget.org.currency,
          products: products,
          initialMethod: 'credit',
          farm: widget.org.profile == 'farm',
          customerName: name,
          customerPhone: _e164,
          onSaved: (uuid) => saleUuid = uuid,
        ),
      );
      if (saleUuid == null) return false; // Left without selling.
      _sold = true;
      _clientUuid = saleUuid!;
    }
    if (due != null) await _dateSale(_clientUuid, due);
    return true;
  }

  /// The sale's date: at once when the sale is on the server, else queued
  /// behind it on the phone.
  Future<void> _dateSale(String saleUuid, DateTime due) async {
    try {
      final debt = await widget.credit.setDue(
          orgId: widget.org.id, dueOn: due, saleClientUuid: saleUuid);
      if (debt != null) return;
    } catch (_) {
      // No signal: queued below.
    }
    final db = widget.db;
    if (db == null) return;
    await db.queueDebtDue(
        orgId: widget.org.id,
        saleClientUuid: saleUuid,
        dueOn: CreditRepository.day(due));
    _dueQueued = true;
  }

  void _another() {
    _restore(const {});
    _flow.restart();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = _dueFrom(_due);
    return StepFlow(
      title: context.tr('Nouveau crédit'),
      controller: _flow,
      store: widget.store,
      draft: FlowDraft(
          key: 'credit:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'customer',
          title: context.tr('Pour qui ?'),
          isValid: () => _customer.text.trim().isNotEmpty,
          builder: (_) => CustomerPick(
            controller: _customer,
            known: [for (final d in widget.debtors) d.name],
            onChanged: _known,
          ),
        ),
        FlowStep(
          id: 'phone',
          title: context.tr('Son numéro WhatsApp ?'),
          help: context.tr('Pour lui envoyer un rappel.'),
          optional: true,
          isValid: () => _country.lengthProblem(_phone.text) == null,
          builder: (_) => PhoneField(
            controller: _phone,
            country: _country,
            onCountry: (c) => setState(() => _country = c),
            labelText: context.tr('Téléphone (facultatif)'),
            hintText: '70 12 34 56',
            errorText: _country.lengthProblem(_phone.text),
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'what',
          title: context.tr('Qu\'est-ce qu\'il doit ?'),
          shown: () => !_sums,
          isValid: () => _what != null,
          builder: (_) => FlowChoice<String>(
            options: [
              FlowOption('articles', context.tr('Des articles'),
                  icon: Icons.shopping_basket_outlined,
                  detail: context.tr('Pris maintenant, payés plus tard — le stock bouge')),
              FlowOption('sum', context.tr('Une somme'),
                  icon: Icons.payments_outlined,
                  detail: context.tr('Un prêt, un service, un reste à payer')),
            ],
            value: _what,
            onChanged: (v) => setState(() => _what = v),
          ),
        ),
        FlowStep(
          id: 'amount',
          title: context.tr('Combien ?'),
          shown: () => !_articles,
          isValid: () => _value > 0,
          builder: (_) => FlowNumberField(
            key: const Key('credit-amount'),
            controller: _amount,
            suffix: widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency,
            onChanged: (_) => setState(() {}),
          ),
        ),
        FlowStep(
          id: 'label',
          title: context.tr('C\'est pour quoi ?'),
          shown: () => !_articles,
          isValid: () => _label.text.trim().isNotEmpty,
          builder: (_) => TextField(
            key: const Key('credit-label'),
            controller: _label,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _sums
                  ? context.tr('Cotisation de mars')
                  : context.tr('Prêt, réparation…'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        FlowStep(
          id: 'due',
          title: context.tr('Il paiera quand ?'),
          optional: true,
          builder: (_) => FlowChoice<String>(
            options: [
              FlowOption('none', context.tr('Pas de date')),
              FlowOption('days:7', context.tr('Dans une semaine')),
              FlowOption('days:14', context.tr('Dans deux semaines')),
              FlowOption('days:30', context.tr('Dans un mois')),
              FlowOption(
                  _due.startsWith('date:') ? _due : 'date',
                  _due.startsWith('date:') && due != null
                      ? _dateWord(context, due)
                      : context.tr('Une date précise'),
                  icon: Icons.event_outlined),
            ],
            value: _due,
            onChanged: (v) => v == 'date' || v.startsWith('date:')
                ? _pickDate()
                : setState(() => _due = v),
          ),
        ),
      ],
      summary: (_) => FlowSummary(
        rows: [
          FlowSummaryRow(context.tr('Client'), _customer.text.trim(), step: 'customer'),
          if (_e164 != null) FlowSummaryRow(context.tr('WhatsApp'), _e164!, step: 'phone'),
          if (_articles)
            FlowSummaryRow(context.tr('Quoi'), context.tr('Des articles, choisis à l\'étape suivante'),
                step: 'what')
          else ...[
            FlowSummaryRow(context.tr('Montant'), _money.format(_value),
                step: 'amount', bold: true),
            FlowSummaryRow(context.tr('Pour'), _label.text.trim(), step: 'label'),
          ],
          FlowSummaryRow(context.tr('À payer'),
              due == null ? context.tr('Pas de date') : _dateWord(context, due),
              step: 'due'),
        ],
        footer: Text(
            _articles
                ? context.tr('« Choisir les articles » ouvre la vente, déjà sur Crédit.')
                : context.tr('Il faut du réseau pour enregistrer un crédit.'),
            style: theme.textTheme.bodySmall),
      ),
      saveLabel: _articles && !_sold
          ? context.tr('Choisir les articles')
          : context.tr('Enregistrer le crédit'),
      onSave: _record,
      done: (_) => FlowDone(
        message: _articles
            ? context.tr('Vente à crédit enregistrée pour {name}', {'name': _customer.text.trim()})
            : context.tr('{name} doit {amount}',
                {'name': _customer.text.trim(), 'amount': _money.format(_value)}),
        details: _dueQueued
            ? Text(context.tr('La date partira avec la vente, dès le retour du réseau.'),
                textAlign: TextAlign.center)
            : null,
        actions: [
          if (!_articles)
            FlowAction(
              key: const Key('credit-remind'),
              label: context.tr('Envoyer un rappel sur WhatsApp'),
              icon: Icons.chat_outlined,
              primary: true,
              onPressed: () => sendReminder(
                  _e164,
                  creditReminder(context,
                      customer: _customer.text.trim(),
                      business: widget.org.name,
                      amount: _money.format(_value),
                      due: due)),
            ),
          FlowAction(
            key: const Key('credit-another'),
            label: context.tr('Un autre crédit'),
            icon: Icons.add,
            onPressed: _another,
          ),
        ],
      ),
    );
  }
}

/// « Remboursement »: who → how much → Enregistrer.
class RepayFlow extends StatefulWidget {
  const RepayFlow({
    super.key,
    required this.org,
    required this.credit,
    this.debtors = const [],
    this.customerId,
    this.store,
  });

  final OrgSummary org;
  final CreditRepository credit;

  /// Who owes, as the carnet just read it.
  final List<DebtorRow> debtors;

  /// Opened from a customer's page: that customer, already chosen.
  final String? customerId;
  final FlowStore? store;

  @override
  State<RepayFlow> createState() => _RepayFlowState();
}

class _RepayFlowState extends State<RepayFlow> {
  static const _uuid = Uuid();
  final _amount = TextEditingController();
  late String? _customerId = widget.customerId;
  String _clientUuid = _uuid.v4();
  double? _left;

  NumberFormat get _money => moneyFormat(widget.org.currency);
  double get _value => parseAmount(_amount.text) ?? 0;

  DebtorRow? get _debtor {
    for (final d in widget.debtors) {
      if (d.customerId == _customerId) return d;
    }
    return null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Map<String, Object?> _save() =>
      {'customer': _customerId, 'amount': _amount.text, 'uuid': _clientUuid};

  void _restore(Map<String, Object?> a) => setState(() {
        _customerId = (a['customer'] as String?) ?? widget.customerId;
        _amount.text = (a['amount'] as String?) ?? '';
        _clientUuid = (a['uuid'] as String?) ?? _uuid.v4();
      });

  Future<bool> _record() async {
    _left = await widget.credit.repay(
      orgId: widget.org.id,
      customerId: _customerId!,
      amount: _value,
      clientUuid: _clientUuid,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final debtor = _debtor;
    final owed = debtor?.totalOwed ?? 0;
    return StepFlow(
      title: context.tr('Remboursement'),
      store: widget.store,
      draft: FlowDraft(
          key: 'repay:${widget.org.id}', save: _save, restore: _restore),
      steps: [
        FlowStep(
          id: 'customer',
          title: context.tr('Qui rembourse ?'),
          isValid: () => debtor != null,
          builder: (_) => widget.debtors.isEmpty
              ? Text(context.tr('Personne ne vous doit rien.'),
                  style: theme.textTheme.bodyLarge)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final d in widget.debtors)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: d.customerId == _customerId
                            ? theme.colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          key: Key('repay-customer-${d.customerId}'),
                          minTileHeight: 64,
                          title: Text(d.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          trailing: Text(_money.format(d.totalOwed),
                              style: theme.textTheme.titleMedium),
                          onTap: () => setState(() {
                            _customerId = d.customerId;
                            _amount.clear();
                          }),
                        ),
                      ),
                  ],
                ),
        ),
        FlowStep(
          id: 'amount',
          title: context.tr('Combien ?'),
          help: debtor == null
              ? null
              : context.tr('{name} doit {amount}.',
                  {'name': debtor.name, 'amount': _money.format(owed)}),
          isValid: () => _value > 0 && _value <= owed,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowNumberField(
                key: const Key('repay-amount'),
                controller: _amount,
                suffix: widget.org.currency == 'XOF' ? 'FCFA' : widget.org.currency,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  key: const Key('repay-all'),
                  avatar: const Icon(Icons.done_all, size: 18),
                  label: Text(context.tr('Tout : {amount}', {'amount': _money.format(owed)})),
                  onPressed: () => setState(
                      () => _amount.text = owed == owed.roundToDouble()
                          ? owed.round().toString()
                          : '$owed'),
                ),
              ),
              if (_value > owed) ...[
                const SizedBox(height: 8),
                Text(context.tr('C\'est plus que ce qu\'il doit.'),
                    style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ],
      summary: (_) => FlowSummary(rows: [
        FlowSummaryRow(context.tr('Client'), debtor?.name ?? '', step: 'customer'),
        FlowSummaryRow(context.tr('Il paie'), _money.format(_value),
            step: 'amount', bold: true),
        FlowSummaryRow(context.tr('Il restera'), _money.format(owed - _value)),
      ], footer: Text(context.tr('Les crédits les plus anciens sont payés en premier.'),
          style: theme.textTheme.bodySmall)),
      onSave: _record,
      done: (_) => FlowDone(
        message: context.tr('{name} a payé {amount}',
            {'name': debtor?.name ?? '', 'amount': _money.format(_value)}),
        details: Text(
          (_left ?? 0) <= 0
              ? context.tr('Il ne doit plus rien.')
              : context.tr('Il reste {amount}.', {'amount': _money.format(_left ?? 0)}),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/events/my_tickets.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/phone/country_codes.dart';
import '../common/phone_field.dart';

/// Buying tickets (172), signed in. The owner: « every person buying a
/// ticket should create an account with Marakaj, since the tickets show on
/// the welcome page and open their QR code with no internet; one account
/// buying several tickets writes as many names — there is no point in one
/// person owning several tickets for the same event ». So: the kinds of
/// ticket and how many, then one name per ticket (the first is the
/// account's), a WhatsApp for the organiser, and the request is the
/// account's from the start; « Mes billets » opens on it.
class BuyTicketsScreen extends StatefulWidget {
  const BuyTicketsScreen({super.key, required this.client, required this.slug, this.preview, this.store, this.rpc, this.myName, this.myPhone});

  final SupabaseClient? client;

  /// For the tests: the server's answer to a function, and who is signed in.
  final Future<dynamic> Function(String fn, Map<String, dynamic> params)? rpc;
  final String? myName;
  final String? myPhone;
  final String slug;
  final String? preview;
  final MyTicketsStore? store;

  @override
  State<BuyTicketsScreen> createState() => _BuyTicketsScreenState();
}

class _Kind {
  _Kind(this.id, this.name, this.price, this.left);
  final String id;
  final String name;
  final double price;
  final int? left;
  int qty = 0;
  final names = <TextEditingController>[];
}

class _BuyTicketsScreenState extends State<BuyTicketsScreen> {
  Map<String, dynamic>? _offer;
  String? _problem;
  bool _busy = false;
  String? _error;
  final _kinds = <_Kind>[];
  final _wa = TextEditingController();

  /// The WhatsApp's country, chosen in front of the number (the app's
  /// PhoneField): a buyer from Abidjan or Paris is not turned into +226.
  CountryCode _country = defaultCountry;
  final _txn = TextEditingController();

  String get _me {
    if (widget.myName != null) return widget.myName!.trim();
    final u = widget.client?.auth.currentUser;
    return ((u?.userMetadata?['full_name'] as String?) ?? '').trim();
  }

  Future<dynamic> _call(String fn, Map<String, dynamic> params) {
    final f = widget.rpc;
    if (f != null) return f(fn, params);
    return widget.client!.rpc(fn, params: params);
  }

  bool get _online => widget.rpc != null || widget.client != null;

  @override
  void initState() {
    super.initState();
    // the account's own number, under its country (Supabase keeps it without its « + »)
    var phone = (widget.myPhone ?? widget.client?.auth.currentUser?.phone ?? '').trim();
    if (phone.isNotEmpty) {
      if (!phone.startsWith('+')) phone = '+$phone';
      _country = countryOfNumber(phone) ?? defaultCountry;
      _wa.text = _country.localPart(phone);
    }
    _load();
  }

  @override
  void dispose() {
    for (final k in _kinds) {
      for (final c in k.names) {
        c.dispose();
      }
    }
    _wa.dispose();
    _txn.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_online) {
      setState(() => _problem = context.tr('La billetterie n’est pas disponible.'));
      return;
    }
    try {
      final r = await _call('event_ticket_offer', {'p_slug': widget.slug, 'p_preview': widget.preview ?? ''});
      if (!mounted) return;
      if (r is! Map || r['on'] != true) {
        setState(() => _problem = context.tr('Cet événement ne vend pas de billets.'));
        return;
      }
      final o = Map<String, dynamic>.from(r);
      setState(() {
        _offer = o;
        _kinds
          ..clear()
          ..addAll([
            for (final t in (o['types'] as List? ?? const []))
              _Kind('${(t as Map)['id']}', '${t['name'] ?? ''}', (t['price'] as num?)?.toDouble() ?? 0,
                  (t['left'] as num?)?.toInt()),
          ]);
      });
    } catch (_) {
      if (mounted) setState(() => _problem = context.tr('Pas de réseau : réessayez.'));
    }
  }

  int get _count => _kinds.fold(0, (a, k) => a + k.qty);
  double get _total => _kinds.fold(0.0, (a, k) => a + k.qty * k.price);

  /// One name field per ticket; the very first ticket is the account's.
  void _setQty(_Kind k, int qty) {
    final max = k.left == null ? 20 : (k.left! < 20 ? k.left! : 20);
    qty = qty.clamp(0, max);
    if (_count - k.qty + qty > 20) return;
    setState(() {
      while (k.names.length < qty) {
        final first = _count == 0 && k.names.isEmpty;
        k.names.add(TextEditingController(text: first ? _me : ''));
      }
      while (k.names.length > qty) {
        k.names.removeLast().dispose();
      }
      k.qty = qty;
    });
  }

  String _money(double v) {
    final cur = '${_offer?['currency'] ?? 'XOF'}';
    final n = v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return '$n ${currencySymbol(cur)}';
  }

  Future<void> _send() async {
    if (!_online || _busy) return;
    setState(() => _error = null);
    if (_count == 0) {
      setState(() => _error = context.tr('Choisissez au moins un billet.'));
      return;
    }
    final holders = <Map<String, String>>[];
    final seen = <String>{};
    for (final k in _kinds) {
      for (final n in k.names) {
        final name = n.text.trim();
        if (name.isEmpty) {
          setState(() => _error = context.tr('Un nom par billet : chaque personne a le sien.'));
          return;
        }
        if (!seen.add(name.toLowerCase())) {
          setState(() => _error = context.tr('Chaque billet est pour une personne différente : « {name} » est écrit deux fois.', {'name': name}));
          return;
        }
        holders.add({'type': k.id, 'name': name});
      }
    }
    if (_wa.text.replaceAll(RegExp(r'\D'), '').length < 6) {
      setState(() => _error = context.tr('Votre numéro WhatsApp, pour que l’organisateur vous réponde.'));
      return;
    }
    final waProblem = _country.lengthProblem(_wa.text);
    if (waProblem != null) {
      setState(() => _error = waProblem);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _call('event_ticket_request', {
        'p_slug': widget.slug,
        'p_preview': widget.preview,
        'p_name': holders.first['name'],
        'p_whatsapp': _country.toE164(_wa.text.trim()),
        'p_lines': [
          for (final k in _kinds)
            if (k.qty > 0) {'type': k.id, 'qty': k.qty},
        ],
        'p_txn': _txn.text.trim().isEmpty ? null : _txn.text.trim(),
        'p_holders': holders,
      });
      final id = '${(r as Map)['id']}';
      await widget.store?.keep(id);
      if (!mounted) return;
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        router.go('/billets/$id');
      } else {
        Navigator.of(context).maybePop(id);
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('Pas de réseau : réessayez.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = _offer;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Acheter mes billets')), actions: const [bellRoom]),
      body: _problem != null
          ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(_problem!, textAlign: TextAlign.center)))
          : o == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
                  children: [
                    Text('${o['title'] ?? ''}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text([o['date_fr'], o['place']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                        style: theme.textTheme.bodyMedium),
                    if (o['org_name'] != null)
                      Text(context.tr('Organisé par {name}', {'name': '${o['org_name']}'}), style: theme.textTheme.bodySmall),
                    const SizedBox(height: 16),
                    if (o['open'] == false)
                      Text(context.tr('La vente des billets est terminée.'), style: theme.textTheme.titleMedium)
                    else ...[
                      for (final k in _kinds) ...[
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(k.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                    Text(k.left == 0 ? context.tr('Complet') : _money(k.price)),
                                  ]),
                                ),
                                if (k.left != 0) ...[
                                  IconButton(
                                    key: Key('buy-less-${k.id}'),
                                    tooltip: context.tr('Un de moins'),
                                    onPressed: k.qty == 0 ? null : () => _setQty(k, k.qty - 1),
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  Text('${k.qty}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                  IconButton(
                                    key: Key('buy-more-${k.id}'),
                                    tooltip: context.tr('Un de plus'),
                                    onPressed: () => _setQty(k, k.qty + 1),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ]),
                              for (final (i, c) in k.names.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8, right: 8),
                                  child: TextField(
                                    key: Key('buy-name-${k.id}-$i'),
                                    controller: c,
                                    maxLength: 80,
                                    textCapitalization: TextCapitalization.words,
                                    decoration: InputDecoration(
                                      labelText: context.tr('Nom de la personne · billet {n}', {'n': i + 1}),
                                      counterText: '',
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ],
                      if (_count > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(context.tr('Un nom par billet : chaque personne a le sien.'), style: theme.textTheme.bodySmall),
                        ),
                      Row(children: [
                        Text(context.tr('Total'), style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Text(_money(_total), key: const Key('buy-total'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 14),
                      PhoneField(
                        key: const Key('buy-whatsapp'),
                        controller: _wa,
                        country: _country,
                        onCountry: (c) => setState(() => _country = c),
                        labelText: context.tr('Votre WhatsApp'),
                        errorText: _wa.text.trim().isEmpty ? null : _country.lengthProblem(_wa.text),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _txn,
                        maxLength: 40,
                        decoration: InputDecoration(
                          labelText: context.tr('Numéro de transaction (si vous avez déjà payé)'),
                          counterText: '',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!, key: const Key('buy-error'), style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: FilledButton(
                          key: const Key('buy-send'),
                          onPressed: _busy ? null : _send,
                          child: Text(_busy ? context.tr('Envoi…') : context.tr('Demander mes billets')),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr('Vos places sont gardées {h} heures, le temps de payer l’organisateur. Vos billets s’affichent en haut de votre accueil et s’ouvrent même sans connexion.',
                            {'h': '${o['hold_hours'] ?? 72}'}),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/courier/courier_repository.dart';
import '../../core/format/money.dart';
import '../../core/nav/router.dart';
import '../../core/storefront/storefront_repository.dart';
import '../storefront/shop_style.dart';

/// The livreur's whole world on one page.
///
/// The same address serves every stage of being a courier, because the
/// stages are the server's to say: never registered → the pitch and one
/// button; pending → "à l'étude"; suspended → said in words; approved →
/// two tabs, the board of ready deliveries and their own courses. A job
/// card carries the three things a courier acts on — where to collect
/// (with the itinerary), where to bring (with the itinerary), what to
/// collect at the door — and exactly one button per state.
class CourierScreen extends StatefulWidget {
  const CourierScreen({super.key, required this.courier});

  final CourierRepository courier;

  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen> {
  String? _status;
  List<DeliveryJob> _board = const [];
  List<DeliveryJob> _mine = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

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
    if (!widget.courier.isConfigured) {
      setState(() {
        _error = "L'espace livreur a besoin d'une connexion.";
        _loading = false;
      });
      return;
    }
    try {
      final status = await widget.courier.status();
      var board = const <DeliveryJob>[];
      var mine = const <DeliveryJob>[];
      if (status == 'approved') {
        final results =
            await Future.wait([widget.courier.available(), widget.courier.mine()]);
        board = results[0];
        mine = results[1];
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _board = board;
        _mine = mine;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "L'espace livreur n'a pas pu être chargé. Vérifiez le réseau.";
        _loading = false;
      });
    }
  }

  Future<void> _register() async {
    setState(() => _busy = true);
    try {
      await widget.courier.register();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("L'inscription n'a pas pu partir. Vérifiez le réseau.")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(Future<void> Function() call, String failed) async {
    setState(() => _busy = true);
    try {
      await call();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failed)));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final running = _mine.where((j) => j.isRunning).length;

    return ShopPage(
      title: 'Espace livreur',
      leading: IconButton(
        tooltip: 'Les vitrines',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(Routes.directory),
      ),
      trailing: _status == 'approved'
          ? IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh),
              onPressed: _loading || _busy ? null : _load,
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ShopNotice(
                  text: _error!,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('Réessayer')),
                )
              : switch (_status) {
                  null => _Pitch(busy: _busy, onRegister: _register),
                  'pending' => const ShopNotice(
                      text: 'Votre inscription est à l\'étude. La plateforme '
                          'vous préviendra dès qu\'elle est validée.',
                    ),
                  'suspended' => const ShopNotice(
                      text: 'Votre accès livreur est suspendu. '
                          'Contactez la plateforme.',
                    ),
                  _ => DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          Material(
                            color: ShopStyle.paper,
                            child: TabBar(tabs: [
                              Tab(
                                  text:
                                      'Disponibles${_board.isEmpty ? '' : ' (${_board.length})'}'),
                              Tab(
                                  text:
                                      'Mes courses${running == 0 ? '' : ' ($running)'}'),
                            ]),
                          ),
                          Expanded(
                            child: TabBarView(children: [
                              _JobList(
                                jobs: _board,
                                empty: 'Aucune livraison à prendre pour le '
                                    'moment. Revenez un peu plus tard.',
                                busy: _busy,
                                onOpen: _open,
                                actionsFor: (job) => [
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _act(
                                            () => widget.courier
                                                .take(job.orderId),
                                            'Trop tard : un autre livreur '
                                            "l'a prise."),
                                    child: const Text("J'accepte"),
                                  ),
                                ],
                              ),
                              _JobList(
                                jobs: _mine,
                                empty: 'Aucune course. Prenez-en une dans '
                                    'Disponibles.',
                                busy: _busy,
                                onOpen: _open,
                                actionsFor: (job) => switch (job.status) {
                                  'ready' => [
                                      FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _act(
                                                () => widget.courier.mark(
                                                    job.orderId, 'in_transit'),
                                                "Le retrait n'a pas pu être "
                                                'enregistré.'),
                                        child: const Text('Colis récupéré'),
                                      ),
                                      OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _act(
                                                () => widget.courier
                                                    .release(job.orderId),
                                                'Cette course ne peut plus '
                                                'être remise.'),
                                        child: const Text('Remettre'),
                                      ),
                                    ],
                                  'in_transit' => [
                                      FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _act(
                                                () => widget.courier.mark(
                                                    job.orderId, 'delivered'),
                                                "La livraison n'a pas pu "
                                                'être enregistrée.'),
                                        child: const Text('Livré'),
                                      ),
                                    ],
                                  _ => const [],
                                },
                              ),
                            ]),
                          ),
                        ],
                      ),
                    ),
                },
    );
  }
}

/// What being a livreur is, for somebody who is not one yet.
class _Pitch extends StatelessWidget {
  const _Pitch({required this.busy, required this.onRegister});

  final bool busy;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ColoredBox(
          color: ShopStyle.stone,
          child: ShopWidth(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Livrez pour les\nboutiques du quartier.',
                  style: TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: ShopStyle.ink),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Les boutiques préparent des commandes à livrer. Vous les '
                  'prenez quand vous voulez, vous encaissez le montant à la '
                  'porte et vous réglez la boutique. La plateforme valide '
                  'chaque livreur avant sa première course.',
                  style: TextStyle(
                      fontSize: 16, height: 1.45, color: ShopStyle.ink),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: busy ? null : onRegister,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: ShopStyle.paper))
                      : const Text("M'inscrire comme livreur"),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.jobs,
    required this.empty,
    required this.busy,
    required this.onOpen,
    required this.actionsFor,
  });

  final List<DeliveryJob> jobs;
  final String empty;
  final bool busy;
  final Future<void> Function(String url) onOpen;
  final List<Widget> Function(DeliveryJob) actionsFor;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return ShopNotice(text: empty);
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ShopWidth(
          child: Column(
            children: [
              const SizedBox(height: 20),
              for (final job in jobs)
                _JobCard(
                    job: job, onOpen: onOpen, actions: actionsFor(job)),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }
}

/// One course: collect here, bring there, collect this much.
class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.onOpen,
    required this.actions,
  });

  final DeliveryJob job;
  final Future<void> Function(String url) onOpen;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(job.currency);
    final when = DateFormat('HH:mm', 'fr_FR').format(job.createdAt);
    final phone = (job.phone ?? '').trim();
    final done = job.status != null && !job.isRunning;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: ShopStyle.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Opacity(
        opacity: done ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(job.shopName,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: ShopStyle.ink)),
                ),
                Text('$when · ${money.format(job.total)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ShopStyle.ink)),
              ],
            ),
            const SizedBox(height: 10),
            _Leg(
              icon: Icons.storefront_outlined,
              label: 'Retirer',
              place: (job.shopAddress ?? '').trim().isEmpty
                  ? job.shopName
                  : job.shopAddress!.trim(),
              onRoute: job.shopHasPin
                  ? () => onOpen(directionsUrl(job.shopLat!, job.shopLng!))
                  : null,
            ),
            const SizedBox(height: 6),
            _Leg(
              icon: Icons.home_outlined,
              label: 'Livrer',
              place: (job.dropAddress ?? '').trim().isEmpty
                  ? 'Adresse chez le client'
                  : job.dropAddress!.trim(),
            ),
            if (job.customerName != null || phone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (job.customerName != null) job.customerName!,
                        if (phone.isNotEmpty) phone,
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 14, color: ShopStyle.mist),
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    IconButton(
                      tooltip: 'Appeler',
                      icon: const Icon(Icons.call_outlined, size: 20),
                      onPressed: () => onOpen('tel:$phone'),
                    ),
                    if (whatsappUrl(phone) != null)
                      IconButton(
                        tooltip: 'WhatsApp',
                        icon: const Icon(Icons.chat_outlined, size: 20),
                        onPressed: () => onOpen(whatsappUrl(phone)!),
                      ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text('À encaisser à la porte : ${money.format(job.total)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ShopStyle.mist)),
            if (done) ...[
              const SizedBox(height: 6),
              Text(
                  job.status == 'delivered'
                      ? 'Livrée'
                      : 'Terminée (${job.status})',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ShopStyle.mist)),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({
    required this.icon,
    required this.label,
    required this.place,
    this.onRoute,
  });

  final IconData icon;
  final String label;
  final String place;
  final VoidCallback? onRoute;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: ShopStyle.mist),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$label : $place',
              style: const TextStyle(fontSize: 15, color: ShopStyle.ink)),
        ),
        if (onRoute != null)
          TextButton(onPressed: onRoute, child: const Text('Itinéraire')),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/pay/wave_pay.dart';

/// Where Wave sends the person back (076): it waits for Wave's own word —
/// the webhook, not the return address, decides — and says what happened.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.paymentId, this.issue, this.pay});

  final String paymentId;

  /// 'ok' or 'erreur', as Wave's return address said. A hint only.
  final String? issue;
  final WavePay? pay;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final WavePay? _pay = widget.pay ?? AppScope.read(context)?.wavePay;
  String? _status;
  Timer? _poll;
  int _ticks = 0;

  /// Three seconds apart, for three minutes: Wave's word usually arrives in
  /// a few seconds; after that the order page keeps watching on its own.
  static const _every = Duration(seconds: 3);
  static const _maxTicks = 60;

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(_every, (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    _ticks++;
    final status = await _pay?.status(widget.paymentId);
    if (!mounted) return;
    setState(() => _status = status);
    if (status == 'succeeded' || status == 'failed' || status == 'expired' ||
        _ticks >= _maxTicks) {
      _poll?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _status == 'succeeded';
    final failed = _status == 'failed' || _status == 'expired';
    final gaveUp = !done && !failed && _ticks >= _maxTicks;
    final (icon, title, line) = done
        ? (Icons.check_circle, 'Paiement reçu', 'Merci ! La confirmation est enregistrée.')
        : failed
            ? (Icons.error_outline, 'Paiement non abouti',
                'Rien n\'a été débité. Vous pouvez réessayer.')
            : gaveUp
                ? (Icons.schedule, 'Confirmation en attente',
                    'Wave n\'a pas encore confirmé. Si vous avez payé, la '
                    'commande se mettra à jour toute seule.')
                : (Icons.hourglass_top, 'Confirmation en cours…',
                    widget.issue == 'erreur'
                        ? 'Wave signale un problème ; nous vérifions.'
                        : 'Nous attendons la confirmation de Wave.');
    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!done && !failed && !gaveUp)
                const SizedBox(
                    width: 48, height: 48, child: CircularProgressIndicator())
              else
                Icon(icon,
                    size: 56,
                    color: done
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error),
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(line, textAlign: TextAlign.center),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(Routes.myOrders),
                child: const Text('Continuer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

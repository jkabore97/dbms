import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/access/store_rules.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/pay/wave_pay.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// « Payer avec Wave » and, when Wave's page takes cards for the account,
/// « Payer par carte » (076). Draws nothing until the platform has switched
/// Wave on — and, for an order, until its shop has a payout number — so the
/// screens that hold it keep their old way of paying meanwhile.
class WaveButtons extends StatefulWidget {
  const WaveButtons({
    super.key,
    required this.kind,
    required this.ref,
    this.orgId,
    this.period = 'month',
    this.pay,
    this.onUnavailable,
    this.above,
    this.below,
    this.launch,
  });

  /// Opens Wave's link; the platform's launcher unless a test gives one.
  final Future<bool> Function(Uri uri, {required bool card})? launch;

  /// Drawn with the buttons only when Wave is offered: a choice the payment
  /// needs (the period), a line after them.
  final Widget? above;
  final Widget? below;

  /// 'order', 'pro' or 'spot', and what it names.
  final String kind;
  final String ref;

  /// The shop, for an order: its payout number decides.
  final String? orgId;
  final String period;

  /// Taken from the app scope when not given (tests give one).
  final WavePay? pay;

  /// Drawn instead when Wave is not offered (the old way of paying).
  final Widget? onUnavailable;

  @override
  State<WaveButtons> createState() => _WaveButtonsState();
}

class _WaveButtonsState extends State<WaveButtons> {
  late final WavePay? _pay = widget.pay ?? AppScope.read(context)?.wavePay;
  WaveTerms? _terms;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pay = _pay;
    if (pay == null) {
      setState(() => _terms = const WaveTerms());
      return;
    }
    final terms = await pay.terms(orgId: widget.kind == 'order' ? widget.orgId : null);
    if (mounted) setState(() => _terms = terms);
  }

  bool get _offered {
    final t = _terms;
    if (t == null || !t.on) return false;
    return widget.kind != 'order' || t.shopReady;
  }

  Future<void> _go({required bool card}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final checkout = await _pay!.start(
          kind: widget.kind, ref: widget.ref, card: card, period: widget.period);
      final uri = Uri.parse(checkout.url);
      // Wave: its app, where the PIN is. Card: Wave's page in the browser.
      final launch = widget.launch;
      if (launch != null) {
        await launch(uri, card: card);
      } else {
        await launchUrl(uri,
            mode: card
                ? LaunchMode.platformDefault
                : LaunchMode.externalApplication);
      }
      if (!mounted) return;
      context.push(Routes.paymentOf(checkout.paymentId));
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mara Pro and a spot are digital goods: not sold in the iPhone app
    // (125). An order — a shop's goods, its delivery — is paid as ever.
    if (widget.kind != 'order' && !sellsDigitalInApp) {
      return const SizedBox.shrink();
    }
    if (_terms == null) return const SizedBox.shrink();
    if (!_offered) return widget.onUnavailable ?? const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.above != null) ...[widget.above!, const SizedBox(height: 10)],
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _go(card: false),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.phone_iphone_outlined),
            label: Text(context.tr('Payer avec Wave'), style: const TextStyle(fontSize: 16)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1DC4FF),
              foregroundColor: const Color(0xFF0B1F33),
            ),
          ),
        ),
        if (_terms!.card) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _go(card: true),
              icon: const Icon(Icons.credit_card_outlined),
              label: Text(context.tr('Payer par carte')),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (widget.below != null) ...[const SizedBox(height: 12), widget.below!],
      ],
    );
  }
}

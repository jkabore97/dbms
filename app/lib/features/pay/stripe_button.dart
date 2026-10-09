import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/access/plan_terms.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/pay/wave_pay.dart';
import '../../core/theme/kaj_theme.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// « S'abonner par carte » — Kaj Pro as a Stripe subscription (082).
///
/// Drawn only when the app was built with the Worker (PAY_URL) and the
/// platform has switched the card on (plan_terms().stripe_on). The price on
/// the button is the platform's, in FCFA; Stripe charges it in dollars
/// (121), converted by the database at the platform's rate — the line under
/// the button says the same cents, read from plan_terms(), never computed
/// here. Stripe's page opens in this tab on the web and comes back to
/// `/o/<id>/kaj-pro?stripe=ok`.
class StripeCardButton extends StatefulWidget {
  const StripeCardButton({
    super.key,
    required this.orgId,
    required this.terms,
    required this.period,
    this.pay,
    this.launch,
  });

  final String orgId;
  final PlanTerms terms;
  final String period;

  /// Taken from the app scope when not given (tests give one).
  final WavePay? pay;

  /// Opens Stripe's page; the platform's launcher unless a test gives one.
  final Future<bool> Function(Uri uri)? launch;

  @override
  State<StripeCardButton> createState() => _StripeCardButtonState();
}

class _StripeCardButtonState extends State<StripeCardButton> {
  late final WavePay? _pay = widget.pay ?? AppScope.read(context)?.wavePay;
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await _pay!
          .subscribeByCard(orgId: widget.orgId, period: widget.period);
      final uri = Uri.parse(url);
      final launch = widget.launch;
      if (launch != null) {
        await launch(uri);
      } else {
        await launchUrl(uri,
            mode: LaunchMode.platformDefault,
            webOnlyWindowName: kIsWeb ? '_self' : null);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pay = _pay;
    if (pay == null || !pay.compiledIn || !widget.terms.stripeOn) {
      return const SizedBox.shrink();
    }
    final year = widget.period == 'year';
    final price = NumberFormat.decimalPattern('fr_FR')
        .format(year ? widget.terms.priceYear : widget.terms.priceMonth);
    final cents = year ? widget.terms.stripeUsdYearCents : widget.terms.stripeUsdMonthCents;
    final usd = cents == null
        ? null
        : NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2)
            .format(cents / 100);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('stripe-card'),
            onPressed: _busy ? null : _go,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.credit_card),
            label: Text(
              "S'abonner par carte · $price F / ${year ? 'an' : 'mois'}",
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: kInk,
              foregroundColor: kPaper,
            ),
          ),
        ),
        if (usd != null) ...[
          const SizedBox(height: 6),
          Text(
            year
                ? context.tr('≈ {usd} par an, payé en dollars', {'usd': usd})
                : context.tr('≈ {usd} par mois, payé en dollars', {'usd': usd}),
            key: const Key('stripe-usd'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'Visa, Mastercard. Renouvelé chaque ${year ? context.tr('année') : 'mois'}, '
          'annulable à tout moment. Paiement sécurisé par Stripe.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: kMist),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

/// For a business already paying by card: where it stands, and Stripe's
/// own page to change the card or cancel. Nothing when there is none.
class StripeManage extends StatefulWidget {
  const StripeManage({super.key, required this.orgId, this.pay, this.launch});

  final String orgId;
  final WavePay? pay;
  final Future<bool> Function(Uri uri)? launch;

  @override
  State<StripeManage> createState() => _StripeManageState();
}

class _StripeManageState extends State<StripeManage> {
  late final WavePay? _pay = widget.pay ?? AppScope.read(context)?.wavePay;
  CardSubscription? _sub;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sub = await _pay?.cardSubscription(widget.orgId);
    if (mounted) setState(() => _sub = sub);
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(await _pay!.cardPortal(widget.orgId));
      final launch = widget.launch;
      if (launch != null) {
        await launch(uri);
      } else {
        await launchUrl(uri,
            mode: LaunchMode.platformDefault,
            webOnlyWindowName: kIsWeb ? '_self' : null);
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _sub;
    final pay = _pay;
    if (sub == null || pay == null || !pay.compiledIn) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final until = sub.until == null
        ? ''
        : DateFormat('d MMMM yyyy', intlLocale()).format(sub.until!.toLocal());
    final line = !sub.active
        ? context.tr('Abonnement par carte arrêté.')
        : sub.cancelAtEnd
            ? context.tr('Payé par carte jusqu\'au {until}, puis arrêté.', {'until': until})
            : context.tr('Payé par carte, renouvelé le {until}.', {'until': until});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(line,
            key: const Key('stripe-status'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('stripe-manage'),
          onPressed: _busy ? null : _open,
          icon: const Icon(Icons.credit_card_outlined),
          label: Text(context.tr('Gérer la carte ou annuler')),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/access/plan_terms.dart';
import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/motion.dart';
import '../account/pro_sheet.dart';

/// Kaj and Kaj Pro, side by side (`/o/<id>/kaj-pro`).
///
/// The one door to Pro: the « Pro » strip on every page, every badged tool
/// and Compte open it. The month or year at the top, then what each plan
/// gives, row by row — what is free for everyone, what Pro adds, and the
/// limits Pro lifts — read from the platform's own terms (066), so the page
/// says exactly what the database will enforce. The foot is how to pay
/// (ProPayPanel): by card, by Wave, or by hand.
class ProPlansScreen extends StatefulWidget {
  const ProPlansScreen({
    super.key,
    required this.org,
    required this.terms,
    required this.admin,
    this.cardButton,
    this.cardManage,
    this.stripeReturn,
    this.onPaid,
  });

  final OrgSummary org;
  final PlanTerms terms;
  final AdminRepository admin;

  /// « Payer par carte » (Stripe), when the platform has opened it; given
  /// the period chosen at the top.
  final Widget Function(String period)? cardButton;

  /// For a Pro business paying by card: Stripe's page to change it.
  final Widget? cardManage;

  /// `?stripe=` on the way back from Stripe: 'ok' or 'annule'.
  final String? stripeReturn;

  /// Asked to read the business again once Stripe says it is paid (the
  /// webhook may land a few seconds after the owner).
  final VoidCallback? onPaid;

  @override
  State<ProPlansScreen> createState() => _ProPlansScreenState();
}

/// One line of the comparison: what it is, what Free gives, what Pro gives.
/// A null cell is « not included »; `true` is a tick; a string says how much.
class PlanRow {
  const PlanRow(this.label, this.free, this.pro);

  final String label;
  final Object? free;
  final Object? pro;
}

class _ProPlansScreenState extends State<ProPlansScreen> {
  String _period = 'year';
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    final onPaid = widget.onPaid;
    if (widget.stripeReturn == 'ok' && !widget.org.isPro && onPaid != null) {
      for (final s in const [3, 10, 30]) {
        _timers.add(Timer(Duration(seconds: s), onPaid));
      }
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  String _money(int amount) =>
      '${NumberFormat.decimalPattern('fr_FR').format(amount)} F';

  /// Months offered by paying for the year, when the year costs less.
  int get _monthsOffered {
    final t = widget.terms;
    if (t.priceMonth <= 0) return 0;
    final saved = t.priceMonth * 12 - t.priceYear;
    return saved <= 0 ? 0 : (saved / t.priceMonth).floor();
  }

  static List<(String, List<PlanRow>)> rowsFor(PlanTerms t) =>
      ProPlansScreenRows.of(t);


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.terms;
    final org = widget.org;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final price = _period == 'year' ? t.priceYear : t.priceMonth;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: kMist);

    return Scaffold(
      appBar: AppBar(title: const Text('Mara Pro')),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 20, vertical: 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.stripeReturn == 'ok' || widget.stripeReturn == 'annule') ...[
                    _Returned(
                      paid: widget.stripeReturn == 'ok',
                      active: org.isPro,
                    ),
                    const SizedBox(height: 18),
                  ],
                  Reveal(
                    child: Column(
                      children: [
                        Text(
                          org.isPro
                              ? 'Vous êtes sur Mara Pro'
                              : 'Faites grandir ${org.name}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          org.isPro
                              ? 'Tous les outils ci-dessous sont ouverts.'
                              : 'Mara reste gratuit pour le quotidien. Mara Pro '
                                  'ajoute la livraison, le paiement en ligne et '
                                  'les outils d\'une entreprise qui grandit.',
                          textAlign: TextAlign.center,
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  if (!org.isPro) ...[
                    const SizedBox(height: 22),
                    Center(
                      child: SegmentedButton<String>(
                        key: const Key('pro-period'),
                        segments: [
                          const ButtonSegment(value: 'month', label: Text('Mensuel')),
                          ButtonSegment(
                            value: 'year',
                            label: Text(_monthsOffered > 0
                                ? 'Annuel · $_monthsOffered mois offerts'
                                : 'Annuel'),
                          ),
                        ],
                        selected: {_period},
                        onSelectionChanged: (v) =>
                            setState(() => _period = v.first),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _Header(
                    proPrice: org.isPro
                        ? null
                        : '${_money(price)} / ${_period == 'year' ? 'an' : 'mois'}',
                  ),
                  for (final (title, rows) in rowsFor(t)) ...[
                    const SizedBox(height: 18),
                    ScrollReveal(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          title.toUpperCase(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    KajCard(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, r) in rows.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _Row(row: r),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (org.isPro && widget.cardManage != null) widget.cardManage!,
                  if (!org.isPro)
                    ProPayPanel(
                      org: org,
                      terms: t,
                      admin: widget.admin,
                      canRequest: org.isAdmin,
                      period: _period,
                      showFeatures: false,
                      top: widget.cardButton?.call(_period),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The way back from Stripe: paid (Pro on its way, or already on), or
/// cancelled (nothing taken).
class _Returned extends StatelessWidget {
  const _Returned({required this.paid, required this.active});

  final bool paid;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = !paid
        ? 'Paiement annulé : rien n\'a été prélevé.'
        : active
            ? 'Merci ! Mara Pro est actif.'
            : 'Merci ! Paiement reçu — Mara Pro s\'active dans quelques secondes.';
    return Container(
      key: const Key('stripe-returned'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: paid ? kInk : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(paid ? Icons.check_circle_outline : Icons.info_outline,
              color: paid ? kPaper : kInk),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: paid ? kPaper : kInk)),
          ),
          if (paid && !active)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: kPaper),
            ),
        ],
      ),
    );
  }
}

/// The columns' heads: Kaj and Kaj Pro, Pro's price under its name.
class _Header extends StatelessWidget {
  const _Header({this.proPrice});

  final String? proPrice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(flex: 5, child: SizedBox()),
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Text('Mara', style: theme.textTheme.titleSmall),
              Text('Gratuit', style: theme.textTheme.bodySmall?.copyWith(color: kMist)),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: kInk,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('Mara Pro',
                    style: theme.textTheme.titleSmall?.copyWith(color: kPaper)),
                if (proPrice != null)
                  Text(proPrice!,
                      key: const Key('pro-price'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: kPaper)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final PlanRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(Object? v, {required bool pro}) {
      if (v == true) {
        return Icon(Icons.check, size: 20, color: pro ? kInk : kMist);
      }
      if (v == null) return const Text('—', style: TextStyle(color: kMist));
      return Text('$v',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: pro ? FontWeight.w700 : FontWeight.w400,
            color: pro ? kInk : kMist,
          ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(row.label, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 2, child: Center(child: cell(row.free, pro: false))),
          Expanded(flex: 3, child: Center(child: cell(row.pro, pro: true))),
        ],
      ),
    );
  }
}

/// The whole comparison, from the platform's terms — public so a test can
/// read it without drawing the page.
class ProPlansScreenRows {
  static List<(String, List<PlanRow>)> of(PlanTerms t) => [
        (
          'Pour tous',
          const [
            PlanRow('Caisse, articles et stock', true, true),
            PlanRow('Carnet de crédit et reçus', true, true),
            PlanRow('Vitrine en ligne et commandes à retirer', true, true),
            PlanRow('Logo de la boutique', true, true),
            PlanRow('Alertes de nouvelles commandes', true, true),
          ],
        ),
        (
          'Avec Mara Pro',
          [for (final f in t.proFeatures) PlanRow(PlanTerms.labelOf(f), null, true)],
        ),
        (
          'Sans limite',
          [
            PlanRow('Comptes de l\'équipe', '${t.freeMaxStaff}', 'Illimité'),
            PlanRow('Factures par mois', '${t.freeMaxInvoicesMonth}', 'Illimité'),
            PlanRow('Photos', '${t.freeMaxPhotos}', 'Illimité'),
            PlanRow('Historique', '${t.freeHistoryMonths} mois', 'Complet'),
            const PlanRow('Mise en avant offerte', null, '1 par mois'),
          ],
        ),
      ];
}


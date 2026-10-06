import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/models.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/router.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import 'cauri_icon.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// « Mes cauris » (084): what the business has earned, how, and how to
/// earn more.
///
/// The wallet first, counting up as it opens — a number that moves is a
/// number people look at. Then this week's score (the league's, 086),
/// the ways to earn as the platform set them, the business's own code for
/// those it brings in, and the history line by line, so every cauri can
/// be traced to what earned it.
class CaurisScreen extends StatefulWidget {
  const CaurisScreen({super.key, required this.org, required this.cauris});

  final OrgSummary org;
  final CaurisRepository cauris;

  @override
  State<CaurisScreen> createState() => _CaurisScreenState();
}

class _CaurisScreenState extends State<CaurisScreen> {
  CaurisWallet? _wallet;
  bool _loading = true;
  String? _error;
  final _code = TextEditingController();
  bool _savingCode = false;
  String? _codeLine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.cauris.milestones(widget.org.id);
      final w = await widget.cauris.wallet(widget.org.id);
      if (!mounted) return;
      setState(() {
        _wallet = w;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _saveCode() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _savingCode = true;
      _codeLine = null;
    });
    try {
      final name = await widget.cauris.setReferral(widget.org.id, _code.text);
      if (!mounted) return;
      setState(() => _codeLine = 'Merci ! $name est votre parrain.');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _codeLine = describeError(e));
    } finally {
      if (mounted) setState(() => _savingCode = false);
    }
  }

  Future<void> _share(String code) async {
    final text = 'Rejoignez Mara, les boutiques près de chez vous. Quand on '
        'vous demande qui vous a parrainé, donnez le code « $code ».';
    await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = _wallet;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Mes cauris'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_loading && w == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (w == null)
              Text(context.tr('Les cauris ne sont pas encore ouverts pour cette entreprise.'))
            else ...[
              _Wallet(wallet: w),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('open-league'),
                onPressed: () => context.push(Routes.inside(widget.org.id, 'classement')),
                icon: const Icon(Icons.emoji_events_outlined),
                label: Text(context.tr('Classement de la semaine · +{week}', {'week': w.week})),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('open-academy'),
                onPressed: () => context.push(Routes.inside(widget.org.id, 'academie')),
                icon: const Icon(Icons.school_outlined),
                label: Text(context.tr('Apprendre et gagner · Académie Mara')),
              ),
              const SizedBox(height: 22),
              _label(theme, 'Comment gagner des cauris'),
              KajCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, r) in w.rules.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(r.label),
                        subtitle: r.dailyCap == null
                            ? null
                            : Text(context.tr('jusqu\'à {dailyCap} par jour', {'dailyCap': r.dailyCap})),
                        trailing: Text(context.tr('+{points}', {'points': r.points}),
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _label(theme, 'Parrainez une entreprise'),
              KajCard(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Votre code : « ${w.referralCode ?? '—'} ». Une entreprise '
                        'qui le donne en arrivant et qui décolle (vitrine '
                        'complète, 3 commandes) vous rapporte des cauris.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (w.referralCode != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => _share(w.referralCode!),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: Text(context.tr('Envoyer sur WhatsApp')),
                          ),
                        ),
                      ],
                      if (!w.referred) ...[
                        const SizedBox(height: 16),
                        Text(context.tr('On vous a parrainé ?'),
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('referral-code'),
                                controller: _code,
                                enabled: !_savingCode,
                                decoration: InputDecoration(
                                  hintText: context.tr('Le code de votre parrain'),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _savingCode ? null : _saveCode,
                              child: Text(context.tr('Valider')),
                            ),
                          ],
                        ),
                      ],
                      if (_codeLine != null) ...[
                        const SizedBox(height: 6),
                        Text(_codeLine!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _label(theme, 'Historique'),
              if (w.history.isEmpty)
                Text(context.tr('Pas encore de cauris. La première commande terminée en rapporte.'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: kMist))
              else
                KajCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, h) in w.history.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(h.label),
                          subtitle: Text([
                            if (h.at != null)
                              DateFormat('d MMM, HH:mm', 'fr_FR')
                                  .format(h.at!.toLocal()),
                            if (h.note != null) h.note!,
                          ].join(' · ')),
                          trailing: Text(
                            h.delta > 0 ? context.tr('+{delta}', {'delta': h.delta}) : context.tr('{delta}', {'delta': h.delta}),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: h.delta > 0
                                  ? maraGreen
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text.toUpperCase(),
            style: theme.textTheme.labelMedium
                ?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w700)),
      );
}

/// The wallet: the balance counting up, this week's score, the expiry.
class _Wallet extends StatelessWidget {
  const _Wallet({required this.wallet});

  final CaurisWallet wallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = KajMotion.reduced(context);
    return Container(
      key: const Key('cauris-wallet'),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: maraIndigo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CauriIcon(size: 34),
              const SizedBox(width: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: wallet.balance.toDouble()),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  NumberFormat.decimalPattern('fr_FR').format(v.round()),
                  key: const Key('cauris-balance'),
                  style: theme.textTheme.displaySmall?.copyWith(
                      color: maraCream, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('cauris',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: maraCream.withValues(alpha: 0.8))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            context.tr('Cette semaine : +{week}', {'week': wallet.week}),
            key: const Key('cauris-week'),
            style: theme.textTheme.titleSmall?.copyWith(color: maraGold),
          ),
          if (wallet.expiresOn != null && wallet.balance > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Utilisez-les ou gagnez-en d\'autres avant le '
              '${DateFormat('d MMMM yyyy', 'fr_FR').format(wallet.expiresOn!)} : '
              'sans mouvement pendant 6 mois, ils expirent.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: maraCream.withValues(alpha: 0.75)),
            ),
          ],
        ],
      ),
    );
  }
}

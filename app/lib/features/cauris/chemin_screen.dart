import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/access/plan_terms.dart';
import '../../core/auth/models.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/cauris/feature_states.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import 'cauri_icon.dart';
import 'path_card.dart';
import 'unlock_sheet.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';

/// « Mon chemin » (097): the one page for how the business grows on Mara.
///
/// The wallet first, counting up. Then the four stages — the ones walked
/// folded with a tick, the current one open with every step and the next
/// lit, the ones ahead a locked line each. Then the tools the path opens,
/// what the cauris buy, the business's own code for those it brings in,
/// the league from the last stage, and — folded — the rules and the
/// history, so every cauri can still be traced to what earned it.
///
/// A business off the path (no path_state) still reads its wallet here.
class CheminScreen extends StatefulWidget {
  const CheminScreen({
    super.key,
    required this.org,
    required this.cauris,
    this.features,
    this.initialPart,
    this.fromTill = false,
  });

  final OrgSummary org;
  final CaurisRepository cauris;

  /// The section to open on: 'depenser' or 'parrainer' (a step of the last
  /// stage, from the home's card).
  final String? initialPart;

  /// Opened from the home with the till: a step done at the till goes back
  /// there and opens the sale sheet (pops with [pathSellResult]).
  final bool fromTill;

  /// The cauris prices; the session's unless a test gives its own.
  final FeatureStates? features;

  @override
  State<CheminScreen> createState() => _CheminScreenState();
}

class _CheminScreenState extends State<CheminScreen> {
  PathState? _path;
  CaurisWallet? _wallet;
  bool _loading = true;
  String? _error;
  final _code = TextEditingController();
  bool _savingCode = false;
  String? _codeLine;

  /// Where a step of the last stage is done on this very page.
  final _spendKey = GlobalKey();
  final _referralKey = GlobalKey();

  /// The section asked for is shown once, after the first read.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(target,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  void _scrollToPart() {
    if (_scrolled || widget.initialPart == null) return;
    _scrolled = true;
    final key = switch (widget.initialPart) {
      'parrainer' => _referralKey,
      'depenser' => _spendKey,
      _ => null,
    };
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(key);
    });
  }

  String get _dateLocale => context.trLanguage == 'en' ? 'en' : 'fr_FR';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  FeatureStates? get _features =>
      widget.features ??
      AppScope.read(context)?.session.featuresFor(widget.org.id);

  Future<void> _load() async {
    // Read before the first await: a context is not for after a gap.
    final session = AppScope.read(context)?.session;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.cauris.milestones(widget.org.id);
      final path = await widget.cauris.pathState(widget.org.id);
      final w = await widget.cauris.wallet(widget.org.id);
      // What the cauris buy, from the same moment as the wallet above
      // (108): the session's copy could be minutes behind it.
      await session?.reloadFeatures(widget.org.id);
      if (!mounted) return;
      setState(() {
        _path = path;
        _wallet = w;
        _loading = false;
      });
      _scrollToPart();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _go(PathStep s) async {
    if (s.go == 'chemin') {
      await _scrollTo(s.key == 'referral' ? _referralKey : _spendKey);
      return;
    }
    // At the till: back to the home that opened this page, which opens the
    // sale sheet; from anywhere else, a word saying where.
    final nav = Navigator.of(context);
    await openPathStep(context, widget.org, s,
        onHere: widget.fromTill && nav.canPop()
            ? () => nav.pop(pathSellResult)
            : null);
    if (mounted && s.go.isNotEmpty) await _load();
  }

  Future<void> _spend(String feature) async {
    await UnlockSheet.open(context, org: widget.org, feature: feature);
    if (mounted) await _load();
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
      setState(() => _codeLine = context.tr('Merci ! {name} est votre parrain.', {'name': name}));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _codeLine = describeError(e));
    } finally {
      if (mounted) setState(() => _savingCode = false);
    }
  }

  Future<void> _share(String code) async {
    final text = context.tr(
        'Rejoignez Mara, les boutiques près de chez vous. Quand on vous demande qui vous a parrainé, donnez le code « {code} ».',
        {'code': code});
    await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _path;
    final w = _wallet;
    return Scaffold(
      // An association has no path (097), only the wallet Mara fills (100).
      appBar: AppBar(
          actions: const [bellRoom],
          title: Text(widget.org.isAssociation
              ? context.tr('Mes cauris')
              : context.tr('Mon chemin'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_loading && p == null && w == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (p == null && w == null)
              Text(context.tr('Les cauris ne sont pas encore ouverts pour cette entreprise.'))
            else ...[
              // The wallet is the admins' (path_state says null to the
              // others).
              if ((p?.balance ?? w?.balance) case final balance?) ...[
                _Wallet(
                  balance: balance,
                  week: p?.week ?? w?.week ?? 0,
                  expiresOn: w?.expiresOn,
                  promo: w?.promo ?? _features?.promo ?? const [],
                  // An association earns nothing (084): no week to count.
                  showWeek: !widget.org.isAssociation,
                  locale: _dateLocale,
                ),
                const SizedBox(height: 22),
              ],
              if (p != null) ...[
                for (var n = 1; n <= 4; n++)
                  _Stage(
                    n: n,
                    path: p,
                    farm: widget.org.profile == 'farm',
                    onGo: _go,
                  ),
                if (p.finished)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(context.tr('Chemin terminé : bravo !'),
                        key: const Key('chemin-finished'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: maraGreen, fontWeight: FontWeight.w800)),
                  ),
                const SizedBox(height: 22),
                _label(theme, context.tr('Vos outils')),
                KajCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, t) in _pathTools.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _ToolRow(org: widget.org, tool: t, path: p),
                      ],
                    ],
                  ),
                ),
              ],
              // An association does not race nor earn (084): no league, no
              // referral — what Mara gave it, and what that buys.
              if (!widget.org.isAssociation) ..._league(theme, p, w),
              ..._spending(theme),
              if (w != null) ...[
                if (!widget.org.isAssociation) ...[
                  const SizedBox(height: 22),
                  _label(theme, context.tr('Parrainer'), key: _referralKey),
                  _referral(theme, w),
                ],
                const SizedBox(height: 22),
                _details(theme, w, p),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The week's race, from the last stage only — and « Bientôt » while the
  /// business's league has too few racing to be a race. A business off
  /// the path keeps its plain door.
  List<Widget> _league(ThemeData theme, PathState? p, CaurisWallet? w) {
    if (p != null && p.stage < 4) return const [];
    final week = p?.week ?? w?.week ?? 0;
    final open = p == null || p.leagueOpen;
    return [
      const SizedBox(height: 22),
      _label(theme, context.tr('Classement')),
      if (open)
        OutlinedButton.icon(
          key: const Key('chemin-league'),
          onPressed: () => context.push(Routes.inside(widget.org.id, 'classement')),
          icon: const Icon(Icons.emoji_events_outlined),
          label: Text(context.tr('Classement de la semaine · +{week}', {'week': week})),
        )
      else
        Container(
          key: const Key('chemin-league-soon'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.tr('Bientôt, quand votre quartier sera là'),
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
    ];
  }

  /// The path's tools, less those Mara's switchboard hid here (104).
  List<PathTool> get _pathTools {
    final access = AppScope.read(context)?.session.accessFor(widget.org.id);
    return [
      for (final t in pathTools)
        if (!(access?.isHidden(t.key) ?? false)) t,
    ];
  }

  /// What the cauris buy: each Pro tool's price, or how long it stays open.
  List<Widget> _spending(ThemeData theme) {
    final f = _features;
    if (f == null || f.isPro || f.tools.isEmpty) return const [];
    // Only the tools this kind of business has (an association: none of
    // the shop's analyses, no delivery — 099), and none Mara's switchboard
    // hid here (104): no cauris for a door that is not drawn.
    final access = AppScope.read(context)?.session.accessFor(widget.org.id);
    final tools = [
      for (final e in f.tools.entries)
        if (PlanTerms.fits(e.key, widget.org.profile) &&
            !(access?.isHidden(e.key) ?? false))
          e,
    ]..sort((a, b) => a.value.cost.compareTo(b.value.cost));
    if (tools.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      _label(theme, context.tr('Dépenser mes cauris'), key: _spendKey),
      KajCard(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, e) in tools.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                key: Key('chemin-spend-${e.key}'),
                title: Text(e.key == 'pro_all'
                    ? context.tr('Mara Pro complet : tous les outils, sans limite')
                    : PlanTerms.labelOf(e.key)),
                subtitle: e.value.until != null
                    ? Text(e.value.gift
                        // Opened by Mara, not with the business's cauris.
                        ? context.tr('Offert par Mara jusqu\'au {date}', {
                            'date': DateFormat('d MMMM', _dateLocale)
                                .format(e.value.until!.toLocal()),
                          })
                        : context.tr('Ouvert jusqu\'au {date}', {
                            'date': DateFormat('d MMMM', _dateLocale)
                                .format(e.value.until!.toLocal()),
                          }))
                    // The wait of a new business, with its day (108).
                    : e.value.waitsDays != null
                        ? Text(
                            '${UnlockSheet.waitWords(context, e.value.waitsDays!)}. '
                            '${UnlockSheet.waitDay(context, e.value.waitsDays!)}',
                            key: Key('chemin-wait-${e.key}'))
                        : null,
                trailing: e.value.until != null
                    ? const Icon(Icons.lock_open, color: maraGreen)
                    : CaurisAmount(e.value.cost,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                onTap: () => _spend(e.key),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _referral(ThemeData theme, CaurisWallet w) => KajCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // What it pays, first and big.
              Row(
                children: [
                  const CauriIcon(size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('+{points} cauris par entreprise parrainée',
                          {'points': w.referralPoints}),
                      key: const Key('referral-points'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('Quand elle a sa vitrine complète et 3 commandes terminées.'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(context.tr('Votre code'), style: theme.textTheme.labelLarge),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(w.referralCode ?? '—',
                        key: const Key('referral-own-code'),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                ],
              ),
              // Who was brought in, and how far each is.
              for (final r in w.referrals) ...[
                const SizedBox(height: 10),
                Row(
                  key: Key('referral-${r.name}'),
                  children: [
                    Icon(r.paid ? Icons.check_circle : Icons.hourglass_top,
                        color: r.paid ? Colors.green.shade600 : kMist, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r.name, style: theme.textTheme.bodyMedium)),
                    Text(
                      r.paid
                          ? context.tr('+{points} reçus', {'points': w.referralPoints})
                          : context.tr('Vitrine {score} % · {orders}/3 commandes',
                              {'score': r.score, 'orders': r.orders}),
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ],
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
                      style: FilledButton.styleFrom(
                          backgroundColor: maraCaramel, foregroundColor: maraDeep),
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
      );

  /// The rules and the history, folded: there to trace a cauri, not to
  /// read every day.
  Widget _details(ThemeData theme, CaurisWallet w, PathState? p) {
    // What a step of the path pays, so every cauri is traced to a rule.
    final rewards = [
      for (final s in p?.steps ?? const <PathStep>[])
        if (s.reward > 0) s.reward,
    ]..sort();
    return Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('chemin-details'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text(context.tr('Détails'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          // An association earns nothing (084): no rules to earn by, only
          // what Mara gave and what it spent.
          subtitle: Text(widget.org.isAssociation
              ? context.tr('Historique')
              : context.tr('Comment gagner des cauris · historique')),
          children: [
            if (!widget.org.isAssociation) ...[
              KajCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (rewards.isNotEmpty)
                      ListTile(
                        key: const Key('chemin-rule-path'),
                        dense: true,
                        title: Text(rewards.first == rewards.last
                            ? context.tr('Étapes du chemin : {n} cauris chacune',
                                {'n': rewards.first})
                            : context.tr('Étapes du chemin : {min} à {max} cauris chacune',
                                {'min': rewards.first, 'max': rewards.last})),
                      ),
                    for (final (i, r) in w.rules.indexed) ...[
                      if (i > 0 || rewards.isNotEmpty) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(caurisText(context, r.label)),
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
              const SizedBox(height: 16),
            ],
            _label(theme, context.tr('Historique')),
            if (w.history.isEmpty)
              Text(
                  widget.org.isAssociation
                      ? context.tr('Pas encore de cauris.')
                      : context.tr('Pas encore de cauris. Votre premier article en vente en rapporte.'),
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
                        title: Text(caurisText(context, h.label)),
                        subtitle: Text([
                          if (h.at != null)
                            DateFormat(context.tr('d MMM, HH:mm'), _dateLocale)
                                .format(h.at!.toLocal()),
                          if (h.note != null) caurisText(context, h.note!),
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
        ),
      );
  }

  Widget _label(ThemeData theme, String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text.toUpperCase(),
            style: theme.textTheme.labelMedium
                ?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w700)),
      );
}

/// The wallet: the balance counting up, this week's score, the expiry.
class _Wallet extends StatelessWidget {
  const _Wallet({
    required this.balance,
    required this.week,
    this.expiresOn,
    this.promo = const [],
    this.showWeek = true,
    this.locale = 'fr_FR',
  });

  final bool showWeek;

  final int balance;
  final int week;
  final DateTime? expiresOn;

  /// What Mara gave to spend before a day (100): « dont 200 à utiliser
  /// avant le 30/11 ».
  final List<PromoLot> promo;

  /// The dates' and numbers' language.
  final String locale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = KajMotion.reduced(context);
    return Container(
      key: const Key('cauris-wallet'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: maraDeep,
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
                tween: Tween(begin: 0, end: balance.toDouble()),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  NumberFormat.decimalPattern(locale).format(v.round()),
                  key: const Key('cauris-balance'),
                  style: theme.textTheme.displaySmall?.copyWith(
                      color: maraPaper, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(context.tr('cauris'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: maraPaper.withValues(alpha: 0.8))),
              ),
            ],
          ),
          for (final p in promo)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.tr('dont {n} à utiliser avant le {date}', {
                  'n': p.points,
                  'date': DateFormat('dd/MM', locale).format(p.until),
                }),
                key: const Key('cauris-promo'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: maraPaper, fontWeight: FontWeight.w700),
              ),
            ),
          if (showWeek) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('Cette semaine : +{week}', {'week': week}),
              key: const Key('cauris-week'),
              style: theme.textTheme.titleSmall?.copyWith(color: maraCaramel),
            ),
          ],
          if (expiresOn != null && balance > 0) ...[
            const SizedBox(height: 4),
            Text(
              context.tr(
                  'Utilisez-les ou gagnez-en d\'autres avant le {date} : sans mouvement pendant 6 mois, ils expirent.',
                  {'date': DateFormat(context.tr('d MMMM yyyy'), locale).format(expiresOn!)}),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: maraPaper.withValues(alpha: 0.75)),
            ),
          ],
        ],
      ),
    );
  }
}

/// One stage: walked (folded, ticked — open it to see its steps), the
/// current one (every step, the next lit), or ahead (a locked line).
class _Stage extends StatelessWidget {
  const _Stage({
    required this.n,
    required this.path,
    required this.onGo,
    this.farm = false,
  });

  final int n;
  final PathState path;
  final void Function(PathStep) onGo;
  final bool farm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = translate(context.trLanguage, path.titleOf(n));
    final steps = path.stepsOf(n);
    final name = context.tr('Étape {n} · {title}', {'n': n, 'title': title});
    if (n > path.stage) {
      return Padding(
        key: Key('chemin-stage-$n'),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  key: Key('chemin-locked-$n'),
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      );
    }
    if (n < path.stage) {
      return Padding(
        key: Key('chemin-stage-$n'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: Key('chemin-done-$n'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 6),
            leading: const CircleAvatar(
              radius: 14,
              backgroundColor: maraGreen,
              child: Icon(Icons.check, size: 18, color: maraPaper),
            ),
            title: Text(name,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            children: [
              for (final s in steps)
                _StepRow(step: s, next: false, farm: farm, onGo: onGo),
            ],
          ),
        ),
      );
    }
    final done = steps.where((s) => s.done).length;
    return Container(
      key: Key('chemin-stage-$n'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      decoration: BoxDecoration(
        border: Border.all(color: maraCaramel, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: maraCaramel,
                  child: Text('$n',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: maraDeep, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      context.tr('Étape {n} sur 4 · {title}', {'n': n, 'title': title}),
                      key: const Key('chemin-current'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text('$done / ${steps.length}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final s in steps)
            _StepRow(
              step: s,
              // The step to do now: never the podium while it is « Bientôt ».
              next: s.key == path.proposed?.key,
              soon: path.soon(s),
              farm: farm,
              onGo: onGo,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.next,
    required this.onGo,
    this.soon = false,
    this.farm = false,
  });

  final PathStep step;
  final bool next;
  final void Function(PathStep) onGo;

  /// Not yet possible (the podium while the league is not a race).
  final bool soon;
  final bool farm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = step.done;
    final soft = next
        ? maraPaper.withValues(alpha: 0.75)
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      key: Key('chemin-step-${step.key}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: next
            ? maraDeep
            : theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: done ? 0.5 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: done
                      ? maraGreen
                      : next
                          ? maraCaramel
                          : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(done ? Icons.check : pathStepIcon(step.key),
                    color: done
                        ? maraPaper
                        : next
                            ? maraDeep
                            : theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pathStepTitle(context, step, farm: farm),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: next ? maraPaper : null,
                      ),
                    ),
                    Text(
                      done
                          ? context.tr('Fait')
                          : [
                              if (step.goal > 1) '${step.progress} / ${step.goal}',
                              context.tr('+{n} cauris', {'n': step.reward}),
                            ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: soft),
                    ),
                  ],
                ),
              ),
              if (!done && !next && soon)
                Padding(
                  key: Key('chemin-soon-${step.key}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(context.tr('Bientôt'),
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700)),
                )
              else if (!done && !next)
                TextButton(
                  onPressed: () => onGo(step),
                  child: Text(context.tr('Faire')),
                ),
            ],
          ),
          if (next) ...[
            if (step.line.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(pathStepLine(context, step, farm: farm),
                  style: theme.textTheme.bodySmall?.copyWith(color: soft)),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('chemin-go'),
                style: FilledButton.styleFrom(
                    backgroundColor: maraCaramel, foregroundColor: maraDeep),
                onPressed: () => onGo(step),
                icon: const Icon(Icons.arrow_forward),
                label: Text(context.tr('Faire maintenant'),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tool the path opens: open (green), or locked with what opens it.
class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.org, required this.tool, required this.path});

  final OrgSummary org;
  final PathTool tool;
  final PathState path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = path.tools[tool.key] ?? false;
    return ListTile(
      key: Key('chemin-tool-${tool.key}'),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: open ? maraCaramel : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(tool.icon,
            color: open ? maraDeep : theme.colorScheme.onSurfaceVariant),
      ),
      title: Text(context.tr(tool.label),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(open
          ? context.tr('Ouvert')
          : pathToolGoal(context, org, tool.key, path)),
      trailing: Icon(open ? Icons.check_circle : Icons.lock_outline,
          color: open ? maraGreen : theme.colorScheme.onSurfaceVariant),
    );
  }
}

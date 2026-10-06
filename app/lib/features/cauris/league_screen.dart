import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/models.dart';
import '../../core/cauris/cauris_repository.dart';
import '../../core/errors.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import '../../core/storefront/storefront_repository.dart' show publicShopUrl;
import 'cauri_icon.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// « Classement » (086): this week's race in the business's league.
///
/// A podium for the top 3 — the bars rise as the page opens — then the
/// business's own place and what the next one costs, last week's result,
/// a card to send on WhatsApp when there is something to be proud of, and
/// the two choices: hide the name from others, hear the board four times a
/// week. Never the bottom of the board: only the top and yourself.
class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key, required this.org, required this.cauris});

  final OrgSummary org;
  final CaurisRepository cauris;

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  LeagueBoard? _board;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.cauris.board(widget.org.id);
      if (!mounted) return;
      setState(() {
        _board = b;
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

  Future<void> _prefs({bool? hidden, bool? notify}) async {
    try {
      await widget.cauris
          .setBoardPrefs(widget.org.id, hidden: hidden, notify: notify);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  Future<void> _share(LeagueBoard b) async {
    final place = b.rank == 1 ? '1er' : '${b.rank}e';
    final slug = widget.org.slug;
    final text = 'Je suis $place cette semaine sur Mara, en ${b.label} ! 🏆'
        '${slug == null ? '' : ' Venez voir ma vitrine : ${publicShopUrl(slug)}'}';
    await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = _board;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Classement'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (b == null)
              Text(context.tr('Le classement n\'est pas encore ouvert.'))
            else ...[
              Text(b.label.toUpperCase(),
                  key: const Key('league-label'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Cette semaine · ${b.size} entreprise${b.size > 1 ? 's' : ''} '
                  'dans la course',
                  style: theme.textTheme.bodySmall?.copyWith(color: kMist)),
              const SizedBox(height: 16),
              _Podium(top: b.top),
              const SizedBox(height: 18),
              _You(board: b),
              if (b.lastWeekRank != null) ...[
                const SizedBox(height: 10),
                Text(
                  'La semaine dernière : ${b.lastWeekRank == 1 ? '1er' : '${b.lastWeekRank}e'} '
                  'de votre ligue.',
                  key: const Key('league-last-week'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (b.rank <= 3 && b.score > 0) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('league-share'),
                  onPressed: () => _share(b),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(context.tr('Le dire sur WhatsApp')),
                ),
              ],
              const SizedBox(height: 22),
              KajCard(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      key: const Key('league-notify'),
                      value: b.notify,
                      onChanged: (v) => _prefs(notify: v),
                      title: Text(context.tr('Le classement 4 fois par semaine')),
                      subtitle: Text(context.tr('Lundi, mercredi, vendredi, dimanche à 19 h')),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      key: const Key('league-hidden'),
                      value: b.hidden,
                      onChanged: (v) => _prefs(hidden: v),
                      title: Text(context.tr('Cacher mon nom aux autres')),
                      subtitle: Text(context.tr('Ils voient « une boutique de … »')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('Chaque lundi, les 3 premiers de chaque ligue gagnent des cauris, le badge « Top 3 » sur leur vitrine pour la semaine, et le premier est mis en avant 7 jours.'),
                style: theme.textTheme.bodySmall?.copyWith(color: kMist),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The top 3, 2-1-3, the bars rising as the page opens.
class _Podium extends StatelessWidget {
  const _Podium({required this.top});

  final List<({int rank, String name, int score, bool me})> top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (top.isEmpty) {
      return KajCard(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(context.tr('Personne n\'a encore gagné de cauris cette semaine dans votre ligue : la première commande prend la tête.'),
              style: theme.textTheme.bodyMedium),
        ),
      );
    }
    final byRank = {for (final t in top) t.rank: t};
    final order = [2, 1, 3];
    const heights = {1: 120.0, 2: 90.0, 3: 66.0};
    const colours = {1: maraGold, 2: Color(0xFFB9BCD6), 3: maraTerracotta};
    final reduced = KajMotion.reduced(context);
    return SizedBox(
      key: const Key('league-podium'),
      height: 210,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final r in order)
            Expanded(
              child: byRank[r] == null
                  ? const SizedBox()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(byRank[r]!.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: byRank[r]!.me
                                    ? FontWeight.w800
                                    : FontWeight.w600)),
                        const SizedBox(height: 4),
                        CaurisAmount(byRank[r]!.score,
                            iconSize: 13, style: theme.textTheme.labelMedium),
                        const SizedBox(height: 6),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: heights[r]!),
                          duration: reduced
                              ? Duration.zero
                              : Duration(milliseconds: 500 + 200 * (3 - r)),
                          curve: Curves.easeOutBack,
                          builder: (context, h, _) => Container(
                            height: h,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: colours[r],
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12)),
                              border: byRank[r]!.me
                                  ? Border.all(color: maraIndigo, width: 3)
                                  : null,
                            ),
                            alignment: Alignment.topCenter,
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('$r',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                    color: maraIndigo,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// The business's own place, and the price of the next one.
class _You extends StatelessWidget {
  const _You({required this.board});

  final LeagueBoard board;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = board;
    final place = b.rank == 1 ? '1er' : '${b.rank}e';
    return Container(
      key: const Key('league-you'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: maraIndigo,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(place,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(color: maraGold, fontWeight: FontWeight.w900)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaurisAmount(b.score,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: maraCream, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  b.gap == null
                      ? (b.score > 0 ? context.tr('En tête : gardez-la !') : context.tr('La course commence.'))
                      : context.tr('Encore {gap} cauris pour la place devant.', {'gap': b.gap}),
                  key: const Key('league-gap'),
                  style: theme.textTheme.bodySmall?.copyWith(color: maraCream),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

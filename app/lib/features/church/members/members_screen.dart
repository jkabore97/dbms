import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/association/books_start.dart';
import '../../../core/association/members.dart';
import '../../../core/auth/models.dart';
import '../../../core/db/local_db.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/notify/bell_room.dart';
import '../../../core/phone/country_codes.dart' show displayPhone;
import 'member_form_screen.dart';
import 'member_screen.dart';
import 'member_words.dart';

/// « Membres » (148): an association's list — a legacy church's too.
///
/// Search by name or phone, how many, and for each member their phone,
/// since when, what they gave this year (when the caller may see amounts:
/// full visibility, as the giving statement) and where they stand on the
/// usual cotisation (134) when the association has one.
///
/// Offline, the list the phone last read (MembersBook), said as such;
/// adding needs the network. Observers and approvers read it, nobody else
/// writes it — as 148's policies say (canWriteMembers).
class MembersScreen extends StatefulWidget {
  const MembersScreen({
    super.key,
    required this.api,
    required this.org,
    this.db,
    this.books,
    this.openMember,
    this.openStatement,
  });

  final MembersApi api;
  final OrgSummary org;
  final LocalDb? db;

  /// The usual cotisation (134): the period the statuses are said in, and
  /// the reminder's amount.
  final BooksStartApi? books;

  /// Opens a member's page; the screen's own push when null.
  final Future<void> Function(AssociationMember member, MembersList list)? openMember;

  /// « Relevé de dons » for one member, from their page.
  final void Function(AssociationMember member)? openStatement;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _search = TextEditingController();
  late final MembersBook _book = MembersBook(widget.api, widget.db);
  MembersList? _list;
  ContributionDefault? _usual;
  bool _loading = true;
  Object? _error;

  bool get _canWrite => canWriteMembers(widget.org);

  @override
  void initState() {
    super.initState();
    _usual = BooksStart.lastKnown[widget.org.id]?.contribution;
    _load();
    _loadUsual();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _list == null;
      _error = null;
    });
    try {
      final list = await _book.load(widget.org.id);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadUsual() async {
    final books = widget.books;
    if (books == null) return;
    try {
      final start = await books.booksStart(widget.org.id);
      if (mounted && start != null) setState(() => _usual = start.contribution);
    } catch (_) {
      // No signal: the statuses are said by the month.
    }
  }

  Future<void> _add() async {
    final list = _list;
    final saved = await Navigator.of(context).push<AssociationMember>(
      MaterialPageRoute(
        builder: (_) => MemberFormScreen(
          api: widget.api,
          orgId: widget.org.id,
          others: list?.members ?? const [],
          notesKept: list?.serverReady ?? true,
        ),
      ),
    );
    if (saved != null || mounted) await _load();
  }

  Future<void> _open(AssociationMember m) async {
    final list = _list!;
    if (widget.openMember != null) {
      await widget.openMember!(m, list);
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MemberScreen(
          api: widget.api,
          org: widget.org,
          member: m,
          list: list,
          usual: _usual,
          openStatement: widget.openStatement,
        ),
      ));
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Membres')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: context.tr('Actualiser'),
          ),
          bellRoom,
        ],
      ),
      floatingActionButton: _canWrite && list != null && list.members.isNotEmpty
          ? FloatingActionButton.extended(
              key: const Key('members-add'),
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(context.tr('Ajouter')),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : list == null
              ? _failed(context)
              : RefreshIndicator(onRefresh: _load, child: _body(context, list)),
    );
  }

  Widget _failed(BuildContext context) {
    final e = _error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              e == null || isOffline(e)
                  ? context.tr('Pas de réseau, et la liste des membres n\'a pas encore été lue sur ce téléphone.')
                  : describeError(e),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('Réessayer')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MembersList list) {
    final theme = Theme.of(context);
    final shown = [for (final m in list.members) if (m.matches(_search.text)) m];
    final lang = context.trLanguage;
    final late = list.members.where((m) => m.dues?.status == DuesStatus.late).length;
    final upToDate = list.members.where((m) => m.dues?.status == DuesStatus.upToDate).length;
    final hasDues = list.members.any((m) => m.dues != null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (list.fromPhone)
          _Banner(
            key: const Key('members-offline'),
            icon: Icons.cloud_off_outlined,
            text: list.readAt == null
                ? context.tr('Hors connexion : la dernière liste lue sur ce téléphone.')
                : context.tr('Hors connexion : la liste du {date}.', {
                    'date': DateFormat('d MMM, HH:mm', context.trLocale).format(list.readAt!),
                  }),
          ),
        if (list.members.isEmpty)
          _Empty(canWrite: _canWrite, onAdd: _add)
        else ...[
          TextField(
            key: const Key('members-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr('Chercher un nom ou un numéro'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.tr('Effacer'),
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_search.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            key: const Key('members-count'),
            shown.length == list.members.length
                ? (list.members.length == 1
                    ? context.tr('1 membre')
                    : context.tr('{n} membres', {'n': list.members.length}))
                : context.tr('{shown} sur {n}', {'shown': shown.length, 'n': list.members.length}),
            style: theme.textTheme.titleSmall,
          ),
          if (hasDues) ...[
            const SizedBox(height: 2),
            Text(
              context.tr('{ok} à jour · {late} en retard', {'ok': upToDate, 'late': late}),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          for (final m in shown)
            _MemberRow(
              member: m,
              currency: widget.org.currency,
              period: _usual?.period,
              lang: lang,
              onTap: () => _open(m),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(context.tr('Personne ne correspond.'), textAlign: TextAlign.center),
            ),
          if (!list.serverReady) ...[
            const SizedBox(height: 12),
            Text(
              context.tr('Les totaux, les cotisations et la note arrivent avec la prochaine mise à jour du serveur.'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.currency,
    required this.period,
    required this.lang,
    required this.onTap,
  });

  final AssociationMember member;
  final String currency;
  final ContributionPeriod? period;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = member;
    final narrow = isNarrow(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final details = [
      if (m.phone != null) displayPhone(m.phone!),
      if (m.since != null) memberSince(lang, m.since),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: Key('member-row-${m.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Text(initialsOf(m.fullName),
                    style: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (m.note != null)
                      Text(m.note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    for (final d in details)
                      Text(d, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    if (narrow && m.givenYear != null)
                      Text(
                        '${moneyFormat(currency).format(m.givenYear)} · ${context.tr('cette année')}',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    if (m.dues != null) ...[
                      const SizedBox(height: 6),
                      DuesPill(dues: m.dues!, period: period),
                    ],
                  ],
                ),
              ),
              if (!narrow && m.givenYear != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(moneyFormat(currency).format(m.givenYear),
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Text(context.tr('cette année'), style: muted, textAlign: TextAlign.end),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// « À jour » green, « À payer » neutral, « En retard depuis … » warm —
/// always with its words and an icon, never the colour alone.
class DuesPill extends StatelessWidget {
  const DuesPill({super.key, required this.dues, this.period});

  final MemberDues dues;
  final ContributionPeriod? period;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg, icon) = switch (dues.status) {
      DuesStatus.upToDate => (
          dark ? const Color(0xFF1E3A2A) : const Color(0xFFE3F1E7),
          dark ? const Color(0xFF9FD8B1) : const Color(0xFF1E5C36),
          Icons.check_circle_outline,
        ),
      DuesStatus.due => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.schedule),
      DuesStatus.late => (
          dark ? const Color(0xFF4A2A14) : const Color(0xFFFBE7D9),
          dark ? const Color(0xFFF5B98F) : const Color(0xFF8A3A0B),
          Icons.error_outline,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(duesLabel(context.trLanguage, dues, period),
                style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canWrite, required this.onAdd});

  final bool canWrite;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 8),
      child: Column(
        children: [
          Icon(Icons.groups_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(context.tr('Aucun membre pour l\'instant'),
              style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            context.tr('Inscrivez les membres pour leur attribuer cotisations et dons, et leur remettre un relevé.'),
            textAlign: TextAlign.center,
          ),
          if (canWrite) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('members-add-first'),
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(context.tr('Ajouter des membres')),
            ),
          ],
        ],
      ),
    );
  }
}

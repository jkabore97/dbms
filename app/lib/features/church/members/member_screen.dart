import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/association/books_start.dart';
import '../../../core/association/members.dart';
import '../../../core/auth/models.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/notify/bell_room.dart';
import '../../../core/phone/country_codes.dart' show displayPhone;
import '../../../core/reports/models.dart' show accountLabel;
import 'member_form_screen.dart';
import 'member_words.dart';
import 'members_screen.dart' show DuesPill;

/// One member (148): who they are, where they stand on the cotisation,
/// what they gave — year by year, entry by entry — their « Relevé de
/// dons », « Écrire sur WhatsApp » (a polite reminder when the cotisation
/// waits), and, for those who may, « Modifier » and « Retirer ».
///
/// Removing is soft: the member leaves the list, their past entries stay
/// attributed to them (the giving statement still finds them). Asked in
/// the app, never through a browser's confirm().
class MemberScreen extends StatefulWidget {
  const MemberScreen({
    super.key,
    required this.api,
    required this.org,
    required this.member,
    this.list,
    this.usual,
    this.openStatement,
    this.launch,
  });

  final MembersApi api;
  final OrgSummary org;
  final AssociationMember member;

  /// The list the member was opened from (same-phone warning, notes kept).
  final MembersList? list;

  /// The usual cotisation (134), for the status's words and the reminder.
  final ContributionDefault? usual;

  /// « Relevé de dons » for this member.
  final void Function(AssociationMember member)? openStatement;

  /// Opens a link (wa.me); url_launcher when null. Tests pass their own.
  final Future<bool> Function(Uri uri)? launch;

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  late AssociationMember _member = widget.member;
  List<MemberGift>? _gifts;
  Object? _error;
  bool _loading = true;
  bool _busy = false;

  bool get _canWrite => canWriteMembers(widget.org);

  /// Amounts are line detail (006): shown with full visibility, and never
  /// to an observer — as « Relevé de dons » is withheld from them.
  bool get _seesGifts =>
      widget.org.visibility == 'full' && !widget.org.isObserverOnly;

  ContributionDefault? get _usual =>
      widget.usual ?? BooksStart.lastKnown[widget.org.id]?.contribution;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    if (!_seesGifts) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gifts = await widget.api.memberHistory(_member.id);
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
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

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<AssociationMember>(
      MaterialPageRoute(
        builder: (_) => MemberFormScreen(
          api: widget.api,
          orgId: widget.org.id,
          member: _member,
          others: widget.list?.members ?? const [],
          notesKept: widget.list?.serverReady ?? true,
        ),
      ),
    );
    if (saved != null && mounted) {
      setState(() => _member = AssociationMember(
            id: _member.id,
            fullName: saved.fullName,
            phone: saved.phone,
            note: saved.note,
            joinedOn: saved.joinedOn,
            createdAt: _member.createdAt,
            givenYear: _member.givenYear,
            cotisationsYear: _member.cotisationsYear,
            donsYear: _member.donsYear,
            lastGivenOn: _member.lastGivenOn,
            dues: _member.dues,
          ));
    }
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Retirer {name} de la liste ?', {'name': _member.fullName})),
        content: Text(ctx.tr('Ses cotisations et ses dons restent enregistrés à son nom, et son relevé reste disponible. Il n\'apparaîtra plus dans la liste ni dans « De qui ? ».')),
        actions: [
          TextButton(
            key: const Key('member-remove-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('Annuler')),
          ),
          FilledButton(
            key: const Key('member-remove-confirm'),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Retirer')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.removeMember(widget.org.id, _member.id);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final done = context.tr('{name} a été retiré de la liste.', {'name': _member.fullName});
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(isOffline(e)
            ? context.tr('Il faut du réseau pour retirer un membre.')
            : describeError(e)),
      ));
    }
  }

  Future<void> _whatsapp() async {
    final phone = _member.phone;
    if (phone == null) return;
    final text = whatsappMessage(context.trLanguage,
        member: _member, orgName: widget.org.name, usual: _usual, currency: widget.org.currency);
    final uri = whatsappLink(phone, text);
    final launch = widget.launch ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    await launch(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = _member;
    final money = moneyFormat(widget.org.currency);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final dues = m.dues;
    final late = dues != null && dues.status != DuesStatus.upToDate;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Membre')),
        actions: [
          if (_canWrite)
            IconButton(
              key: const Key('member-edit'),
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: context.tr('Modifier'),
            ),
          bellRoom,
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Who.
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Text(initialsOf(m.fullName),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSecondaryContainer)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.fullName,
                        key: const Key('member-name-title'),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (m.note != null) Text(m.note!, style: muted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (m.phone != null)
            _Line(icon: Icons.phone_outlined, text: displayPhone(m.phone!)),
          if (m.since != null)
            _Line(icon: Icons.event_outlined, text: memberSince(context.trLanguage, m.since)),
          if (dues != null) ...[
            const SizedBox(height: 12),
            Card(
              key: const Key('member-dues'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('Cotisation'), style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    DuesPill(dues: dues, period: _usual?.period),
                    if (_usual != null) ...[
                      const SizedBox(height: 6),
                      Text(context.tr('Cotisation habituelle : {usual}',
                              {'usual': usualCotisation(context.trLanguage, _usual!, widget.org.currency)}),
                          style: muted),
                    ],
                    if (dues.paidThrough != null)
                      Text(
                          context.tr('Payée jusqu\'au {date}', {
                            'date': DateFormat('d MMMM yyyy', context.trLocale).format(dues.paidThrough!),
                          }),
                          style: muted),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // What to do.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (m.phone != null)
                FilledButton.icon(
                  key: const Key('member-whatsapp'),
                  onPressed: _whatsapp,
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(late
                      ? context.tr('Rappeler sur WhatsApp')
                      : context.tr('Écrire sur WhatsApp')),
                ),
              if (widget.openStatement != null && _seesGifts)
                OutlinedButton.icon(
                  key: const Key('member-statement'),
                  onPressed: () => widget.openStatement!(m),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(context.tr('Relevé de dons')),
                ),
              if (_canWrite)
                OutlinedButton.icon(
                  key: const Key('member-remove'),
                  onPressed: _busy ? null : _remove,
                  style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: Text(context.tr('Retirer')),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (!_seesGifts)
            Text(context.tr('Le détail des cotisations et des dons est réservé aux responsables.'),
                style: muted)
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(
              children: [
                Text(isOffline(_error!)
                    ? context.tr('Pas de réseau : l\'historique s\'affichera au retour du réseau.')
                    : describeError(_error!)),
                TextButton.icon(
                  onPressed: _loadGifts,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.tr('Réessayer')),
                ),
              ],
            )
          else
            ..._history(context, _gifts ?? const [], money),
        ],
      ),
    );
  }

  List<Widget> _history(BuildContext context, List<MemberGift> gifts, NumberFormat money) {
    final theme = Theme.of(context);
    if (gifts.isEmpty) {
      return [
        Text(context.tr('Aucune cotisation ni aucun don à son nom pour l\'instant.'),
            key: const Key('member-no-gifts')),
      ];
    }
    final byYear = <int, double>{};
    for (final g in gifts) {
      if (g.reversed) continue;
      byYear[g.date.year] = (byYear[g.date.year] ?? 0) + g.amount;
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    final df = DateFormat('d MMM yyyy', context.trLocale);
    String kind(MemberGift g) => switch (g.kind) {
          'cotisation' => context.tr('Cotisation'),
          'don' => context.tr('Don'),
          _ => accountLabel(g.accountName),
        };
    return [
      Text(context.tr('Par année'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      for (final y in years)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text('$y', style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(money.format(byYear[y]),
                  key: Key('member-year-$y'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      const Divider(height: 28),
      Text(context.tr('Historique'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      for (final g in gifts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(df.format(g.date),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(
                  g.reversed ? '${kind(g)} · ${context.tr('annulé')}' : kind(g),
                  style: g.reversed
                      ? TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money.format(g.amount),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: g.reversed ? TextDecoration.lineThrough : null,
                  color: g.reversed ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

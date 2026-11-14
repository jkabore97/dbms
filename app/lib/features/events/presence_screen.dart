import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/events/invitations_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../storefront/my_invitations_screen.dart';

/// « Confirmer ma présence » (183): the card's one button opens
/// `/presence/<slug>`; signed out, the sign-in brings the person straight
/// back here. How many come (1 to 10), a word if they like, « Je
/// confirme » — then their photos, five each, from here or « Mes
/// invitations ». Confirming again changes the numbers, nothing more.
class PresenceScreen extends StatefulWidget {
  const PresenceScreen({super.key, required this.repo, required this.slug, this.preview, this.pick, this.toInvitations});

  final InvitationsRepository repo;
  final String slug;
  final String? preview;

  /// The gallery (the tests answer it).
  final Future<List<PickedPhoto>> Function(int limit)? pick;

  /// « Mes invitations » (the router's address by default).
  final VoidCallback? toInvitations;

  @override
  State<PresenceScreen> createState() => _PresenceScreenState();
}

class _PresenceScreenState extends State<PresenceScreen> {
  PresenceCard? _card;
  String? _problem;
  int _people = 1;
  final _message = TextEditingController();

  /// « Rappel WhatsApp la veille »: the number goes to the organiser only
  /// when the guest turns it on (off by default; a confirmation of before
  /// that shared it starts on).
  bool _sharePhone = false;
  bool _busy = false;
  String? _error;

  /// After « Je confirme »: whether it was the first time, and the card as
  /// « Mes invitations » has it (for its photos).
  bool? _first;
  MyInvitation? _mine;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await widget.repo.card(widget.slug, widget.preview);
      if (!mounted) return;
      if (c == null) {
        setState(() => _problem = context.tr('Cette carte n’est pas ouverte.'));
        return;
      }
      // Confirmed, and the answers since closed: the photos and « Mes
      // invitations » still, not only « fermées ».
      MyInvitation? mine;
      if (c.confirmed && !c.open) {
        try {
          mine = (await widget.repo.mine()).where((x) => x.slug == widget.slug).firstOrNull;
        } catch (_) {}
        if (!mounted) return;
      }
      setState(() {
        _card = c;
        _mine = mine ?? _mine;
        if (c.myPeople != null) _people = c.myPeople!.clamp(1, 10);
        if ((c.myMessage ?? '').isNotEmpty) _message.text = c.myMessage!;
        _sharePhone = c.hasPhone && c.mySharePhone;
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } catch (_) {
      if (mounted) setState(() => _problem = context.tr('Pas de réseau : réessayez.'));
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.repo.confirm(widget.slug, widget.preview,
          people: _people, message: _message.text, sharePhone: (_card?.hasPhone ?? false) && _sharePhone);
      MyInvitation? mine;
      try {
        mine = (await widget.repo.mine()).where((x) => x.slug == widget.slug).firstOrNull;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _first = r.first;
        _mine = mine;
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('Pas de réseau : réessayez.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhotos() async {
    final inv = _mine;
    if (inv == null || _adding) return;
    setState(() => _adding = true);
    try {
      final n = await addInvitationPhotos(context, widget.repo, inv, pick: widget.pick);
      if (n > 0) {
        final fresh = (await widget.repo.mine()).where((x) => x.slug == widget.slug).firstOrNull;
        if (mounted && fresh != null) setState(() => _mine = fresh);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _invitations() {
    final go = widget.toInvitations;
    if (go != null) {
      go();
      return;
    }
    // pushed, not gone to: Back returns here
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      context.push('/invitations');
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MyInvitationsScreen(repo: widget.repo)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _card;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Confirmer ma présence')), actions: const [bellRoom]),
      body: _problem != null
          ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(_problem!, key: const Key('presence-problem'), textAlign: TextAlign.center)))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
                  children: [
                    Text(context.tr('Confirmer ma présence à {title}', {'title': c.title}),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    if ([c.dateFr, c.place].any((x) => x != null && x.isNotEmpty))
                      Text([c.dateFr, c.place].where((x) => x != null && x.isNotEmpty).join(' · '), style: theme.textTheme.bodyMedium),
                    if (c.orgName != null && c.orgName!.isNotEmpty)
                      Text(context.tr('Organisé par {name}', {'name': c.orgName!}), style: theme.textTheme.bodySmall),
                    const SizedBox(height: 18),
                    if (_first != null || (!c.open && c.confirmed && !c.cancelled))
                      ..._done(context)
                    else if (c.cancelled)
                      Text(context.tr('Cet événement est annulé.'), key: const Key('presence-cancelled'), style: theme.textTheme.titleMedium)
                    else if (!c.open)
                      Text(context.tr('Les réponses sont fermées pour cet événement.'), style: theme.textTheme.titleMedium)
                    else
                      ..._form(context, c),
                  ],
                ),
    );
  }

  List<Widget> _form(BuildContext context, PresenceCard c) {
    final theme = Theme.of(context);
    return [
      if (c.confirmed)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(context.tr('Vous avez déjà confirmé : changez le nombre ou le mot si besoin.'), style: theme.textTheme.bodySmall),
        ),
      Row(children: [
        Expanded(child: Text(context.tr('Nombre de personnes'), style: theme.textTheme.titleMedium)),
        IconButton(
          key: const Key('presence-less'),
          tooltip: context.tr('Une de moins'),
          onPressed: _people <= 1 ? null : () => setState(() => _people--),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$_people', key: const Key('presence-people'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        IconButton(
          key: const Key('presence-more'),
          tooltip: context.tr('Une de plus'),
          onPressed: _people >= 10 ? null : () => setState(() => _people++),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]),
      const SizedBox(height: 12),
      TextField(
        key: const Key('presence-message'),
        controller: _message,
        maxLength: 500,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: context.tr('Un mot (facultatif)'), border: const OutlineInputBorder()),
      ),
      // the number only by the guest's choice, and only if the account has one
      if (c.hasPhone)
        SwitchListTile(
          key: const Key('presence-share-phone'),
          contentPadding: EdgeInsets.zero,
          value: _sharePhone,
          onChanged: _busy ? null : (v) => setState(() => _sharePhone = v),
          title: Text(context.tr('Rappel WhatsApp la veille')),
          subtitle: Text(context.tr('L’organisateur verra votre numéro pour vous écrire.')),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_error!, key: const Key('presence-error'), style: TextStyle(color: theme.colorScheme.error)),
        ),
      const SizedBox(height: 14),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: FilledButton(
          key: const Key('presence-confirm'),
          onPressed: _busy ? null : _confirm,
          child: Text(_busy ? context.tr('Envoi…') : context.tr('Je confirme')),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        c.album
            ? context.tr('Une fois confirmé, vous ajoutez vos photos de la fête : 5 au plus, depuis « Mes invitations ».')
            : context.tr('L’organisateur saura que vous venez. Vos invitations confirmées s’affichent dans « Mes invitations ».'),
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _done(BuildContext context) {
    final theme = Theme.of(context);
    final inv = _mine;
    final album = inv != null && inv.albumOn && inv.albumAllowed;
    return [
      Card(
        key: const Key('presence-done'),
        color: const Color(0xFFE8F3EA),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFF1E7B3A), size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                switch (_first) {
                  true => context.tr('Votre présence est confirmée. Merci !'),
                  false => context.tr('Votre réponse est mise à jour.'),
                  // confirmed before, the answers since closed
                  null => context.tr('Vous avez confirmé votre présence.'),
                },
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ]),
        ),
      ),
      if (_first == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(context.tr('Les réponses sont fermées pour cet événement.'), style: theme.textTheme.bodySmall),
        ),
      const SizedBox(height: 14),
      if (album) ...[
        Text(
            inv.photosOpen
                ? context.tr('Vous pouvez maintenant ajouter vos photos de la fête : {n} au plus.', {'n': inv.photosLimit})
                : context.tr('Vous pourrez ajouter vos photos de la fête : {n} au plus.', {'n': inv.photosLimit}),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: FilledButton.icon(
            key: const Key('presence-photos'),
            onPressed: _adding || !inv.canAddPhotos ? null : _addPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text('${context.tr('Ajouter des photos')} · ${inv.photosUsed} / ${inv.photosLimit}'),
          ),
        ),
        if (photoDaysNote(context, inv, DateTime.now()) case final note?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, key: const Key('presence-photo-days'), style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        key: const Key('presence-invitations'),
        onPressed: _invitations,
        icon: const Icon(Icons.celebration_outlined),
        label: Text(context.tr('Mes invitations')),
      ),
    ];
  }
}

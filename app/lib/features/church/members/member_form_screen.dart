import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/association/members.dart';
import '../../../core/errors.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/notify/bell_room.dart';
import '../../../core/phone/country_codes.dart';
import '../../common/phone_field.dart';

/// « Ajouter un membre » / « Modifier » (148): a name (required), a phone
/// (optional, its country chosen — the setup's PhoneField, length checked
/// as the setup checks it), a word about them (optional: « Trésorier »)
/// and the day they joined.
///
/// Adding, « Enregistrer et ajouter un autre » keeps the screen open on an
/// empty form, so a treasurer types ten members in a row. A phone that is
/// already another member's is said under the field as it is typed, and
/// asked once more on saving (« Ajouter quand même ? »); the server says it
/// too when the list on the phone was old (148's MA148).
///
/// Needs the network, as a credit and an invoice do: a member's id comes
/// from the server. With no signal it says so and keeps what was typed.
///
/// Pops with the last member saved (an [AssociationMember]), or null.
class MemberFormScreen extends StatefulWidget {
  const MemberFormScreen({
    super.key,
    required this.api,
    required this.orgId,
    this.member,
    this.others = const [],
    this.notesKept = true,
    this.single = false,
  });

  final MembersApi api;
  final String orgId;

  /// The member edited; null adds.
  final AssociationMember? member;

  /// The list as known, for the same-phone warning and the country.
  final List<AssociationMember> others;

  /// The server keeps the note (148). False before it: the field is not
  /// offered rather than silently dropped.
  final bool notesKept;

  /// One member and back (Recette's « De qui ? »): no « ajouter un autre ».
  final bool single;

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _nameFocus = FocusNode();
  late CountryCode _country;
  DateTime? _joined;
  bool _busy = false;
  String? _error;
  String? _nameError;
  String? _phoneError;
  final List<AssociationMember> _added = [];

  bool get _editing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _country = _usualCountry();
    if (m != null) {
      _name.text = m.fullName;
      final phone = m.phone;
      if (phone != null && phone.isNotEmpty) {
        _country = countryOfNumber(phone) ?? _country;
        _phone.text = _country.localPart(phone);
      }
      _note.text = m.note ?? '';
      _joined = m.joinedOn;
    }
  }

  /// The country most of the list's numbers are in, else Burkina Faso.
  CountryCode _usualCountry() {
    final counts = <String, int>{};
    for (final m in widget.others) {
      final c = m.phone == null ? null : countryOfNumber(m.phone!);
      if (c != null) counts[c.iso] = (counts[c.iso] ?? 0) + 1;
    }
    if (counts.isEmpty) return defaultCountry;
    final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    return countryByIso(best.key);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String? get _e164 {
    final typed = _phone.text.trim();
    return typed.isEmpty ? null : _country.toE164(typed);
  }

  /// Another member with this number, from the list as known.
  AssociationMember? get _samePhone {
    final p = _e164;
    if (p == null) return null;
    final digits = p.replaceAll(RegExp(r'\D'), '');
    for (final m in [...widget.others, ..._added]) {
      if (m.id == widget.member?.id) continue;
      if ((m.phone ?? '').replaceAll(RegExp(r'\D'), '') == digits) return m;
    }
    return null;
  }

  Future<bool> _askSamePhone(String message) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Ce numéro est déjà enregistré')),
        content: Text(message),
        actions: [
          TextButton(
            key: const Key('member-same-cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('Corriger')),
          ),
          FilledButton(
            key: const Key('member-same-anyway'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_editing ? ctx.tr('Enregistrer quand même') : ctx.tr('Ajouter quand même')),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _save({required bool another}) async {
    if (_busy) return;
    final name = _name.text.trim();
    final typed = _phone.text.trim();
    setState(() {
      _error = null;
      _nameError = name.isEmpty ? context.tr('Le nom du membre, s\'il vous plaît.') : null;
      _phoneError = typed.isEmpty ? null : _country.lengthProblem(typed);
    });
    if (_nameError != null || _phoneError != null) return;
    var allow = false;
    final same = _samePhone;
    if (same != null) {
      allow = await _askSamePhone(
          context.tr('Ce numéro est déjà celui de {name}.', {'name': same.fullName}));
      if (!allow || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      String id;
      try {
        id = await _send(name, allow);
      } on SamePhoneException catch (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        final who = RegExp(r'celui de (.+?)\.?$').firstMatch(e.message)?.group(1);
        if (!await _askSamePhone(who == null
            ? describeError(e.message)
            : context.tr('Ce numéro est déjà celui de {name}.', {'name': who}))) {
          return;
        }
        setState(() => _busy = true);
        id = await _send(name, true);
      }
      final saved = AssociationMember(
        id: id,
        fullName: name,
        phone: _e164,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        joinedOn: _joined ?? widget.member?.joinedOn ?? DateTime.now(),
        createdAt: widget.member?.createdAt ?? DateTime.now(),
      );
      if (!mounted) return;
      if (another) {
        setState(() {
          _added.add(saved);
          _busy = false;
          _name.clear();
          _phone.clear();
          _note.clear();
          _joined = null;
        });
        _nameFocus.requestFocus();
        return;
      }
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = isOffline(e)
            ? context.tr('Il faut du réseau pour enregistrer un membre : la liste est gardée sur le serveur. Ce que vous avez tapé reste ici.')
            : describeError(e);
      });
    }
  }

  Future<String> _send(String name, bool allow) => widget.api.saveMember(
        widget.orgId,
        id: widget.member?.id,
        name: name,
        phone: _e164,
        note: widget.notesKept ? _note.text.trim() : null,
        joinedOn: _joined,
        allowSamePhone: allow,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _joined ?? widget.member?.joinedOn ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (picked != null) setState(() => _joined = picked);
  }

  void _close() {
    Navigator.of(context).pop(_added.isEmpty ? null : _added.last);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final same = _samePhone;
    final joined = _joined ?? widget.member?.joinedOn;
    final df = DateFormat('d MMMM yyyy', context.trLocale);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.tr('Fermer'),
            onPressed: _close,
          ),
          title: Text(_editing ? context.tr('Modifier le membre') : context.tr('Ajouter un membre')),
          actions: const [bellRoom],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_added.isNotEmpty) ...[
              Container(
                key: const Key('member-added'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _added.length == 1
                            ? context.tr('{name} ajouté. Le suivant ?', {'name': _added.last.fullName})
                            : context.tr('{n} membres ajoutés. Le suivant ?', {'n': _added.length}),
                        style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const Key('member-name'),
              controller: _name,
              focusNode: _nameFocus,
              autofocus: !_editing,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              decoration: InputDecoration(
                labelText: context.tr('Nom'),
                prefixIcon: const Icon(Icons.person_outline),
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            PhoneField(
              key: const Key('member-phone'),
              controller: _phone,
              country: _country,
              onCountry: (c) => setState(() => _country = c),
              labelText: context.tr('Téléphone (facultatif)'),
              errorText: _phoneError,
              onChanged: (_) => setState(() => _phoneError = null),
            ),
            if (same != null)
              Padding(
                key: const Key('member-same-phone'),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr('Ce numéro est déjà celui de {name}.', {'name': same.fullName}),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.notesKept) ...[
              const SizedBox(height: 14),
              TextField(
                key: const Key('member-note'),
                controller: _note,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: context.tr('Rôle ou note'),
                  helperText: context.tr('Facultatif'),
                  hintText: context.tr('Trésorier, section jeunes…'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
            ] else
              const SizedBox(height: 14),
            ListTile(
              key: const Key('member-joined'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(context.tr('Membre depuis')),
              subtitle: Text(joined == null ? context.tr('Aujourd\'hui') : df.format(joined)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _busy ? null : _pickDate,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('member-error'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('member-save'),
              onPressed: _busy ? null : () => _save(another: false),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(context.tr('Enregistrer')),
            ),
            if (!_editing && !widget.single) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('member-save-another'),
                onPressed: _busy ? null : () => _save(another: true),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(context.tr('Enregistrer et ajouter un autre')),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              context.tr('Des membres, pas des comptes : gratuits, sans Pro.'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/admin/models.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/l10n/tr.dart';

/// The admin edit of one member's own information (moved from the old
/// People screen into Équipe, 101). Pre-filled from the roster, saved
/// through admin_save_member_profile (046) — which lets an admin edit only
/// someone they outrank, so a refusal here is the server's word, not this
/// form's. Never opened on an owner. A first name and a family name are
/// required, matching the personal profile form; the rest are optional.
class EditMemberSheet extends StatefulWidget {
  const EditMemberSheet({super.key, required this.admin, required this.member});

  final AdminRepository admin;
  final Member member;

  @override
  State<EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends State<EditMemberSheet> {
  late final _first = TextEditingController(text: widget.member.firstName ?? '');
  late final _middle =
      TextEditingController(text: widget.member.middleName ?? '');
  late final _last = TextEditingController(text: widget.member.lastName ?? '');
  late final _title = TextEditingController(text: widget.member.title ?? '');
  late final _phone = TextEditingController(text: widget.member.phone ?? '');
  late DateTime? _dob = widget.member.dateOfBirth;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _title.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      setState(() => _error = context.tr('Un prénom et un nom de famille sont requis.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.admin.saveMemberProfile(
        widget.member.userId,
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        middleName: _middle.text.trim(),
        dateOfBirth: _dob,
        title: _title.text.trim(),
        phone: _phone.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AuthRepository.describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = context.trLanguage == 'en' ? 'en' : 'fr_FR';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Informations — {label}', {'label': widget.member.label}),
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('member-first'),
              controller: _first,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('Prénom'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _middle,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('Deuxième prénom (facultatif)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('member-last'),
              controller: _last,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: context.tr('Nom de famille'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: context.tr('Titre (facultatif)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: context.tr('Téléphone (facultatif)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dob ?? DateTime(1990, 1, 1),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _dob = picked);
                    },
              icon: const Icon(Icons.cake_outlined),
              label: Text(_dob == null
                  ? context.tr('Date de naissance (facultatif)')
                  : context.tr('Né(e) le {date}',
                      {'date': DateFormat('d MMMM y', locale).format(_dob!)})),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('member-save'),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.tr('Enregistrer'), style: const TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The roles somebody of [callerRoles] may hand out: below their own rank,
/// never an owner nor a super administrator (the platform's alone).
List<String> grantableRolesFor(Iterable<String> callerRoles) {
  final mine = accountRankOf(callerRoles);
  return [
    for (final r in adminGrantableRoles.keys)
      if (accountRoleRank(r) < mine) r,
  ];
}

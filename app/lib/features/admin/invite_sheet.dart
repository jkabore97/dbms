import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/admin/models.dart';
import '../../core/auth/auth_repository.dart';

/// Inviting somebody, in one sheet.
///
/// The shape of this screen is decided by who is using it. The person being
/// invited is usually standing right there, and usually has no email address,
/// so the default is a code that can be handed over three ways — read aloud,
/// copied, or scanned off the screen — and a phone number is optional rather
/// than required.
///
/// Two deliberate decisions:
///
///  * The role and the scope are chosen before the code exists, not after. A
///    code that could be "upgraded" later would be a code worth stealing.
///  * A phone number, when given, pins the invitation to that number: nobody
///    else can use the code even if they see it, and the invitee gets it swept
///    up automatically at sign-in with nothing to type. That is strictly safer
///    than a bearer code, so the field is offered first and explained.
class InviteSheet extends StatefulWidget {
  const InviteSheet({
    super.key,
    required this.admin,
    required this.orgId,
    required this.orgName,
    required this.structure,
  });

  final AdminRepository admin;
  final String orgId;
  final String orgName;
  final List<Entity> structure;

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  final _phoneController = TextEditingController();

  String _role = 'employee';

  /// Encodes both halves of a scope in one dropdown value: 'org', 'entity:ID',
  /// 'department:ID'. Flattening it this way keeps the picker a single tap for
  /// what is, to the user, a single question — "over what?".
  String _scope = 'org';

  String _visibility = 'full';
  int _validDays = 14;

  bool _working = false;
  String? _error;
  Invitation? _created;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  (String kind, String id) _resolveScope() {
    if (_scope == 'org') return ('org', widget.orgId);
    final parts = _scope.split(':');
    return (parts[0], parts[1]);
  }

  Future<void> _create() async {
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final (kind, id) = _resolveScope();
      final typed = _phoneController.text.trim();
      final invitation = await widget.admin.createInvitation(
        orgId: widget.orgId,
        role: _role,
        scopeKind: kind,
        scopeId: id,
        phone: typed.isEmpty ? null : AuthRepository.normalizePhone(typed),
        visibility: _role == 'observer' ? _visibility : 'full',
        validFor: Duration(days: _validDays),
      );
      if (!mounted) return;
      setState(() {
        _created = invitation;
        _working = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _created == null ? _buildForm(context) : _buildCode(context),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Before: what are we granting?
  // ----------------------------------------------------------------

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Inviter quelqu\'un', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          widget.orgName,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        Text('Rôle', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            for (final entry in adminGrantableRoles.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _working ? null : (v) => setState(() => _role = v!),
        ),

        if (_role == 'observer') ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'full', label: Text('Détail complet')),
              ButtonSegment(value: 'summary', label: Text('Totaux seulement')),
            ],
            selected: {_visibility},
            onSelectionChanged: _working
                ? null
                : (s) => setState(() => _visibility = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            "Un observateur lit les comptes sans jamais pouvoir les modifier.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        const SizedBox(height: 20),
        Text('Portée', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _scope,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(
              value: 'org',
              child: Text("Toute l'activité"),
            ),
            for (final entity in widget.structure) ...[
              DropdownMenuItem(
                value: 'entity:${entity.id}',
                child: Text(entity.name),
              ),
              for (final dept in entity.departments)
                DropdownMenuItem(
                  value: 'department:${dept.id}',
                  child: Text('    ${entity.name} · ${dept.name}'),
                ),
            ],
          ],
          onChanged: _working ? null : (v) => setState(() => _scope = v!),
        ),
        const SizedBox(height: 4),
        Text(
          'Cette personne ne verra rien en dehors de cette portée.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 20),
        Text('Numéro de téléphone (optionnel)',
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          enabled: !_working,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '70 12 34 56',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Avec un numéro, le code ne fonctionne que pour cette personne et '
          "s'active tout seul à sa connexion. Sans numéro, il fonctionne pour "
          'quiconque le détient — à remettre en main propre.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 20),
        Text('Valable', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1 jour')),
            ButtonSegment(value: 7, label: Text('7 jours')),
            ButtonSegment(value: 14, label: Text('14 jours')),
          ],
          selected: {_validDays},
          onSelectionChanged:
              _working ? null : (s) => setState(() => _validDays = s.first),
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(message: _error!),
        ],

        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _working ? null : _create,
            icon: _working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2),
            label: const Text('Créer le code', style: TextStyle(fontSize: 17)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ----------------------------------------------------------------
  // After: the code itself
  // ----------------------------------------------------------------

  Widget _buildCode(BuildContext context) {
    final theme = Theme.of(context);
    final invitation = _created!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Code créé', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '${roleLabel(invitation.role)} · '
          '${scopeKindLabel(invitation.scopeKind)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 24),

        // The code is the whole point of this screen, so it is the biggest
        // thing on it: read aloud from across a room, or copied by eye.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            invitation.code,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 3,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // The other handover: one phone pointed at another, with nothing
        // spoken and nothing to mistype. White background regardless of theme
        // — a QR inverted on a dark card does not scan.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: QrImageView(
            data: invitation.code,
            size: 180,
            backgroundColor: Colors.white,
          ),
        ),

        const SizedBox(height: 20),
        Text(
          invitation.phone == null
              ? 'Valable pour quiconque détient ce code, '
                  "jusqu'au ${_formatDate(invitation.expiresAt)}."
              : 'Valable uniquement pour ${invitation.phone}, '
                  "jusqu'au ${_formatDate(invitation.expiresAt)}.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: invitation.code),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copié')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copier'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Terminé'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  static String _formatDate(DateTime when) =>
      '${when.day.toString().padLeft(2, '0')}/'
      '${when.month.toString().padLeft(2, '0')}/${when.year}';
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }
}

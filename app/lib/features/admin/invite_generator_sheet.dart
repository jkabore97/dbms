import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/onboarding/onboarding_repository.dart';
import '../../core/phone/country_codes.dart';
import '../common/phone_field.dart';

/// The manager's side of getting somebody into the business.
///
/// This is what replaced "J'ai un code" as the app's answer to onboarding. The
/// old entry sat in the *invitee's* menu and assumed a code had already
/// reached them by some means the app knew nothing about — which is backwards.
/// The person holding the app is the manager; the person without it is the one
/// who needs reaching.
///
/// So the flow runs the other way: the manager says who they are inviting and
/// what they will do, gets a code, and sends it. Sending is the whole point,
/// and it is one tap to WhatsApp — which is where this conversation actually
/// happens here, not email.
///
/// Two details that matter more than they look.
///
/// **The message is composed for them.** A bare code in a chat window is a
/// riddle; the message says which business, what to install, and where to type
/// it. The name of the business comes back with the code from
/// `invite_employee()` precisely so this can be built without a round trip.
///
/// **The number is optional and pins the invitation when given.** With it, the
/// code only works for that person — and since 017 it matches either the
/// number they signed up with or the one on their profile, because a manager
/// types the number they were given and that is usually the second one.
class InviteGeneratorSheet extends StatefulWidget {
  const InviteGeneratorSheet({
    super.key,
    required this.orgId,
    required this.onboarding,
  });

  final String orgId;
  final OnboardingRepository onboarding;

  static Future<void> open(
    BuildContext context, {
    required String orgId,
    required OnboardingRepository onboarding,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InviteGeneratorSheet(orgId: orgId, onboarding: onboarding),
    );
  }

  @override
  State<InviteGeneratorSheet> createState() => _InviteGeneratorSheetState();
}

class _InviteGeneratorSheetState extends State<InviteGeneratorSheet> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _phone = TextEditingController();

  /// The manager types the number they were given, and it is not always a
  /// local one — a supplier's accountant in Abidjan is invited the same way.
  CountryCode _country = defaultCountry;

  String _role = 'employee';
  Invitation? _invitation;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invitation = await widget.onboarding.invite(
        orgId: widget.orgId,
        role: _role,
        fullName: _name.text.trim(),
        title: _title.text.trim(),
        phone: _phone.text.trim().isEmpty
            ? ''
            : _country.toE164(_phone.text),
      );
      if (!mounted) return;
      setState(() {
        _invitation = invitation;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, inset + 20),
      child: SingleChildScrollView(
        child: _invitation == null
            ? _form(theme)
            : _ready(theme, _invitation!),
      ),
    );
  }

  Widget _form(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Inviter quelqu’un', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Vous obtiendrez un code à lui envoyer. Il crée son compte, entre le '
          'code, et rejoint l’entreprise.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nom de la personne (facultatif)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Fonction (facultatif)',
            helperText: 'Vendeuse, gardien, comptable…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        PhoneField(
          controller: _phone,
          country: _country,
          onCountry: (c) => setState(() => _country = c),
          labelText: 'Téléphone (facultatif)',
          hintText: '70 12 34 56',
          enabled: !_busy,
          // Said plainly, because it changes what the code is: with a
          // number it belongs to one person, without it whoever holds it.
          helperText: 'Avec un numéro, le code ne marche que pour lui.',
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: const InputDecoration(
            labelText: 'Rôle',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'employee', child: Text('Employé')),
            DropdownMenuItem(value: 'manager', child: Text('Responsable')),
            DropdownMenuItem(value: 'admin', child: Text('Administrateur')),
            DropdownMenuItem(value: 'observer', child: Text('Observateur')),
          ],
          onChanged: _busy ? null : (v) => setState(() => _role = v ?? _role),
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_error!),
          ),
        ],

        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.key),
          label: const Text('Générer le code'),
        ),
      ],
    );
  }

  Widget _ready(ThemeData theme, Invitation invitation) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Code prêt', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SelectableText(
                invitation.code,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              if (invitation.expiresAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Valable jusqu’au '
                  '${DateFormat('d MMMM y', 'fr_FR').format(invitation.expiresAt!)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Sending it is the point of this sheet, so it is the filled button.
        FilledButton.icon(
          onPressed: () => SharePlus.instance.share(
            ShareParams(text: invitation.message),
          ),
          icon: const Icon(Icons.send),
          label: const Text('Envoyer par WhatsApp ou SMS'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            // Captured before the await: this is a State, so the analyzer
            // wants the State's own mounted check rather than the context's.
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: invitation.code));
            if (!mounted) return;
            messenger.showSnackBar(
              const SnackBar(content: Text('Code copié.')),
            );
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copier le code'),
        ),

        const SizedBox(height: 20),
        // For the case this app was built for in the first place: the new
        // employee is standing right there, and pointing one phone at another
        // is faster than reading eight characters aloud in a market.
        Center(
          child: QrImageView(
            data: invitation.code,
            size: 160,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ou faites-lui scanner ce code s’il est à côté de vous.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),

        const SizedBox(height: 20),
        TextButton(
          onPressed: () => setState(() {
            _invitation = null;
            _name.clear();
            _title.clear();
            _phone.clear();
          }),
          child: const Text('Inviter quelqu’un d’autre'),
        ),
      ],
    );
  }
}

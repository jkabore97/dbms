import 'package:flutter/material.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/auth_repository.dart';

/// The invited person's side: type the code, see whose business it is, join.
///
/// The preview is the whole reason this is a screen rather than a dialog. A
/// code alone is meaningless — the server answers with the name of the
/// business it belongs to, and only then does anyone tap Join. Nobody should
/// be asked to accept a grant into something they cannot see the name of.
///
/// That preview is deliberately thin. `invitation_preview()` in 005 returns
/// the business name and nothing else: not the role, not who invited them, not
/// whether the code has already been used. A stranger typing codes at random
/// learns nothing worth having.
class JoinByCodeScreen extends StatefulWidget {
  const JoinByCodeScreen({
    super.key,
    required this.admin,
    this.initialCode,
  });

  final AdminRepository admin;
  final String? initialCode;

  @override
  State<JoinByCodeScreen> createState() => _JoinByCodeScreenState();
}

class _JoinByCodeScreenState extends State<JoinByCodeScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialCode ?? '');

  String? _orgName;
  bool _checking = false;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.initialCode ?? '').isNotEmpty) _preview();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A code is 8 characters however it is punctuated, so there is no point
  /// asking the server before that many have been typed.
  bool get _looksComplete =>
      _controller.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').length >= 8;

  Future<void> _preview() async {
    setState(() {
      _checking = true;
      _error = null;
      _orgName = null;
    });

    try {
      final name = await widget.admin.previewInvitation(_controller.text.trim());
      if (!mounted) return;
      setState(() {
        _orgName = name;
        _checking = false;
        if (name == null) {
          _error = 'Code inconnu, déjà utilisé ou expiré. '
              'Vérifiez les caractères saisis.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _checking = false;
      });
    }
  }

  Future<void> _join() async {
    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      await widget.admin.claimInvitation(_controller.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _joining = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _checking || _joining;

    return Scaffold(
      appBar: AppBar(title: const Text("J'ai un code")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Entrez le code reçu',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Le responsable de votre activité vous l\'a communiqué de '
                  'vive voix, par écrit ou par QR code.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),

                TextField(
                  controller: _controller,
                  enabled: !busy,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'ABCD-2345',
                    // Without this the field's accessible name is the example
                    // code, so a screen reader announces "ABCD-2345" as the
                    // name of the box rather than as a sample of what goes in.
                    labelText: "Code d'invitation",
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  onChanged: (_) {
                    // Unconditionally: the Verify button is enabled off
                    // _looksComplete, which is recomputed on build, so a
                    // conditional setState here leaves it greyed out no matter
                    // how much is typed. Any edit also invalidates the
                    // business named below it.
                    setState(() {
                      _orgName = null;
                      _error = null;
                    });
                  },
                  onSubmitted: (_) {
                    if (_looksComplete && !busy) _preview();
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],

                if (_orgName != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Vous rejoignez',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _orgName!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: _orgName == null
                      ? FilledButton(
                          onPressed:
                              (!_looksComplete || busy) ? null : _preview,
                          child: _checking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Vérifier le code',
                                  style: TextStyle(fontSize: 17),
                                ),
                        )
                      : FilledButton.icon(
                          onPressed: busy ? null : _join,
                          icon: _joining
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: const Text(
                            'Rejoindre',
                            style: TextStyle(fontSize: 17),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../core/auth/auth_repository.dart';

/// The way in.
///
/// Phone and SMS code is the default and the first thing on screen. Email and
/// password is one tap away, folded up, because for most people here it is the
/// wrong answer — they do not have an email address, and asking for one first
/// is how an app tells someone it was not built for them.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.onSignedIn,
  });

  final AuthRepository auth;

  /// Called once Supabase has confirmed the user. The caller is responsible
  /// for storing the identity and resolving orgs.
  final Future<void> Function(User user) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Method { phone, email }

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _Method _method = _Method.phone;

  /// Set once the code has been sent, and holds the E.164 number the code was
  /// sent to — the field the user typed is not re-read, so editing it after
  /// the fact cannot verify a code against the wrong number.
  String? _awaitingCodeFor;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = AuthRepository.describeError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() {
    final phone = AuthRepository.normalizePhone(_phoneController.text);
    if (phone.length < 8) {
      setState(() => _error = 'Entrez un numéro de téléphone valide.');
      return Future.value();
    }

    return _run(() async {
      await widget.auth.sendPhoneOtp(phone);
      if (mounted) setState(() => _awaitingCodeFor = phone);
    });
  }

  Future<void> _verifyCode() {
    final phone = _awaitingCodeFor;
    if (phone == null) return Future.value();

    return _run(() async {
      final response = await widget.auth.verifyPhoneOtp(
        phone: phone,
        token: _otpController.text.trim(),
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Connexion refusée. Réessayez.');
      }
      await widget.onSignedIn(user);
    });
  }

  Future<void> _signInWithEmail() {
    return _run(() async {
      final response = await widget.auth.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Connexion refusée. Réessayez.');
      }
      await widget.onSignedIn(user);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              children: [
                const SizedBox(height: 16),
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Kaj',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connectez-vous pour ouvrir votre activité.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                if (!widget.auth.isConfigured)
                  _NoBackendNotice(theme: theme)
                else if (_awaitingCodeFor != null)
                  ..._otpStep(theme)
                else if (_method == _Method.phone)
                  ..._phoneStep(theme)
                else
                  ..._emailStep(theme),

                if (_error != null) ...[
                  const SizedBox(height: 20),
                  _ErrorBanner(message: _error!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Step 1a: the phone number
  // ----------------------------------------------------------------
  List<Widget> _phoneStep(ThemeData theme) {
    return [
      TextField(
        controller: _phoneController,
        enabled: !_busy,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        style: const TextStyle(fontSize: 20, letterSpacing: 1.2),
        decoration: const InputDecoration(
          labelText: 'Numéro de téléphone',
          hintText: '70 12 34 56',
          prefixText: '+226  ',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _busy ? null : _sendCode(),
      ),
      const SizedBox(height: 8),
      Text(
        'Vous recevrez un code par SMS.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      _PrimaryButton(
        label: 'Recevoir le code',
        busy: _busy,
        onPressed: _sendCode,
      ),
      const SizedBox(height: 24),
      TextButton.icon(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _method = _Method.email;
                  _error = null;
                }),
        icon: const Icon(Icons.alternate_email, size: 18),
        label: const Text('Utiliser un e-mail et un mot de passe'),
      ),
    ];
  }

  // ----------------------------------------------------------------
  // Step 1b: the SMS code
  // ----------------------------------------------------------------
  List<Widget> _otpStep(ThemeData theme) {
    return [
      Text(
        'Code envoyé au $_awaitingCodeFor',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _otpController,
        enabled: !_busy,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        autofillHints: const [AutofillHints.oneTimeCode],
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 32,
          letterSpacing: 12,
          fontWeight: FontWeight.bold,
        ),
        decoration: const InputDecoration(
          labelText: 'Code à 6 chiffres',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _busy ? null : _verifyCode(),
      ),
      const SizedBox(height: 20),
      _PrimaryButton(
        label: 'Se connecter',
        busy: _busy,
        onPressed: _verifyCode,
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _awaitingCodeFor = null;
                      _otpController.clear();
                      _error = null;
                    }),
            child: const Text('Changer de numéro'),
          ),
          TextButton(
            onPressed: _busy ? null : _sendCode,
            child: const Text('Renvoyer'),
          ),
        ],
      ),
    ];
  }

  // ----------------------------------------------------------------
  // The secondary route
  // ----------------------------------------------------------------
  List<Widget> _emailStep(ThemeData theme) {
    return [
      TextField(
        controller: _emailController,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(
          labelText: 'E-mail',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _passwordController,
        enabled: !_busy,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(
          labelText: 'Mot de passe',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _busy ? null : _signInWithEmail(),
      ),
      const SizedBox(height: 20),
      _PrimaryButton(
        label: 'Se connecter',
        busy: _busy,
        onPressed: _signInWithEmail,
      ),
      const SizedBox(height: 24),
      TextButton.icon(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _method = _Method.phone;
                  _error = null;
                }),
        icon: const Icon(Icons.sms_outlined, size: 18),
        label: const Text('Utiliser mon numéro de téléphone'),
      ),
    ];
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the build has no Supabase credentials compiled in. Without them
/// there is nobody to sign in against, and saying so beats a login form that
/// can only fail.
class _NoBackendNotice extends StatelessWidget {
  const _NoBackendNotice({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Serveur non configuré',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            "Cette version a été compilée sans adresse de serveur, donc la "
            'connexion est impossible. Reconstruisez avec :\n\n'
            '  --dart-define=SUPABASE_URL=…\n'
            '  --dart-define=SUPABASE_PUBLISHABLE_KEY=…',
          ),
        ],
      ),
    );
  }
}

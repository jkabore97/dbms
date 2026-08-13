import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../core/auth/auth_repository.dart';

/// The way in — and, now, the way to get an account in the first place.
///
/// Until this screen had a "Créer un compte" side, the only way into the app
/// was to be invited by someone who already had it, and the only person who
/// could be first was Kaj-consulting running an INSERT. That is a fine model
/// for a demo and an impossible one for a product: a business owner who hears
/// about the app cannot start, and an employee handed a code cannot use it,
/// because there is no account for the code to attach to.
///
/// The order is deliberate and it is the order the user asked for: make the
/// account, then join the business. They are separate acts and the app now
/// says so. Signing up gets you as far as the waiting screen; the invitation
/// code, typed there or swept up automatically, is what gets you into somebody
/// else's books. Nothing about creating an account grants access to anything.
///
/// Phone and SMS code stays the default and the first thing on screen. Email
/// and password is one tap away, folded up, because for most people here it is
/// the wrong answer — they do not have an email address, and asking for one
/// first is how an app tells someone it was not built for them.
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

/// Signing in and signing up are the same three fields in a different order
/// with a different meaning, and conflating them is what produced accidental
/// duplicate accounts. Held as state rather than as two screens because the
/// person who picked wrong needs one tap to fix it, not a back button.
enum _Intent { signIn, signUp }

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _Intent _intent = _Intent.signIn;
  _Method _method = _Method.phone;

  /// Set once the code has been sent, and holds the E.164 number the code was
  /// sent to — the field the user typed is not re-read, so editing it after
  /// the fact cannot verify a code against the wrong number.
  String? _awaitingCodeFor;

  /// Set when an email sign-up succeeded but the project requires the address
  /// to be confirmed. The account exists and nobody is signed in, which is
  /// neither success nor failure and needs its own words.
  bool _awaitingEmailConfirmation = false;

  bool _busy = false;
  String? _error;

  bool get _isSignUp => _intent == _Intent.signUp;

  @override
  void dispose() {
    _nameController.dispose();
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

  void _switchIntent(_Intent intent) {
    if (_busy || intent == _intent) return;
    setState(() {
      _intent = intent;
      _error = null;
      // A code sent for one intent must not be verified under the other: an
      // SMS sent to an existing account is not a sign-up, whatever the toggle
      // says by the time the six digits arrive.
      _awaitingCodeFor = null;
      _awaitingEmailConfirmation = false;
      _otpController.clear();
    });
  }

  // ----------------------------------------------------------------
  // Phone
  // ----------------------------------------------------------------

  Future<void> _sendCode() {
    final phone = AuthRepository.normalizePhone(_phoneController.text);
    if (phone.length < 8) {
      setState(() => _error = 'Entrez un numéro de téléphone valide.');
      return Future.value();
    }

    return _run(() async {
      if (_isSignUp) {
        await widget.auth.sendSignUpOtp(phone, fullName: _nameController.text);
      } else {
        await widget.auth.sendPhoneOtp(phone);
      }
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
      await _finish(user);
    });
  }

  // ----------------------------------------------------------------
  // Email
  // ----------------------------------------------------------------

  Future<void> _submitEmail() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!email.contains('@')) {
      setState(() => _error = 'Entrez une adresse e-mail valide.');
      return Future.value();
    }
    if (_isSignUp && password.length < 6) {
      setState(
        () => _error = 'Le mot de passe doit contenir au moins 6 caractères.',
      );
      return Future.value();
    }

    return _run(() async {
      final response = _isSignUp
          ? await widget.auth.signUpWithEmail(
              email: email,
              password: password,
              fullName: _nameController.text,
            )
          : await widget.auth.signInWithEmail(email: email, password: password);

      final user = response.user;
      if (user == null) {
        throw StateError('Connexion refusée. Réessayez.');
      }

      // Signed up into a project that confirms addresses: the account is real
      // and there is no session behind it yet.
      if (_isSignUp && response.session == null) {
        if (mounted) setState(() => _awaitingEmailConfirmation = true);
        return;
      }

      await _finish(user);
    });
  }

  /// The last step of both routes. The name is saved before the caller is
  /// told, so the members list an admin opens a minute later has a name in it.
  Future<void> _finish(User user) async {
    if (_isSignUp) {
      await widget.auth.saveMyName(_nameController.text);
    }
    await widget.onSignedIn(user);
  }

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------

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
                  _isSignUp
                      ? 'Créez votre compte. Vous rejoindrez une activité '
                          'ensuite, avec un code.'
                      : 'Connectez-vous pour ouvrir votre activité.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                if (widget.auth.isConfigured) ...[
                  _IntentSwitch(
                    intent: _intent,
                    enabled: !_busy,
                    onChanged: _switchIntent,
                  ),
                  const SizedBox(height: 24),
                ],

                if (!widget.auth.isConfigured)
                  _NoBackendNotice(theme: theme)
                else if (_awaitingEmailConfirmation)
                  ..._confirmEmailStep(theme)
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

  /// The name field, shown only while creating an account.
  ///
  /// Optional on purpose. It is the one field here that nothing technical
  /// depends on, and a required field is a wall in front of someone who is
  /// standing next to the person who invited them and just wants in. It is
  /// asked for because the alternative is an admin looking at a members list
  /// of seven phone numbers.
  List<Widget> _nameField(ThemeData theme) {
    if (!_isSignUp) return const [];
    return [
      TextField(
        controller: _nameController,
        enabled: !_busy,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        decoration: const InputDecoration(
          labelText: 'Votre nom',
          hintText: 'Comment on vous appelle',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ----------------------------------------------------------------
  // Step 1a: the phone number
  // ----------------------------------------------------------------
  List<Widget> _phoneStep(ThemeData theme) {
    return [
      ..._nameField(theme),
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
        label: _isSignUp ? 'Créer mon compte' : 'Recevoir le code',
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
        label: _isSignUp ? 'Terminer' : 'Se connecter',
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
      ..._nameField(theme),
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
        autofillHints: [
          _isSignUp ? AutofillHints.newPassword : AutofillHints.password,
        ],
        decoration: InputDecoration(
          labelText: 'Mot de passe',
          helperText: _isSignUp ? 'Au moins 6 caractères' : null,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _busy ? null : _submitEmail(),
      ),
      const SizedBox(height: 20),
      _PrimaryButton(
        label: _isSignUp ? 'Créer mon compte' : 'Se connecter',
        busy: _busy,
        onPressed: _submitEmail,
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

  /// The account was created and the address has to be confirmed before there
  /// is a session. Saying "compte créé" and stopping would leave someone
  /// tapping a sign-in button that will keep refusing them.
  List<Widget> _confirmEmailStep(ThemeData theme) {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mark_email_read_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compte créé',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Un message a été envoyé à ${_emailController.text.trim()}. '
              'Ouvrez le lien qu\'il contient, puis revenez vous connecter.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _PrimaryButton(
        label: 'Se connecter',
        busy: _busy,
        onPressed: () => setState(() {
          _intent = _Intent.signIn;
          _awaitingEmailConfirmation = false;
          _error = null;
        }),
      ),
    ];
  }
}

/// Two words, side by side, with the current one filled in. A link reading
/// "pas encore de compte ?" at the bottom of a form is the conventional
/// answer and it is the wrong one here: it is small, it is last, and half the
/// people who need it are reading in poor light on a cracked screen.
class _IntentSwitch extends StatelessWidget {
  const _IntentSwitch({
    required this.intent,
    required this.enabled,
    required this.onChanged,
  });

  final _Intent intent;
  final bool enabled;
  final ValueChanged<_Intent> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Intent>(
      segments: const [
        ButtonSegment(
          value: _Intent.signIn,
          label: Text('Se connecter'),
          icon: Icon(Icons.login, size: 18),
        ),
        ButtonSegment(
          value: _Intent.signUp,
          label: Text('Créer un compte'),
          icon: Icon(Icons.person_add_alt, size: 18),
        ),
      ],
      selected: {intent},
      showSelectedIcon: false,
      onSelectionChanged:
          enabled ? (selection) => onChanged(selection.first) : null,
    );
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

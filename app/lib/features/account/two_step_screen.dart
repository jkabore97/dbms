import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/two_step.dart';
import '../../core/errors.dart';

/// The platform admin's second step (077).
///
/// Two faces. An account with no authenticator app yet is shown how to add
/// one — a QR code for a laptop, a button that opens the app on this phone,
/// the key to type by hand — and confirms with its first code. An account
/// that has one is asked for the code, once per sign-in.
///
/// There is no way past this page but the code or signing out: the server
/// refuses this account everything else until the token has passed.
class TwoStepScreen extends StatefulWidget {
  const TwoStepScreen({
    super.key,
    required this.twoStep,
    required this.enrolled,
    required this.onPassed,
    required this.onSignOut,
  });

  final TwoStep twoStep;
  final bool enrolled;
  final Future<void> Function() onPassed;
  final Future<void> Function() onSignOut;

  @override
  State<TwoStepScreen> createState() => _TwoStepScreenState();
}

class _TwoStepScreenState extends State<TwoStepScreen> {
  final _code = TextEditingController();
  TwoStepEnrollment? _enrollment;
  String? _factorId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _enrolling => !widget.enrolled;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_enrolling) {
        final e = await widget.twoStep.enroll();
        _enrollment = e;
        _factorId = e.factorId;
      } else {
        _factorId = await widget.twoStep.verifiedFactorId();
        if (_factorId == null) {
          _error =
              "Aucune application n'est enregistrée pour ce compte. "
              'Déconnectez-vous puis reconnectez-vous pour en ajouter une.';
        }
      }
    } catch (e) {
      _error = describeError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit() async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    final factor = _factorId;
    if (factor == null || _busy) return;
    if (code.length != 6) {
      setState(() => _error = 'Le code a 6 chiffres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.twoStep.verify(factor, code);
      if (_enrolling) await widget.twoStep.logEnabled();
      await widget.onPassed();
    } on AuthException {
      if (mounted) {
        setState(
          () => _error =
              'Code incorrect ou expiré. '
              'Entrez le code affiché maintenant dans l’application.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openApp(String uri) async {
    final ok = await launchUrl(
      Uri.parse(uri),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      setState(
        () => _error =
            "Aucune application d'authentification n'a "
            'répondu. Installez-en une, ou tapez la clé ci-dessous.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Validation en deux étapes'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 44,
                        color: t.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _enrolling
                            ? 'Protégez le compte de la plateforme'
                            : 'Code de votre application',
                        textAlign: TextAlign.center,
                        style: t.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _enrolling
                            ? 'Ce compte gère toutes les entreprises. Pour '
                                  "l'ouvrir, il faudra désormais votre mot de "
                                  'passe et un code à 6 chiffres donné par une '
                                  'application sur votre téléphone.'
                            : "Ouvrez votre application d'authentification "
                                  'et entrez le code à 6 chiffres affiché pour '
                                  'Kaj.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      if (_enrolling && _enrollment != null)
                        ..._enrollSteps(t, _enrollment!),
                      if (_factorId != null) ...[
                        TextField(
                          key: const Key('two-step-code'),
                          controller: _code,
                          autofocus: !_enrolling,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: t.textTheme.headlineSmall?.copyWith(
                            letterSpacing: 8,
                          ),
                          decoration: const InputDecoration(
                            hintText: '000000',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(
                            _busy
                                ? 'Vérification…'
                                : _enrolling
                                ? 'Activer'
                                : 'Valider',
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: t.colorScheme.error),
                        ),
                        if (_factorId == null)
                          TextButton(
                            onPressed: _prepare,
                            child: const Text('Réessayer'),
                          ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        _enrolling
                            ? 'À l’activation, les autres appareils connectés '
                                  'à ce compte sont déconnectés.'
                            : 'Téléphone perdu ? Dans le tableau de bord '
                                  'Supabase : Authentication › Users › ce compte '
                                  '› supprimez son facteur. Kaj proposera alors '
                                  "d'en ajouter un nouveau.",
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : widget.onSignOut,
                        child: const Text('Se déconnecter'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _enrollSteps(ThemeData t, TwoStepEnrollment e) {
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 12, child: Text(n)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: t.textTheme.bodyMedium)),
        ],
      ),
    );
    final key = e.secret
        .replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ')
        .trim();
    return [
      step(
        '1',
        'Installez Google Authenticator ou Microsoft Authenticator '
            '(Play Store).',
      ),
      step(
        '2',
        'Ajoutez Kaj : scannez ce code depuis un autre écran, ou '
            'touchez le bouton sur ce téléphone.',
      ),
      const SizedBox(height: 8),
      Center(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: QrImageView(data: e.uri, size: 180),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _openApp(e.uri),
        icon: const Icon(Icons.open_in_new),
        label: const Text("Ouvrir l'application d'authentification"),
      ),
      const SizedBox(height: 8),
      Text(
        'Ou tapez cette clé dans l’application :',
        textAlign: TextAlign.center,
        style: t.textTheme.bodySmall,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: SelectableText(
              key,
              key: const Key('two-step-secret'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            tooltip: 'Copier la clé',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: e.secret)),
          ),
        ],
      ),
      const SizedBox(height: 12),
      step('3', "Entrez le code à 6 chiffres que l'application affiche."),
      const SizedBox(height: 4),
    ];
  }
}

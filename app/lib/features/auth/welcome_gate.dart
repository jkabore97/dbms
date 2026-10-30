import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/router.dart';
import '../../core/nav/session.dart';
import '../../core/theme/mara_mark.dart';

/// « Créez votre compte » before the street (batch 152).
///
/// The owner's advertisement sent three thousand people to marakaj.com in a
/// day and almost none of them made an account: the street is open signed
/// out, so a visitor looks around and leaves. Now a visitor who is not
/// signed in sees the street for a moment, dimmed under a sheet with no
/// close — Google, an e-mail account, or « Se connecter » — the way
/// Pinterest greets a stranger.
///
/// Where it stands: the street only (`/` and `/vitrines`). A shop's own
/// vitrine (`/s/<slug>`) stays open: the link a shop sends its customers
/// must not greet them with a wall; they are asked when they order (F1).
/// The sign-in page and the legal pages are where the sheet sends people,
/// so they are never gated. Somebody signed in never sees it; while the
/// session is still being read at start, nothing is shown either, so a
/// member reloading the page does not see the sheet flash.
///
/// [kWelcomeGate] switches it off in one line, should the numbers say the
/// wall sends more people away than it signs up.
const kWelcomeGate = true;

/// Whether the gate stands over [path] for somebody in [phase].
bool welcomeGateShows(SessionPhase phase, String path) {
  if (!kWelcomeGate || phase != SessionPhase.signedOut) return false;
  return path == '/' ||
      path == Routes.directory ||
      path.startsWith('${Routes.directory}/');
}

class WelcomeGate extends StatefulWidget {
  const WelcomeGate({
    super.key,
    required this.session,
    required this.router,
    required this.auth,
    required this.child,
  });

  final SessionController session;
  final GoRouter router;
  final AuthRepository auth;
  final Widget child;

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  /// Google is offered once the project says it is on, as on the sign-in
  /// screen; a build with no server shows e-mail only.
  bool _google = false;
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.auth.isConfigured) {
      unawaited(widget.auth.googleAvailable().then((on) {
        if (mounted && on) setState(() => _google = true);
      }).catchError((_) {}));
    }
  }

  /// Leaves for Google. On the web the person comes back as a reload and
  /// the session controller takes it from there; the gate then finds them
  /// signed in and is gone.
  Future<void> _continueWithGoogle() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.session.signInWithGoogle();
    } catch (e) {
      if (mounted) setState(() => _problem = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The address is read from the router's route-information provider,
    // not its delegate: the delegate tells of the first address while the
    // Router is still being built, which a widget above it may not answer
    // with a rebuild; the provider is told after the frame.
    return ListenableBuilder(
      listenable: Listenable.merge([widget.session, widget.router.routeInformationProvider]),
      builder: (context, _) {
        final path = widget.router.routeInformationProvider.value.uri.path;
        final up = welcomeGateShows(widget.session.phase, path);
        return Stack(
          fit: StackFit.expand,
          children: [
            // The street stays mounted and alive under the sheet (its map,
            // its photos), out of reach of a finger or a screen reader.
            ExcludeFocus(
              excluding: up,
              child: ExcludeSemantics(
                excluding: up,
                child: AbsorbPointer(absorbing: up, child: widget.child),
              ),
            ),
            if (up)
              Positioned.fill(
                child: _WelcomeSheet(
                  key: const Key('welcome-gate'),
                  google: _google,
                  busy: _busy,
                  problem: _problem,
                  onGoogle: _continueWithGoogle,
                  onEmail: () => widget.router.go('${Routes.signIn}?compte=nouveau'),
                  onSignIn: () => widget.router.go(Routes.signIn),
                  onTerms: () => widget.router.push(Routes.terms),
                  onPrivacy: () => widget.router.push(Routes.privacy),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The sheet: the street dimmed and softened behind, the seal, three ways
/// in, the two legal texts a tap away.
class _WelcomeSheet extends StatelessWidget {
  const _WelcomeSheet({
    super.key,
    required this.google,
    required this.busy,
    required this.problem,
    required this.onGoogle,
    required this.onEmail,
    required this.onSignIn,
    required this.onTerms,
    required this.onPrivacy,
  });

  final bool google;
  final bool busy;
  final String? problem;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;
  final VoidCallback onSignIn;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linkStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // A glimpse of the street, not the street: blurred and dimmed.
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: ColoredBox(color: Colors.black.withValues(alpha: .48)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(context).height * .9,
            ),
            child: Material(
              color: scheme.surface,
              elevation: 12,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: MaraMark(size: 72)),
                      const SizedBox(height: 18),
                      Text(
                        context.tr('Bienvenue sur Marakaj'),
                        key: const Key('welcome-title'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.tr(
                          'Créez votre compte gratuit pour découvrir les boutiques, fermes et associations près de chez vous, commander, et ouvrir votre propre vitrine.',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('5 000 cauris offerts à chaque nouvelle entreprise.'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (google) ...[
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            key: const Key('welcome-google'),
                            onPressed: busy ? null : onGoogle,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (busy)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  const Text(
                                    'G',
                                    textScaler: TextScaler.noScaling,
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(context.tr('Continuer avec Google')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        height: 52,
                        child: google
                            ? OutlinedButton(
                                key: const Key('welcome-email'),
                                onPressed: busy ? null : onEmail,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(context.tr('Créer un compte avec mon e-mail')),
                                ),
                              )
                            : FilledButton(
                                key: const Key('welcome-email'),
                                onPressed: busy ? null : onEmail,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(context.tr('Créer un compte avec mon e-mail')),
                                ),
                              ),
                      ),
                      if (problem != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          problem!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('welcome-sign-in'),
                        onPressed: busy ? null : onSignIn,
                        child: Text(context.tr('Déjà membre ? Se connecter')),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            context.tr('En continuant, vous acceptez les '),
                            style: theme.textTheme.bodySmall,
                          ),
                          InkWell(
                            onTap: onTerms,
                            child: Text(context.tr("Conditions d'utilisation"), style: linkStyle),
                          ),
                          Text(context.tr(' et la '), style: theme.textTheme.bodySmall),
                          InkWell(
                            onTap: onPrivacy,
                            child: Text(context.tr('Politique de confidentialité'), style: linkStyle),
                          ),
                          Text('.', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

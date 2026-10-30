import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:go_router/go_router.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton;

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
/// close, the way Pinterest greets a stranger. The owner's words: « give
/// them the two options, Google and Apple, for the website; just Google on
/// the app; do not allow them to bypass that pop-up ».
///
/// So the sheet offers the social doors only — « Continuer avec Google »,
/// and « Continuer avec Apple » on the website (Réglages' « Connexion
/// Apple sur le site ») and the iPhone app, never on Android — plus
/// « Déjà membre ? Se connecter » for the members who have an e-mail
/// account, which is a way *in*, not around. The e-mail sign-up appears
/// only in a project with neither Google nor Apple on, so nobody is ever
/// locked out of making an account. Android's back on the sheet leaves
/// the app (BackFirst, through [handleBack]) rather than opening the
/// router's « Quitter ? » under it, unseen.
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

  /// Whether the sheet is up right now (main.dart's back).
  static bool isUp(SessionController session, GoRouter router) =>
      welcomeGateShows(session.phase, router.routerDelegate.currentConfiguration.uri.path);

  /// Android's back while the sheet is up (main.dart, through BackFirst,
  /// after the terms gate's own answer): the phone leaves the app, as from
  /// any first page — never the router's « Quitter ? » hidden under the
  /// sheet. Null when no sheet is shown: the back is the app's as before.
  static Future<bool?> handleBack(SessionController session, GoRouter router) async {
    if (!isUp(session, router)) return null;
    unawaited(SystemNavigator.pop());
    return true;
  }

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  /// « Continuer avec Google »: the project has it on, as on the sign-in
  /// screen.
  bool _google = false;

  /// « Continuer avec Apple »: the iPhone app with Apple on in the
  /// project, or the website with Réglages' « Connexion Apple sur le
  /// site » on. Never Android.
  bool _apple = false;
  bool _busy = false;
  String? _problem;

  /// The address the router is at. Its delegate tells of a change while
  /// it is itself being built (the first address, a redirect), which a
  /// widget above it may not answer with a rebuild there and then; so the
  /// change is taken after the frame. The route-information provider
  /// would not do: it is told of a redirect without telling anybody.
  late String _path = widget.router.routerDelegate.currentConfiguration.uri.path;

  void _onRoute() {
    final path = widget.router.routerDelegate.currentConfiguration.uri.path;
    if (path == _path) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _path != path) setState(() => _path = path);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_onRoute);
    if (!widget.auth.isConfigured) return;
    unawaited(widget.auth.googleAvailable().then((on) {
      if (mounted && on) setState(() => _google = true);
    }).catchError((_) {}));
    if (appleSignInPlatform || appleWebPlatform) {
      unawaited((appleSignInPlatform ? widget.auth.appleAvailable() : widget.auth.appleWebAvailable()).then((on) {
        if (mounted && on) setState(() => _apple = true);
      }).catchError((_) {}));
    }
  }

  /// Leaves for Google. On the web the person comes back as a reload and
  /// the session controller takes it from there; the gate then finds them
  /// signed in and is gone.
  Future<void> _continueWithGoogle() => _run(widget.session.signInWithGoogle);

  /// Apple's own sheet (the iPhone's, or the website's popup): the session
  /// is in hand when it closes; closing it without signing does nothing.
  Future<void> _continueWithApple() => _run(() => widget.session.signInWithApple());

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _problem = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final up = welcomeGateShows(widget.session.phase, _path);
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
                  apple: _apple,
                  busy: _busy,
                  problem: _problem,
                  onGoogle: _continueWithGoogle,
                  onApple: _continueWithApple,
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

/// The sheet: the street dimmed and softened behind, the seal, the doors
/// in, the two legal texts a tap away.
class _WelcomeSheet extends StatelessWidget {
  const _WelcomeSheet({
    super.key,
    required this.google,
    required this.apple,
    required this.busy,
    required this.problem,
    required this.onGoogle,
    required this.onApple,
    required this.onEmail,
    required this.onSignIn,
    required this.onTerms,
    required this.onPrivacy,
  });

  final bool google;
  final bool apple;
  final bool busy;
  final String? problem;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
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
    // A project with neither social door on (a build with no server, a
    // project with both switched off): the e-mail account, so nobody is
    // locked out of making one.
    final emailOnly = !google && !apple;
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
                      if (apple) ...[
                        // Apple's own button (its logo, its black), with
                        // Marakaj's words, sized as the sign-in screen's.
                        MediaQuery.withNoTextScaling(
                          child: SignInWithAppleButton(
                            key: const Key('welcome-apple'),
                            text: context.tr('Continuer avec Apple'),
                            height: 52,
                            borderRadius: const BorderRadius.all(Radius.circular(26)),
                            onPressed: busy ? null : onApple,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
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
                      ],
                      if (emailOnly)
                        SizedBox(
                          height: 52,
                          child: FilledButton(
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

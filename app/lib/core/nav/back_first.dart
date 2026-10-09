import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/business_frame.dart' show UnsavedInput;
import '../l10n/tr.dart';
import 'parent_route.dart';

/// Back closes what is open first (114): a dialog, a sheet, a menu, a date
/// picker, the Plus sheet, a snackbar with an action — and only then leaves
/// the page. The whole app, one mechanism.
///
/// Three reasons it did not, each fixed here:
///
///  * **Android** (FlutterFragmentActivity): the phone hands its back to the
///    app only while the app last said it can handle one
///    (`SystemNavigator.setFrameworkHandlesBack`). That word is the last
///    navigator's to change — and there are two of them inside a business
///    (the router's and the frame's, 108): a sheet on the frame's, a dialog
///    from it on the router's, the dialog closed — the router's navigator
///    says « nothing to pop » with the sheet still open, and the next back
///    left the app. Now the app always takes the back
///    ([onNavigationNotification]); when nothing is open and no page is left
///    to go back to, the router answers no and Flutter hands the back to the
///    phone (`SystemNavigator.pop`), which leaves as before.
///  * **The web**: the browser's back is a change of address, not a pop —
///    the router drew the page before, and the sheet went with the page it
///    covered. While something is open, that change is turned into closing
///    it, and the address of the page stays ([didPushRouteInformation]).
///  * **A snackbar** is not a route: back went past it. One with an action
///    (« Annuler », « Réessayer ») is closed by back when nothing covers the
///    page.
///  * **A page with nothing under it** (122) — opened with `go`, by the
///    bar, a link or a ring: Android's back left the app from it. Now it
///    goes to the page's logical parent ([parentRoute]: a tool → its
///    business's home, the home → the picker for someone with several
///    businesses, a vitrine → the street); from a root (the street, the
///    only business's home) it asks « Quitter Mara ? » once instead of
///    closing without a word. A page holding input not saved (108's
///    [UnsavedInput]) asks « Quitter sans enregistrer ? » first.
///
/// What is open is read off every navigator of the router ([watch] on the
/// router's observers: go_router 18 tells them of the frame's and the
/// command center's navigators too). The closing itself stays the router's
/// (`popRoute`: the deepest open navigator first, a PopScope still heard).
class BackFirst with WidgetsBindingObserver {
  BackFirst();

  /// The app's: the router of main.dart and every business, street and
  /// center page in it.
  static final instance = BackFirst();

  /// The app's ScaffoldMessenger (MaterialApp.scaffoldMessengerKey): where
  /// every snackbar of the app is shown.
  final messenger = GlobalKey<ScaffoldMessengerState>();

  /// Whether a pushed address is the browser's back or forward. Only on the
  /// web: on Android a pushed address is a link opened from outside (the
  /// sign-in's return), never to be swallowed. Tests of the web set it.
  @visibleForTesting
  bool browserHistory = kIsWeb;

  final List<Route<dynamic>> _open = [];
  GoRouter? _router;
  bool _listening = false;

  /// How many businesses the person can open: the home's parent is the
  /// picker for more than one.
  int Function() _businesses = () => 0;

  /// « Quitter Mara ? » is on screen: a second back answers it (closes it),
  /// it is never asked twice over itself.
  bool _asking = false;

  /// An observer for one router's root navigator (a fresh one per router:
  /// an observer serves one navigator at a time).
  NavigatorObserver watch() => _Watch(this);

  /// Something open over a page: a route of any navigator that is not one
  /// of the router's pages.
  bool get popupOpen {
    _open.removeWhere((r) => !r.isActive);
    return _open.isNotEmpty;
  }

  /// Takes the back and the browser's history for [router]. Called before
  /// the router is first drawn, so the app hears them before the router does.
  void attach(GoRouter router, {int Function()? businesses}) {
    _router = router;
    _businesses = businesses ?? () => 0;
    if (!_listening) {
      WidgetsBinding.instance.addObserver(this);
      _listening = true;
    }
    _takeBack();
  }

  /// Lets go of [router] — and of nothing a newer app attached since.
  void detach(GoRouter router) {
    if (_router != router) return;
    if (_listening) WidgetsBinding.instance.removeObserver(this);
    _listening = false;
    _router = null;
    _open.clear();
    _asking = false;
  }

  /// MaterialApp.onNavigationNotification: whatever a navigator says, the
  /// app takes the back (see above).
  bool onNavigationNotification(NavigationNotification _) {
    _takeBack();
    return true;
  }

  void _takeBack() {
    final state = WidgetsBinding.instance.lifecycleState;
    // As Flutter's own default: no word to the engine before the app is up.
    if (state == null || state == AppLifecycleState.detached) return;
    SystemNavigator.setFrameworkHandlesBack(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _takeBack();

  /// Android's back: something open is the router's to close; a snackbar
  /// with an action is closed here; then the page — popped by the router
  /// when there is one under it (a PopScope still heard), else its parent,
  /// else the question.
  @override
  Future<bool> didPopRoute() async {
    if (popupOpen) return false;
    if (_closeSnackBar()) return true;
    final router = _router;
    // No router drawn (a router left behind by a newer one): not ours.
    if (router == null || router.routerDelegate.navigatorKey.currentState == null) return false;
    if (await router.routerDelegate.popRoute()) return true;
    final here = router.routerDelegate.currentConfiguration.uri.path;
    final parent = parentIn(router, here, businesses: _businesses());
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (parent != null) {
      // Input not saved on this page (108's guard): asked first, as the
      // business's bar asks.
      if (UnsavedInput.dirtyOnTop() && context != null && context.mounted) {
        if (!_asking) unawaited(_leaveUnsaved(context, router, parent));
        return true;
      }
      router.go(parent);
      return true;
    }
    if (context == null || !context.mounted) return false;
    if (!_asking) unawaited(_askToLeave(context));
    return true;
  }

  /// « Quitter sans enregistrer ? » before the parent: « Quitter » goes,
  /// « Rester » keeps the page and what is typed in it.
  Future<void> _leaveUnsaved(BuildContext context, GoRouter router, String parent) async {
    _asking = true;
    try {
      if (await UnsavedInput.askLeave(context) && _router == router) router.go(parent);
    } finally {
      _asking = false;
    }
  }

  /// « Quitter Mara ? » — « Rester » keeps the page, « Quitter » hands the
  /// back to the phone, which closes the app as before. Not awaited by the
  /// back that asked it: the next back closes the question like any dialog.
  Future<void> _askToLeave(BuildContext context) async {
    _asking = true;
    final bool? leave;
    try {
      leave = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          key: const Key('leave-mara'),
          title: Text(dialog.tr('Quitter Mara ?')),
          actions: [
            TextButton(
              key: const Key('leave-stay'),
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(dialog.tr('Rester')),
            ),
            FilledButton(
              key: const Key('leave-quit'),
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(dialog.tr('Quitter')),
            ),
          ],
        ),
      );
    } finally {
      _asking = false;
    }
    if (leave == true) await SystemNavigator.pop();
  }

  /// The browser's back (or forward) while something is open: closed, and
  /// the page's own address put back in the history.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final router = _router;
    if (!browserHistory || router == null) return false;
    if (popupOpen) {
      await router.routerDelegate.popRoute();
    } else if (!_closeSnackBar()) {
      return false;
    }
    final here = router.routeInformationParser
        .restoreRouteInformation(router.routerDelegate.currentConfiguration);
    if (here != null) {
      SystemNavigator.routeInformationUpdated(uri: here.uri, state: here.state);
    }
    return true;
  }

  bool _closeSnackBar() {
    final state = messenger.currentState;
    if (state == null || !_actionSnackBarShown(state.context)) return false;
    state.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
    return true;
  }

  /// A snackbar with an action on screen, and not already leaving.
  static bool _actionSnackBarShown(BuildContext context) {
    var found = false;
    void visit(Element element) {
      if (found) return;
      final widget = element.widget;
      if (widget is SnackBar) {
        final status = widget.animation?.status;
        found = widget.action != null &&
            status != AnimationStatus.reverse &&
            status != AnimationStatus.dismissed;
        if (found) return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return found;
  }
}

class _Watch extends NavigatorObserver {
  _Watch(this._back);

  final BackFirst _back;

  static bool _isPage(Route<dynamic> route) => route.settings is Page;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_isPage(route)) _back._open.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _back._open.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _back._open.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _back._open.remove(oldRoute);
    if (newRoute != null && !_isPage(newRoute)) _back._open.add(newRoute);
  }
}

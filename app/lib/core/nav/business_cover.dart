import 'dart:async';

import 'package:flutter/widgets.dart';

/// Whether something covers the pages of a business (108): a sheet, a menu,
/// a full-screen flow pushed on top — a route of the business's navigator
/// that is not one of its pages.
///
/// The business's frame draws its bar above the pages, so a tap reaches it;
/// while something covers them the bar goes behind, under the sheet's
/// shade, exactly as the home's own bar sat under every sheet before — and
/// comes back on top once the sheet has finished leaving.
///
/// Watches the frame's navigator (the router's ShellRoute observers); the
/// frame listens. Told after the navigator's own work, never during it.
class BusinessCover extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _over = [];

  bool get covered => _over.isNotEmpty;

  static bool _isPage(Route<dynamic> route) => route.settings is Page;

  void _tell() => scheduleMicrotask(notifyListeners);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isPage(route)) return;
    _over.add(route);
    _tell();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_over.contains(route)) return;
    // Back on top only once the sheet is gone: it leaves over the bar, the
    // way it came.
    final animation = route is TransitionRoute ? route.animation : null;
    if (animation == null || animation.isDismissed) {
      _gone(route);
      return;
    }
    void watch(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(watch);
      _gone(route);
    }

    animation.addStatusListener(watch);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _gone(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _over.remove(oldRoute);
    if (newRoute != null && !_isPage(newRoute)) _over.add(newRoute);
    _tell();
  }

  void _gone(Route<dynamic> route) {
    if (_over.remove(route)) _tell();
  }
}

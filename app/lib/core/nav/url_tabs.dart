import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Keeps a screen's tab in its URL — `?onglet=<slug>` — so a refresh, a
/// bookmark or a shared link lands on the same tab instead of the first
/// one. The owner's words: each page its own link.
///
/// The screen names its tabs in order via [tabSlugs] and draws with [tabs].
/// The initial index is read from the address; a change is written back
/// with `replace`, which updates the URL without touching the screen's
/// State — go_router keys a page by its route, not by its query, so the
/// same Element stays mounted and nothing reloads or flickers.
///
/// Outside a router — a bare widget test, say — the mixin degrades to a
/// plain [TabController] and touches no URL at all.
mixin UrlTabsMixin<T extends StatefulWidget> on State<T> {
  /// One slug per tab, in tab order: what `?onglet=` reads and writes.
  List<String> get tabSlugs;

  TabController? _urlTabs;

  /// The controller to hand to both the `TabBar` and the `TabBarView`.
  TabController get tabs => _urlTabs!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once: the first dependency pass is the earliest moment the router's
    // state is readable, and a later pass must not reset the user's tab.
    if (_urlTabs == null) {
      var index = 0;
      if (GoRouter.maybeOf(context) != null) {
        final wanted = GoRouterState.of(context).uri.queryParameters['onglet'];
        final found = tabSlugs.indexOf(wanted ?? '');
        if (found >= 0) index = found;
      }
      _urlTabs = TabController(
        length: tabSlugs.length,
        vsync: this as TickerProvider,
        initialIndex: index,
      )..addListener(_writeTabToUrl);
    }
  }

  void _writeTabToUrl() {
    final controller = _urlTabs!;
    // Mid-swipe the index flaps; only the settled tab belongs in the bar.
    if (controller.indexIsChanging) return;
    if (!mounted || GoRouter.maybeOf(context) == null) return;
    final uri = GoRouterState.of(context).uri;
    final slug = tabSlugs[controller.index];
    if (uri.queryParameters['onglet'] == slug) return;
    context.replace(uri.replace(queryParameters: {
      ...uri.queryParameters,
      'onglet': slug,
    }).toString());
  }

  @override
  void dispose() {
    _urlTabs?.dispose();
    super.dispose();
  }
}

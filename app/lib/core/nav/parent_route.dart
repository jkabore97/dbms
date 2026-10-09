import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_scope.dart';
import 'router.dart';

/// Where « back » goes from a page with nothing under it (122) — the owner:
/// « Every page has a return button and clicking the back button returns
/// to the previous page instead of quitting the app. »
///
/// A page opened with `go` (the bar, the Plus sheet, a link, a ring) has no
/// page under it, so Flutter offers no back arrow and Android's back left
/// the app. Its logical parent is read off its address, the way the router
/// nests its pages:
///
///  * a tool of a business → the page above it, up to the business's home
///    (`/o/<id>/factures/<n>` → `/o/<id>/factures` → `/o/<id>`);
///  * a business's home → the picker for someone with several businesses;
///    for someone with one it is a root (null: back asks « Quitter Mara ? »);
///  * a page of the shopper's account → « Mon compte »; the courier's pages
///    → « Livreur »; a page of the center → its page above, then « À faire »;
///  * a vitrine, « Mes commandes », « Mon compte », the courier's world, the
///    help and legal pages, the sign-in → the street;
///  * the street, the picker, the splash and the gates (code, second step)
///    → roots.
///
/// [exists] says whether an address is one of the router's pages (an
/// address in between two pages, `/s` or `/livreur/course`, is skipped).
/// [businesses] is how many businesses the person can open.
String? parentRoute(String location, {required bool Function(String path) exists, int businesses = 0}) {
  var path = Uri.parse(location).path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  // The picker too: back from it must never fall onto the public street
  // (routing_test: « entering the business world leaves the street
  // behind »); its own button goes there on purpose.
  const roots = {'/', Routes.directory, Routes.picker, Routes.splash, Routes.pin, Routes.twoStep};
  if (roots.contains(path)) return null;
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;

  // Inside a business.
  if (parts.first == 'o' && parts.length >= 2) {
    if (parts.length == 2) return businesses > 1 ? Routes.picker : null;
    for (var n = parts.length - 1; n > 2; n--) {
      final up = '/${parts.take(n).join('/')}';
      if (exists(up)) return up;
    }
    return '/o/${parts[1]}';
  }

  // Deeper than one segment: the nearest page above.
  for (var n = parts.length - 1; n >= 1; n--) {
    final up = '/${parts.take(n).join('/')}';
    if (exists(up)) return up;
  }

  // A first-level page.
  final top = '/${parts.first}';
  if (top == Routes.applications) return Routes.console;
  if (top == Routes.newBusiness || top == Routes.createBusiness) {
    return businesses > 0 ? Routes.picker : Routes.directory;
  }
  return Routes.directory;
}

/// [parentRoute] for [location] in [router]'s pages.
String? parentIn(GoRouter router, String location, {int businesses = 0}) => parentRoute(
      location,
      businesses: businesses,
      exists: (p) => !router.configuration.findMatch(Uri.parse(p)).isError,
    );

/// The AppBar's back arrow for a page with nothing under it (122): null
/// when the page can pop (Flutter's own arrow is there) or is a root;
/// otherwise an arrow to the page's logical parent ([parentRoute]).
///
/// `appBar: AppBar(leading: parentBack(context), …)`.
Widget? parentBack(BuildContext context) {
  if (ModalRoute.of(context)?.impliesAppBarDismissal ?? false) return null;
  final router = GoRouter.maybeOf(context);
  if (router == null) return null;
  final String location;
  try {
    location = GoRouterState.of(context).uri.path;
  } catch (_) {
    return null;
  }
  final parent = parentIn(router, location, businesses: AppScope.read(context)?.session.orgs.length ?? 0);
  if (parent == null) return null;
  return BackButton(key: const Key('parent-back'), onPressed: () => router.go(parent));
}

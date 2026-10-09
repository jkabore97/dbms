import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/nav/router.dart';
import '../../core/notify/notifications_repository.dart';
import 'notifications_screen.dart';

/// The business's bell on every tool page (115), at the right end of the
/// page's own top bar — as the home has it — so a ring is seen from
/// Articles, Commandes, Factures and every other page of the shop, the farm
/// and the association.
///
/// Each page draws its own AppBar, so the bell is laid over the bar's last
/// place and the page's own actions are moved one place left to make room
/// for it (AppBarTheme.actionsPadding): the page keeps every button it had.
/// It is part of the page, under a sheet or a dialog as the page is. The
/// home has its bell already; the list itself needs none.
///
/// A title never runs under it: Flutter pads a bar's actions only when it
/// has some, so every AppBar ends its actions with `bellRoom`
/// (core/notify/bell_room.dart). The bell sits on the row of the page's
/// own bar wherever that is (tabs below it, a wide page's pane, a strip
/// above it), measured once the page is laid out.
class PageBell extends StatefulWidget {
  const PageBell({
    super.key,
    required this.org,
    required this.notify,
    required this.path,
    required this.enabled,
    required this.child,
  });

  final OrgSummary org;
  final NotificationsRepository notify;

  /// This page's own address (`/o/<id>/factures/…`).
  final String path;

  /// Greyed offline, like the home's.
  final bool enabled;
  final Widget child;

  /// The room the bell takes at the bar's end.
  static const room = 48.0;

  /// Whether a page at [path] of the business draws the bell.
  static bool showsOn(String orgId, String path) {
    final home = Routes.org(orgId);
    var rest = path.startsWith(home) ? path.substring(home.length) : path;
    if (rest.startsWith('/')) rest = rest.substring(1);
    if (rest.endsWith('/')) rest = rest.substring(0, rest.length - 1);
    return rest.isNotEmpty && rest != 'notifications';
  }

  @override
  State<PageBell> createState() => _PageBellState();
}

class _PageBellState extends State<PageBell> {
  final _stack = GlobalKey();

  /// The page's top bar row — where its title and actions are — in the
  /// bell's own coordinates, once measured. Null: the usual place (the top
  /// of the page, a standard toolbar high).
  Rect? _bar;

  /// The page's width, as measured with [_bar].
  double _width = 0;

  /// Finds the page's own top bar after it is laid out: the highest AppBar,
  /// and of those the one furthest right (a wide page's detail pane). Its
  /// toolbar row is the AppBar less its `bottom` (tabs) and the status bar
  /// it pads — so a bar with tabs, a pane's bar or a page under a strip
  /// carries the bell on its own row, at its own end.
  void _measure() {
    if (!mounted) return;
    final stack = _stack.currentContext;
    final stackBox = stack?.findRenderObject();
    if (stack is! Element || stackBox is! RenderBox || !stackBox.hasSize) return;
    Rect? found;
    void visit(Element e) {
      final w = e.widget;
      if (w is AppBar) {
        final box = e.findRenderObject();
        if (box is RenderBox && box.hasSize && box.attached) {
          final r = box.localToGlobal(Offset.zero, ancestor: stackBox) & box.size;
          final bottom = w.bottom?.preferredSize.height ?? 0;
          final toolbar =
              w.toolbarHeight ?? AppBarTheme.of(e).toolbarHeight ?? kToolbarHeight;
          final row = Rect.fromLTRB(r.left, r.bottom - bottom - toolbar, r.right, r.bottom - bottom);
          final f = found;
          if (f == null ||
              row.top < f.top - 0.5 ||
              ((row.top - f.top).abs() <= 0.5 && row.right > f.right)) {
            found = row;
          }
        }
        return; // an AppBar inside an AppBar is not the page's bar
      }
      e.visitChildren(visit);
    }

    stack.visitChildren(visit);
    final width = stackBox.size.width;
    if (found != _bar || width != _width) {
      setState(() {
        _bar = found;
        _width = width;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PageBell.showsOn(widget.org.id, widget.path)) return widget.child;
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context);
    // Read so a resize builds (and measures) again.
    MediaQuery.sizeOf(context);
    final ltr = Directionality.of(context) == TextDirection.ltr;
    // Measured again after every build of this page's frame: a resize (a
    // wide pane appearing), a page changing its bar.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final bar = _bar;
    // A bar across the whole page keeps its end clear of a notch, as the
    // AppBar's own SafeArea does; a pane's bar ends where the pane does.
    double endInset(double edge, double safe) => edge < 0.5 ? edge + safe : edge;
    return Stack(
      key: _stack,
      children: [
        Theme(
          data: theme.copyWith(
            appBarTheme: theme.appBarTheme.copyWith(
              // Every AppBar ends its actions with bellRoom, so this
              // applies to a bar with no button of its own too: the title
              // is never under the bell.
              actionsPadding: const EdgeInsetsDirectional.only(end: PageBell.room),
            ),
          ),
          child: widget.child,
        ),
        Positioned(
          top: bar?.top ?? padding.top,
          right: ltr
              ? (bar == null ? padding.right : endInset(_width - bar.right, padding.right))
              : null,
          left: ltr ? null : (bar == null ? padding.left : endInset(bar.left, padding.left)),
          height: bar?.height ?? kToolbarHeight,
          width: PageBell.room,
          child: Center(
            child: NotificationBell(
              key: const Key('page-bell'),
              notify: widget.notify,
              scope: NotifyScope.org(widget.org.id),
              listRoute: Routes.inside(widget.org.id, 'notifications'),
              enabled: widget.enabled,
            ),
          ),
        ),
      ],
    );
  }
}

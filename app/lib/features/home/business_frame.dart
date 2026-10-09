import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/business_cover.dart';
import '../../core/nav/router.dart';
import '../../core/theme/kaj_theme.dart';
import 'home_nav.dart';

/// The business's frame (108): its bar at the foot — or its rail down the
/// left on a wide screen — around every page of the business, for the
/// shop, the farm and the association alike.
///
/// The owner's question: « Do I still have this bar when I open articles or
/// commandes or factures? » It used to stay on the home only; a tool opened
/// as a page of its own with no bar. Now the router puts every `/o/<id>/…`
/// page inside this frame (a ShellRoute), and the frame draws the places
/// the home laid out (HomeNav, published through [BusinessNavHost]):
///
///   * the place of the page on screen is selected — Vente or Accueil on
///     the home, Articles on the articles and under them, Plus for a page
///     reached from Plus;
///   * a tap switches tool: the home stays underneath, so back from any
///     tool returns to the home and never out of the app. A page with
///     input not saved yet ([UnsavedInput]: a new invoice or its
///     correction, the settings' rubriques, a photo's articles to confirm)
///     first asks « Quitter sans enregistrer ? »; the place already
///     selected does nothing, even from deeper in it;
///   * a page that is none of the places (nor one under Plus) selects
///     none of them;
///   * a sheet, a dialog or a full-screen flow covers the bar as it always
///     did: the pages stand above the bar ([BusinessPage]) in a navigator
///     that spans the whole screen, and while something that is not a page
///     covers them ([BusinessCover]) the bar goes behind it, under its
///     shade.
///
/// No places yet — the first setup still holds the home, a kind the build
/// does not know, the business not loaded — no bar: the page is the
/// whole screen, as before.
class BusinessFrame extends StatefulWidget {
  const BusinessFrame({
    super.key,
    required this.org,
    required this.location,
    required this.child,
    this.cover,
  });

  /// Null while the business is still being read.
  final OrgSummary? org;

  /// The address on screen (`/o/<id>/factures/…`).
  final String location;

  /// The pages' navigator.
  final Widget child;

  /// What watches that navigator for a sheet or a full-screen flow on top.
  final BusinessCover? cover;

  @override
  State<BusinessFrame> createState() => _BusinessFrameState();
}

class _BusinessFrameState extends State<BusinessFrame> {
  final _nav = BusinessNav();

  @override
  void didUpdateWidget(BusinessFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another business's places are never drawn under this one's pages.
    if (oldWidget.org?.id != widget.org?.id) _nav.publishNothing();
  }

  @override
  void dispose() {
    _nav.dispose();
    super.dispose();
  }

  /// The address under the business, without its leading slash: '' on the
  /// home, 'factures/123' on an invoice.
  String get _rest {
    final org = widget.org;
    if (org == null) return '';
    final base = Routes.org(org.id);
    final path = widget.location;
    if (!path.startsWith(base)) return '';
    final rest = path.substring(base.length);
    return rest.startsWith('/') ? rest.substring(1) : rest;
  }

  /// The place of the page on screen: the longest route that is the page
  /// or above it. The home only at its own address.
  HomeDestination? _here(Iterable<HomeDestination> places) {
    final rest = _rest;
    HomeDestination? best;
    for (final p in places) {
      final r = p.route;
      if (r == null) continue;
      final hit = r.isEmpty ? rest.isEmpty : rest == r || rest.startsWith('$r/');
      if (hit && (best == null || r.length > best.route!.length)) best = p;
    }
    return best;
  }

  /// Into a place. A door (no route) opens as it says. A place is opened
  /// from the home, the way the home opens it — so the home is always the
  /// page underneath, its gates (Le Chemin's locks) are asked, and it reads
  /// itself again when the tool is closed.
  ///
  /// [themed] is a context under the business's colours (the dialog asked).
  Future<void> _open(HomeDestination p, BuildContext themed) async {
    final org = widget.org;
    final r = p.route;
    final rest = _rest;
    // The place already selected — its own page, or deeper in it (an
    // invoice, under Factures): nothing. A door (no route) still opens.
    if (org != null && r != null) {
      final inIt = r.isEmpty ? rest.isEmpty : rest == r || rest.startsWith('$r/');
      if (inIt) return;
    }
    if (_nav.hasUnsaved && !await _leaveUnsaved(themed)) return;
    if (!mounted) return;
    if (org == null || r == null) {
      p.onTap();
      return;
    }
    if (r.isEmpty) {
      context.go(Routes.org(org.id));
      return;
    }
    if (rest.isEmpty) {
      p.onTap();
      return;
    }
    context.go(Routes.org(org.id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) p.onTap();
    });
  }

  /// « Quitter sans enregistrer ? » — true to leave.
  Future<bool> _leaveUnsaved(BuildContext themed) =>
      UnsavedInput.askLeave(themed);

  @override
  Widget build(BuildContext context) {
    final cover = widget.cover;
    return ListenableBuilder(
      listenable: cover == null ? _nav : Listenable.merge([_nav, cover]),
      builder: (context, _) => _frame(context),
    );
  }

  Widget _frame(BuildContext context) {
    final org = widget.org;
    final nav = org == null ? null : _nav.nav;
    final places = nav == null ? const <HomeDestination>[] : nav.slots(context);
    final drawn = places.length >= 2;
    final wide = MediaQuery.sizeOf(context).width >= HomeNav.wideFrom;
    final padding = MediaQuery.paddingOf(context);

    // How much room the bar or the rail takes, exactly — the pages stand
    // inside the rest (BusinessPage).
    final barHeight =
        (NavigationBarTheme.of(context).height ?? 80) + padding.bottom;
    final railWidth = _railWidth + padding.left + 1;
    final insets = !drawn
        ? EdgeInsets.zero
        : wide
            ? EdgeInsets.only(left: railWidth)
            : EdgeInsets.only(bottom: barHeight);

    final more = nav?.overflow ?? const <HomeDestination>[];
    final here = _here([...places, ...more]);
    // Not one of the bar's own: a page reached from Plus is Plus's; a page
    // that is no place at all is nobody's (nothing selected).
    var selected = places.indexWhere((p) => identical(p, here));
    if (selected < 0 && here != null && more.any((m) => identical(m, here))) {
      selected = places.length - 1;
    }

    // [themed]: a context under the business's colours — the Plus sheet
    // and the dialog are the business's, as its pages are.
    void tap(BuildContext themed, int i) {
      final p = places[i];
      if (i == places.length - 1 && more.isNotEmpty) {
        HomeNav.showMore(themed, more, onPick: (item) => _open(item, themed), here: here);
        return;
      }
      _open(p, themed);
    }

    Widget bar = const SizedBox.shrink();
    if (drawn && !wide) {
      // NavigationBar always selects one: with no place here, the first
      // is drawn as unselected (no indicator, its plain icon and label).
      final none = selected < 0;
      final labels = NavigationBarTheme.of(context).labelTextStyle;
      bar = SizedBox(
        key: const Key('business-bar'),
        height: barHeight,
        child: Builder(
          builder: (themed) => NavigationBar(
            selectedIndex: none ? 0 : selected,
            indicatorColor: none ? Colors.transparent : null,
            labelTextStyle: none && labels != null
                ? WidgetStatePropertyAll(labels.resolve(const <WidgetState>{}))
                : null,
            onDestinationSelected: (i) => tap(themed, i),
            destinations: [
              for (final p in places)
                NavigationDestination(
                  icon: HomeNav.placeIcon(p, p.icon),
                  selectedIcon: HomeNav.placeIcon(
                      p, none ? p.icon : (p.selectedIcon ?? p.icon)),
                  label: p.label,
                ),
            ],
          ),
        ),
      );
    } else if (drawn) {
      bar = Row(
        key: const Key('business-rail'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SafeArea(
            right: false,
            child: SizedBox(
              width: _railWidth,
              child: Builder(
                builder: (themed) => NavigationRail(
                  minWidth: _railWidth,
                  selectedIndex: selected < 0 ? null : selected,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => tap(themed, i),
                  destinations: [
                    for (final p in places)
                      NavigationRailDestination(
                        icon: HomeNav.placeIcon(p, p.icon),
                        selectedIcon:
                            HomeNav.placeIcon(p, p.selectedIcon ?? p.icon),
                        label: Text(p.label, textAlign: TextAlign.center),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
        ],
      );
    }

    final placesBox = Positioned(
      key: const ValueKey('places'),
      left: 0,
      right: wide ? null : 0,
      top: wide ? 0 : null,
      bottom: 0,
      child: bar,
    );
    final pages = Positioned.fill(key: const ValueKey('pages'), child: widget.child);
    // On top of the pages, where a tap reaches it; behind whatever covers
    // them — a sheet shades it and rises over it, as over the home's own
    // bar before.
    final covered = widget.cover?.covered ?? false;
    final frame = BusinessNavHost(
      nav: _nav,
      insets: insets,
      child: Stack(children: covered ? [placesBox, pages] : [pages, placesBox]),
    );
    if (org == null) return frame;
    // The business's colours on its bar, as on its pages.
    return ProfileTheme(profile: org.profile, theme: org.theme, child: frame);
  }

  static const _railWidth = 96.0;
}

/// A page of a business, standing above the frame's bar or beside its rail
/// (108): it takes the rest of the screen, and is told the bar has the
/// bottom's safe area and the part of the keyboard the bar was under.
/// Every page under `/o/<id>` passes through it (the router's `_withOrg`);
/// outside a business frame it is nothing.
class BusinessPage extends StatelessWidget {
  const BusinessPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final insets = BusinessNavHost.insetsOf(context);
    final mq = MediaQuery.of(context);
    // Always the same two widgets, bar or not: a page is never rebuilt from
    // nothing because its bar came or went.
    return Padding(
      padding: insets,
      child: MediaQuery(
        data: insets == EdgeInsets.zero
            ? mq
            : mq.copyWith(
                padding: mq.padding.copyWith(
                  bottom: insets.bottom > 0 ? 0 : null,
                  left: insets.left > 0 ? 0 : null,
                ),
                viewPadding: mq.viewPadding.copyWith(
                  bottom: insets.bottom > 0 ? 0 : null,
                  left: insets.left > 0 ? 0 : null,
                ),
                viewInsets: mq.viewInsets.copyWith(
                  bottom: (mq.viewInsets.bottom - insets.bottom)
                      .clamp(0, double.infinity)
                      .toDouble(),
                ),
              ),
        child: child,
      ),
    );
  }
}

/// Input on a page of a business not saved yet (108, A4): while [isDirty]
/// says so — asked at the moment of the tap — a tap on the business's bar
/// or rail first asks « Quitter sans enregistrer ? ». Outside a business
/// frame it is nothing.
class UnsavedInput extends StatefulWidget {
  const UnsavedInput({super.key, required this.isDirty, required this.child});

  final bool Function() isDirty;
  final Widget child;

  /// « Quitter sans enregistrer ? » (Rester / Quitter) — true to leave.
  /// The bar's question, and the step flows' (115) on their first step.
  static Future<bool> askLeave(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('unsaved-dialog'),
        title: Text(dialog.tr('Quitter sans enregistrer ?')),
        content: Text(dialog.tr('Ce que vous avez saisi ici sera perdu.')),
        actions: [
          TextButton(
            key: const Key('unsaved-stay'),
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(dialog.tr('Rester')),
          ),
          FilledButton(
            key: const Key('unsaved-leave'),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(dialog.tr('Quitter')),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  State<UnsavedInput> createState() => _UnsavedInputState();
}

class _UnsavedInputState extends State<UnsavedInput> {
  BusinessNav? _nav;

  bool _dirty() => mounted && widget.isDirty();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = BusinessNavHost.navOf(context);
    if (!identical(nav, _nav)) {
      _nav?.releaseUnsaved(_dirty);
      _nav = nav?..holdUnsaved(_dirty);
    }
  }

  @override
  void dispose() {
    _nav?.releaseUnsaved(_dirty);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

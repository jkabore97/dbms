import 'package:flutter/material.dart';

import '../l10n/tr.dart';

/// Every bottom sheet of the app (132): [showModalBottomSheet], with a
/// visible way out — a close « X » at the top right, beside the drag
/// handle when the sheet has one.
///
/// The owner on an iPhone (TestFlight 4): « There is no go back button …
/// Apple users definitely need a go back button everywhere. » An iPhone
/// has no system back: a sheet could only be left by a swipe down or a
/// tap above it, which nobody is told. The X closes it the way the back
/// does (`maybePop`: a sheet that asks before losing what was typed still
/// asks).
///
/// The handle and the X stand in their own band above the sheet's content
/// (the room the framework's own handle took), so nothing of the content
/// is covered. [closeButton] false for a sheet that draws its own close.
Future<T?> showMaraSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  bool closeButton = true,
  RouteSettings? routeSettings,
}) {
  final handle = showDragHandle ??
      Theme.of(context).bottomSheetTheme.showDragHandle ??
      false;
  final close = closeButton && isDismissible;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    // The band below draws the handle, with the X beside it.
    showDragHandle: close ? false : handle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    builder: close
        ? (sheet) => SheetFrame(handle: handle, child: builder(sheet))
        : builder,
  );
}

/// A sheet's top band — the drag handle (when asked) and the close « X »
/// — above its content.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.child, this.handle = true});

  final Widget child;
  final bool handle;

  /// The band's height: the framework's own handle takes as much.
  static const band = kMinInteractiveDimension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: band,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (handle)
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.bottomSheetTheme.dragHandleColor ??
                        ink.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: IconButton(
                  key: const Key('sheet-close'),
                  tooltip: context.tr('Fermer'),
                  icon: Icon(Icons.close, color: ink),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}

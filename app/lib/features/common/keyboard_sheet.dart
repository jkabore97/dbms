import 'package:flutter/material.dart';

import '../../core/theme/scroll_hint.dart';

/// A bottom sheet that holds text (batch 115): what is typed is never under
/// the keyboard, and neither is the button that saves it.
///
/// The fields scroll — the one being typed into is brought into view whole
/// (its label, its lines, its counter) as the keyboard rises — and
/// [footer] (the sheet's primary button) stays fixed under them, lifted
/// above the keyboard and clear of the phone's own bar (SafeArea). Opened
/// with `isScrollControlled: true, useSafeArea: true`, so a sheet taller
/// than the screen stops under the status bar and scrolls instead of being
/// cut off. On a 360 × 640 phone with the keyboard up, the field and the
/// button are both on screen (test/batch115_keyboard_test.dart).
class KeyboardSheet extends StatelessWidget {
  const KeyboardSheet({
    super.key,
    required this.children,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 16),
  });

  /// The sheet's title and fields, in a scroll view.
  final List<Widget> children;

  /// The primary button (and its error line), always above the keyboard.
  final Widget? footer;

  /// Around the fields; the footer takes the same sides.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              // More fields under the edge: the arrow says so (122).
              child: ScrollHint(child: FocusedFieldInView(
                child: SingleChildScrollView(
                  key: const Key('keyboard-sheet-scroll'),
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              )),
            ),
            if (footer != null)
              Padding(
                padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 12),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Around a scroll view of fields (a [KeyboardSheet], a StepFlow step):
/// when the keyboard rises or another field is focused, the whole field —
/// its label, its lines and its counter, not only the caret Flutter keeps
/// on screen — is brought into view once the view has its new height.
class FocusedFieldInView extends StatefulWidget {
  const FocusedFieldInView({super.key, required this.child});

  final Widget child;

  @override
  State<FocusedFieldInView> createState() => _FocusedFieldInViewState();
}

class _FocusedFieldInViewState extends State<FocusedFieldInView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusMoved);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusMoved);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _focusMoved();

  void _focusMoved() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null || !focused.mounted) return;
      // Only a field under this widget, and the field as drawn (TextField
      // or its form wrapper), not its inner editable line.
      final here = context;
      Element? field;
      var inside = false;
      focused.visitAncestorElements((e) {
        final w = e.widget;
        if (field == null && (w is TextField || w is TextFormField)) field = e;
        if (identical(e, here)) {
          inside = true;
          return false;
        }
        return true;
      });
      final target = field;
      if (!inside || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 120),
      ).then((_) {
        if (!mounted || !target.mounted) return;
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: const Duration(milliseconds: 120),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'package:flutter/material.dart';

/// A text controller that lives exactly as long as the widget using it.
///
/// For a dialog with a field. The pattern it replaces — create a controller,
/// `await showDialog`, dispose it — disposes while the dialog is still
/// animating out: `showDialog` returns on pop, before the route has left the
/// screen, and the closing TextField then touches a dead controller ("A
/// TextEditingController was used after being disposed"). Here the dialog's
/// own State disposes it, after the dialog is gone. Read the text before
/// popping and pop it as the result.
class OwnedController extends StatefulWidget {
  const OwnedController({super.key, required this.builder});

  final Widget Function(BuildContext context, TextEditingController controller)
      builder;

  @override
  State<OwnedController> createState() => _OwnedControllerState();
}

class _OwnedControllerState extends State<OwnedController> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

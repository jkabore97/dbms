import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// The web app (177): the card in a frame of the same site, its still
/// picture until it has loaded. The frame takes no touch: the page lays it
/// under its own « open the card » tap.
Widget liveCard({required Uri uri, required Widget placeholder, Key? key}) =>
    _LiveCard(key: key, uri: uri, placeholder: placeholder);

class _LiveCard extends StatefulWidget {
  const _LiveCard({super.key, required this.uri, required this.placeholder});

  final Uri uri;
  final Widget placeholder;

  @override
  State<_LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends State<_LiveCard> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    // the card underneath, drawing from the start; its picture over it
    // until it has loaded (a frame drawn at no opacity would never load)
    return Stack(fit: StackFit.expand, children: [
      HtmlElementView.fromTagName(
        tagName: 'iframe',
        isVisible: true,
        onElementCreated: (element) {
          final frame = element as web.HTMLIFrameElement;
          frame.src = widget.uri.toString();
          frame.title = 'Invitation';
          frame.style
            ..border = '0'
            ..width = '100%'
            ..height = '100%'
            ..pointerEvents = 'none';
          frame.addEventListener('load', ((web.Event _) {
            Future<void>.delayed(const Duration(milliseconds: 700), () {
              if (mounted) setState(() => _shown = true);
            });
          }).toJS);
        },
      ),
      IgnorePointer(
        child: AnimatedOpacity(
          opacity: _shown ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: widget.placeholder,
        ),
      ),
    ]);
  }
}

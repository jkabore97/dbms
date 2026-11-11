import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Android and iPhone (177): the card in a web view, its still picture
/// until it has loaded and drawn.
Widget liveCard({required Uri uri, required Widget placeholder, Key? key}) =>
    WebViewPlatform.instance == null ? placeholder : _LiveCard(key: key, uri: uri, placeholder: placeholder);

class _LiveCard extends StatefulWidget {
  const _LiveCard({super.key, required this.uri, required this.placeholder});

  final Uri uri;
  final Widget placeholder;

  @override
  State<_LiveCard> createState() => _LiveCardState();
}

class _LiveCardState extends State<_LiveCard> {
  late final WebViewController _web;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _shown = true);
        }),
        // the card's own links (the map, WhatsApp) stay out of the frame
        onNavigationRequest: (r) => Uri.tryParse(r.url)?.path == widget.uri.path
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    // the card underneath, drawing from the start; its picture over it
    // until it has loaded (a view drawn at no opacity would never load)
    return Stack(fit: StackFit.expand, children: [
      IgnorePointer(child: WebViewWidget(controller: _web)),
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

import 'package:flutter/material.dart';

/// Below this width a page's bar is a small phone's (UI audit B-3).
const double narrowBarWidth = 400;

bool isNarrowBar(BuildContext context) =>
    MediaQuery.sizeOf(context).width < narrowBarWidth;

/// A page's title in its app bar that stays readable on a small phone
/// (UI audit B-3: « Bouti… », « Com… », « F… » with three actions and the
/// bell). Wide, it is the plain title. Narrow, it is a size smaller, at most
/// 1.15 × the text size (two lines must fit the 56 px bar), on up to two
/// lines — a size smaller again (down to 13) when one word is wider than
/// the room.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (!isNarrowBar(context)) return Text(text);
    final theme = Theme.of(context);
    final style = (theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge ?? const TextStyle())
        .copyWith(fontSize: 17, height: 1.15);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: LayoutBuilder(builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        var widest = 0.0;
        for (final word in text.split(RegExp(r'\s+'))) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          if (painter.width > widest) widest = painter.width;
          painter.dispose();
        }
        // A word wider than the room: a smaller size, down to 13, so it is
        // not cut in the middle — still on two lines.
        final size = box.maxWidth.isFinite && widest > box.maxWidth
            // (a hair under the room: text width does not scale exactly
            // with its size — « Catalogue » broke as « Catalogu|e », 134)
            ? (17 * box.maxWidth / widest * 0.94).clamp(13.0, 17.0)
            : 17.0;
        return Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(fontSize: size));
      }),
    );
  }
}

/// One action of a page's bar: its icon, its words (the tooltip, or the
/// label when there is room) and what it does.
class BarAction {
  const BarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.key,
  });

  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

/// A page's own actions: each an icon on a wide screen; on a small phone
/// the first stays and the others fold into one « more » menu, so the
/// title keeps its room (B-3).
List<Widget> barActions(BuildContext context, List<BarAction> actions,
    {required String moreLabel}) {
  Widget icon(BarAction a) => IconButton(
        key: a.key,
        onPressed: a.onPressed,
        icon: Icon(a.icon),
        tooltip: a.label,
      );
  if (!isNarrowBar(context) || actions.length < 2) return [for (final a in actions) icon(a)];
  final rest = actions.sublist(1);
  return [
    icon(actions.first),
    PopupMenuButton<int>(
      key: const Key('bar-more'),
      tooltip: moreLabel,
      icon: const Icon(Icons.more_vert),
      onSelected: (i) => rest[i].onPressed?.call(),
      itemBuilder: (_) => [
        for (var i = 0; i < rest.length; i++)
          PopupMenuItem<int>(
            key: rest[i].key == null ? null : ValueKey('menu-${rest[i].key}'),
            value: i,
            enabled: rest[i].onPressed != null,
            child: Row(children: [
              Icon(rest[i].icon),
              const SizedBox(width: 12),
              Flexible(child: Text(rest[i].label)),
            ]),
          ),
      ],
    ),
  ];
}

/// An action that carries its words beside its icon where there is room
/// (« Ma vitrine »), and is the icon alone, its words the tooltip, on a
/// small phone (B-3).
Widget labelledBarAction(BuildContext context,
    {Key? key, required IconData icon, required String label, required VoidCallback? onPressed}) {
  if (isNarrowBar(context)) {
    return IconButton(key: key, onPressed: onPressed, icon: Icon(icon), tooltip: label);
  }
  return TextButton.icon(key: key, onPressed: onPressed, icon: Icon(icon), label: Text(label));
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/tr.dart';

/// A text that copies itself on a tap (171d). Nothing in Marakaj is chosen
/// by a long press — the owner's ask: no handles, no system bar offering
/// Google's search over the words — so what used to be a SelectableText
/// (a code, a link, a number) is copied whole by a tap, and says so.
class CopyText extends StatelessWidget {
  const CopyText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.copied,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// What the snack bar says once it is copied (already translated);
  /// « Copié » when null.
  final String? copied;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: context.tr('Toucher pour copier'),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (!context.mounted) return;
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text(copied ?? context.tr('Copié'))));
        },
        child: Text(text, style: style, textAlign: textAlign),
      ),
    );
  }
}

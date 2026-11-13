// Every dialog with something to type in scrolls as a whole (the owner's
// « Où payer », keyboard up: only a sliver of the list left between the
// title and the buttons). AlertDialog(scrollable: true) scrolls its title
// and content together, so a field can always come above the keyboard.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every AlertDialog with a field is scrollable as a whole', () {
    final input = RegExp(r'\b(TextField|TextFormField|PhoneInput|DropdownButtonFormField)\b');
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in RegExp(r'\bAlertDialog\(').allMatches(s)) {
        var i = m.end, depth = 1;
        while (depth > 0 && i < s.length) {
          final c = s[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          i++;
        }
        final body = s.substring(m.end, i - 1);
        if (input.hasMatch(body) && !RegExp(r'^\s*scrollable:\s*true', multiLine: true).hasMatch(body)) {
          missing.add('${f.path}:${'\n'.allMatches(s.substring(0, m.start)).length + 1}');
        }
      }
    }
    expect(missing, isEmpty, reason: 'add scrollable: true to these dialogs');
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The site Worker answers 404 to any address whose first segment is no
/// page of the app's (the owner: failed pages show 404). Its list
/// (APP_PATHS, workers/kaj-app/src/index.js) and the router's addresses
/// must stay the same: a page added here and not there would answer 404
/// while it shows.
void main() {
  test('every address of the router is in the site Worker\'s APP_PATHS', () {
    final worker = File('../workers/kaj-app/src/index.js').readAsStringSync();
    final from = worker.indexOf('export const APP_PATHS = new Set([');
    expect(from, greaterThan(0), reason: 'APP_PATHS in the Worker');
    final block = worker.substring(from, worker.indexOf(']);', from));
    final known = {for (final m in RegExp(r'"([^"]*)"').allMatches(block)) m.group(1)!};

    final router = File('lib/core/nav/router.dart').readAsStringSync();
    final firsts = {
      for (final m in RegExp(r"'/([a-z0-9_-]*)").allMatches(router)) m.group(1)!,
    };
    expect(firsts, isNotEmpty);
    final missing = firsts.difference(known);
    expect(missing, isEmpty, reason: 'add to APP_PATHS in workers/kaj-app/src/index.js: $missing');
  });
}

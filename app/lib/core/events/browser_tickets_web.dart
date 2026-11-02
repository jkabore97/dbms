import 'dart:convert';

import 'package:web/web.dart' as web;

/// The requests this browser booked on marakaj.com (part 4): the ticket
/// page keeps them in its localStorage, on the app's own origin.
List<String> browserTicketIds() {
  try {
    final raw = web.window.localStorage.getItem('mk-billets');
    if (raw == null) return const [];
    return [
      for (final x in jsonDecode(raw) as List)
        if (x is Map && x['id'] is String) (x['id'] as String).toLowerCase(),
    ];
  } catch (_) {
    return const [];
  }
}

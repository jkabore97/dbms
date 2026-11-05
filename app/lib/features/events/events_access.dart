import 'package:flutter/widgets.dart';

import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';

/// Whether Événementiel is drawn for this person (152): Marakaj's own
/// admins always, everyone once the platform's switch (Réglages ›
/// Événementiel) is on. A business's admin right is asked beside it, by
/// the home screens and the routes; the server's policies ask both again.
bool eventsShownFor(BuildContext context) {
  final s = AppScope.maybeOf(context)?.session;
  return s != null && (s.isPlatformAdmin || s.eventsPublic);
}

/// Whether this business's Événementiel pages are open to this person:
/// what [eventsShownFor] says, or the business let in by itself (167).
bool eventsOpenFor(BuildContext context, OrgSummary org) {
  final s = AppScope.maybeOf(context)?.session;
  return s != null && s.eventsOpenFor(org);
}

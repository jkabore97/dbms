/// A service's duration (136): minutes in the database, « 1 h 30 » on the
/// screen — and, before 136, the words the service flow wrote at the top of
/// the description (« Durée : 1 h »), still read so that nothing changes on
/// a vitrine until the backfill has run.
library;

/// « 45 min », « 1 h », « 1 h 30 », « 2 h » — the same in French and
/// English (the vitrine's own way of writing it). On screen the number
/// and its unit never part (non-breaking spaces, 133); [plain] for words
/// written to the database.
String formatDuration(int minutes, {bool plain = false}) {
  final sp = plain ? ' ' : '\u00a0';
  if (minutes < 60) return '$minutes${sp}min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h${sp}h' : '$h${sp}h$sp${m.toString().padLeft(2, '0')}';
}

/// What the flow and the « Autre » field accept, in minutes; null when it is
/// not a length of time. The same reading as 136's duration_minutes_of().
int? durationMinutesOf(String? text) {
  var t = (text ?? '').trim().toLowerCase();
  t = t.replaceFirst(RegExp(r'^dur[ée]e\s*:\s*'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  t = t.replaceFirst(RegExp(r'^(environ|env\.|~)\s*'), '');
  const half = {'une demi-journée', 'demi-journée', 'une demi journée', 'demi journée', '1/2 journée'};
  const day = {'une journée', 'journée', '1 journée', 'un jour', '1 jour'};
  if (half.contains(t)) return 240;
  if (day.contains(t)) return 480;
  num? v;
  final hours = RegExp(r'^(\d+(?:[.,]\d+)?) ?(?:h|hr|hrs|heure|heures)(?: ?(\d{1,2}))? ?(?:min|mn|minutes?)?$')
      .firstMatch(t);
  if (hours != null) {
    v = double.parse(hours.group(1)!.replaceAll(',', '.')) * 60 +
        int.parse(hours.group(2) ?? '0');
  } else {
    final mins = RegExp(r'^(\d+) ?(?:min|mn|minute|minutes)$').firstMatch(t);
    if (mins == null) return null;
    v = int.parse(mins.group(1)!);
  }
  final r = v.round();
  return r < 1 || r > 10080 ? null : r;
}

/// A service's duration and the words that remain to describe it:
/// [minutes] (136's column) first; otherwise the « Durée : … » line the
/// service flow wrote first in the description before 136, taken off the
/// description so it is not said twice.
({String? duration, String? description}) serviceWords({
  required bool isService,
  int? minutes,
  String? description,
}) {
  final text = description?.trim();
  final legacy = RegExp(r'^Dur[ée]e\s*:\s*([^\n]+)\n?').firstMatch(text ?? '');
  if (!isService) return (duration: null, description: _blank(text));
  if (minutes != null) {
    // Said by the column: a first line that says the same goes.
    final rest = legacy != null && durationMinutesOf(legacy.group(1)) == minutes
        ? text!.substring(legacy.end)
        : text;
    return (duration: formatDuration(minutes), description: _blank(rest));
  }
  if (legacy != null) {
    final words = legacy.group(1)!.trim();
    final m = durationMinutesOf(words);
    return (
      duration: m == null ? words : formatDuration(m),
      description: _blank(text!.substring(legacy.end)),
    );
  }
  return (duration: null, description: _blank(text));
}

String? _blank(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

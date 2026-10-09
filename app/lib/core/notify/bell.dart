import 'dart:async';

import 'package:flutter/widgets.dart';

import 'notifications_repository.dart';

/// The bell's numbers, live (115), for every bell and every business bar of
/// the app at once.
///
/// Before, each bell read its count once, when drawn, and never again. Now
/// one keeper holds them: it reads notification_counts() — and home_counts()
/// for each business whose bar is on screen — when the first bell or bar
/// starts listening, whenever the person's bell rows change (Realtime, the
/// rows of the signed-in person only), when the app comes back to the
/// foreground, and every minute as the fallback for a socket that died on
/// a slow network. With nobody listening it does nothing at all.
class Bell extends ChangeNotifier with WidgetsBindingObserver {
  Bell(this._notify, {this.every = const Duration(seconds: 60)});

  final NotificationsRepository _notify;

  /// The fallback poll.
  final Duration every;

  NotificationCounts _counts = NotificationCounts.none;
  final Map<String, Map<String, int>> _home = {};
  final Map<String, int> _homeWatchers = {};

  Timer? _timer;
  Timer? _soon;
  void Function()? _unwatch;
  String? _watching;
  bool _running = false;
  bool _disposed = false;

  /// The unread numbers of every list.
  NotificationCounts get counts => _counts;

  /// One bell's number: its list's, with the account's own.
  int unreadOf(NotifyScope scope) => _counts.of(scope);

  /// One number of a business's bar ('orders', 'articles', …); 0 unknown.
  int homeCount(String orgId, String key) => _home[orgId]?[key] ?? 0;

  /// A business's bar is on screen: its numbers are read with the bell's.
  void watchHome(String orgId) {
    _homeWatchers[orgId] = (_homeWatchers[orgId] ?? 0) + 1;
    if (_homeWatchers[orgId] == 1 && _running) unawaited(_readHome(orgId));
  }

  void unwatchHome(String orgId) {
    final n = (_homeWatchers[orgId] ?? 1) - 1;
    if (n <= 0) {
      _homeWatchers.remove(orgId);
    } else {
      _homeWatchers[orgId] = n;
    }
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_running) _start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stop();
  }

  void _start() {
    if (!_notify.isConfigured || _disposed) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(every, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void _stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _soon?.cancel();
    _unwatch?.call();
    _unwatch = null;
    _watching = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  /// Read again a moment from now — several rows written at once (an order
  /// accepted rings the customer and the shop) make one read, not five.
  void refreshSoon() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 400), () => unawaited(refresh()));
  }

  /// Reads every number now. Never throws: no signal is not news, the next
  /// tick tries again.
  Future<void> refresh() async {
    if (!_running || _disposed) return;
    _follow();
    try {
      final counts = await _notify.counts();
      if (_disposed) return;
      if (counts != _counts) {
        _counts = counts;
        notifyListeners();
      }
    } catch (_) {}
    for (final org in _homeWatchers.keys.toList()) {
      await _readHome(org);
    }
  }

  Future<void> _readHome(String orgId) async {
    try {
      final v = await _notify.homeCounts(orgId);
      if (_disposed) return;
      final before = _home[orgId];
      if (before == null ||
          before.length != v.length ||
          v.entries.any((e) => before[e.key] != e.value)) {
        _home[orgId] = v;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// The live channel follows whoever is signed in: another person on the
  /// same phone gets their own, the old one is closed.
  void _follow() {
    final me = _notify.me;
    if (me == _watching) return;
    _unwatch?.call();
    _unwatch = null;
    _watching = me;
    if (me == null) {
      _counts = NotificationCounts.none;
      _home.clear();
      return;
    }
    try {
      _unwatch = _notify.watch(me, refreshSoon);
    } catch (_) {
      // No Realtime here (a test, a build without it): the minute's poll
      // and the return to the foreground still bring the numbers.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/notify/notifications_repository.dart';
import '../../l10n/strings.dart';

/// The bell on every home screen's app bar: a badge with the unread count,
/// opening the list. Self-contained so each home screen adds one widget and
/// nothing else — it fetches its own count and refreshes after the list is
/// visited.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.notify,
    required this.listRoute,
  });

  final NotificationsRepository notify;

  /// Where the bell opens, e.g. `Routes.inside(org.id, 'notifications')`.
  final String listRoute;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.notify.isConfigured) return;
    try {
      final rows = await widget.notify.recent();
      if (mounted) {
        setState(() => _unread = rows.where((r) => r.isUnread).length);
      }
    } catch (_) {
      // A bell that cannot reach the server shows no number — the button
      // still opens the list, which will say what is wrong.
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: Strings.of(context).notifications,
      icon: Badge.count(
        count: _unread,
        isLabelVisible: _unread > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await context.push(widget.listRoute);
        if (mounted) await _refresh();
      },
    );
  }
}

/// The list behind the bell. Opening it marks everything read — a bell that
/// stays red after being looked at trains people to ignore it.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.notify});

  final NotificationsRepository notify;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.notify.recent();
      // The unread state renders once (bold), then everything is marked
      // read for next time.
      if (rows.any((r) => r.isUnread)) {
        await widget.notify.markAllRead();
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  IconData _iconFor(String kind) => switch (kind) {
        'low_stock' => Icons.inventory_2_outlined,
        'member_joined' => Icons.person_add_alt,
        'debt_settled' => Icons.handshake_outlined,
        'tontine_ready' => Icons.group_outlined,
        'org_application' => Icons.business_outlined,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final dates = DateFormat('d MMM à HH:mm', 'fr_FR');
    return Scaffold(
      appBar: AppBar(title: Text(strings.notifications)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(strings.noNotifications,
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = _rows[i];
                        return ListTile(
                          leading: Icon(_iconFor(n.kind)),
                          title: Text(
                            n.message,
                            style: n.isUnread
                                ? const TextStyle(fontWeight: FontWeight.w600)
                                : null,
                          ),
                          subtitle:
                              Text(dates.format(n.createdAt.toLocal())),
                        );
                      },
                    ),
    );
  }
}

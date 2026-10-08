import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/notify/notifications_repository.dart';
import '../../l10n/strings.dart';
import '../admin/admin_pill.dart' show AdminTrail;
import 'notification_text.dart';

/// The bell on every home screen's app bar: a badge with the unread count,
/// opening the list. Self-contained so each home screen adds one widget and
/// nothing else — it fetches its own count and refreshes after the list is
/// visited.
class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.notify,
    required this.listRoute,
    this.enabled = true,
  });

  final NotificationsRepository notify;

  /// Where the bell opens, e.g. `Routes.inside(org.id, 'notifications')`.
  final String listRoute;

  /// The bell is always on the app bar so its place never moves; offline it is
  /// greyed and inert rather than gone, because a control that vanishes teaches
  /// people it was never there.
  final bool enabled;

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
    if (!widget.enabled || !widget.notify.isConfigured) return;
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
    if (!widget.enabled) {
      // Offline: present but inert, greyed so it reads as "later", not "gone".
      return IconButton(
        tooltip: Strings.of(context).notifications,
        onPressed: null,
        icon: Icon(
          Icons.notifications_outlined,
          color: Theme.of(context).disabledColor,
        ),
      );
    }
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
/// stays red after being looked at trains people to ignore it. Each ring
/// says its line in the phone's language and opens what it is about
/// (notification_text.dart).
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
        'unlock' => Icons.lock_open_outlined,
        'cauris_board' || 'cauris_prize' => Icons.emoji_events_outlined,
        'pro_active' => Icons.workspace_premium_outlined,
        'new_device' => Icons.shield_outlined,
        'spot_approved' || 'spot_refused' => Icons.campaign_outlined,
        'vitrine_news' => Icons.favorite_border,
        'report_handled' => Icons.flag_outlined,
        final k when k.startsWith('courier_') || k.startsWith('delivery_') =>
          Icons.delivery_dining_outlined,
        final k when k.startsWith('order_') || k == 'new_order' =>
          Icons.receipt_long_outlined,
        _ => Icons.notifications_outlined,
      };

  /// Where this ring opens (notificationTarget): the business's own screen
  /// when the person answers for it, theirs as a customer otherwise.
  String? _targetOf(NotificationRow n) {
    final session = AppScope.maybeOf(context)?.session;
    return notificationTarget(
      n,
      isAdminOf: (id) => session?.orgById(id)?.isAdmin ?? false,
      profileOf: (id) => session?.orgById(id)?.profile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final english = context.trLanguage == 'en';
    final dates = english
        ? DateFormat('d MMM, HH:mm', 'en')
        : DateFormat('d MMM à HH:mm', 'fr_FR');
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
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = _rows[i];
                        final target = _targetOf(n);
                        return ListTile(
                          key: Key('notification-${n.id}'),
                          leading: Icon(_iconFor(n.kind)),
                          trailing: target == null
                              ? null
                              : const Icon(Icons.chevron_right),
                          // A ring for the platform (a request, a spot)
                          // enters the center the way the pill does, so
                          // back returns here.
                          onTap: target == null
                              ? null
                              : () => AdminTrail.inCenter(target)
                                  ? AdminTrail.enter(context, to: target)
                                  : context.push(target),
                          title: Text(
                            notificationLine(context, n),
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

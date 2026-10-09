import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/nav/session.dart';
import '../../core/notify/bell.dart';
import '../../core/notify/notifications_repository.dart';
import '../../l10n/strings.dart';
import '../admin/admin_pill.dart' show AdminTrail;
import 'notification_settings_sheet.dart';
import 'notification_text.dart';

/// The bell (115): on every home of the three kinds, on every tool page of
/// a business (PageBell), on the street and the vitrine for a signed-in
/// shopper, on the shopper's profile, in the courier's space and in the
/// command center — each the bell of its own list ([scope]).
///
/// Its number is live: one keeper for the whole app (notify.bell) reads the
/// counts when the person's bell rows change (Realtime), when the app comes
/// back to the foreground and every minute. A red bubble, « 9+ » past nine.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.notify,
    required this.scope,
    required this.listRoute,
    this.enabled = true,
  });

  final NotificationsRepository notify;

  /// Whose list: a business's, the shopper's, the courier's, the platform's.
  final NotifyScope scope;

  /// Where the bell opens, e.g. `Routes.inside(org.id, 'notifications')`.
  final String listRoute;

  /// The bell is always on the app bar so its place never moves; offline it is
  /// greyed and inert rather than gone, because a control that vanishes teaches
  /// people it was never there.
  final bool enabled;

  /// The bubble's words: the number, « 9+ » past nine.
  static String label(int n) => n > 9 ? '9+' : '$n';

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      // Offline: present but inert, greyed so it reads as "later", not "gone".
      return IconButton(
        key: const Key('bell'),
        tooltip: Strings.of(context).notifications,
        onPressed: null,
        icon: Icon(
          Icons.notifications_outlined,
          color: Theme.of(context).disabledColor,
        ),
      );
    }
    if (!notify.isConfigured) {
      // A build with no server: the list will say so.
      return IconButton(
        key: const Key('bell'),
        tooltip: Strings.of(context).notifications,
        icon: const Icon(Icons.notifications_outlined),
        onPressed: () => context.push(listRoute),
      );
    }
    final bell = notify.bell;
    return ListenableBuilder(
      listenable: bell,
      builder: (context, _) {
        final n = bell.unreadOf(scope);
        return IconButton(
          key: const Key('bell'),
          tooltip: Strings.of(context).notifications,
          icon: Badge(
            key: const Key('bell-count'),
            isLabelVisible: n > 0,
            label: Text(label(n)),
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: () async {
            await context.push(listRoute);
            await bell.refresh();
          },
        );
      },
    );
  }
}

/// The list behind a bell: its own rows only (115) — this business's, my
/// purchases, my deliveries, or the platform's, with the account's own in
/// each. Opening it marks read exactly the rows it shows, and nothing else:
/// a bell that stays red after being looked at trains people to ignore it,
/// and one business's list must never clear another's. A row that arrives
/// while it is open appears at once. Each ring says its line in the
/// phone's language and opens what it is about (notification_text.dart).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.notify,
    required this.scope,
  });

  final NotificationsRepository notify;
  final NotifyScope scope;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationRow> _rows = const [];
  bool _loading = true;
  String? _error;
  int _seen = 0;

  /// The keeper listened to, kept: the same one is let go at dispose.
  Bell? _bell;

  @override
  void initState() {
    super.initState();
    if (widget.notify.isConfigured) _bell = widget.notify.bell..addListener(_onBell);
    _load();
  }

  @override
  void dispose() {
    _bell?.removeListener(_onBell);
    super.dispose();
  }

  /// A new row for this list while it is open: read again.
  void _onBell() {
    final n = _bell?.unreadOf(widget.scope) ?? 0;
    if (n > 0 && n != _seen && !_loading) _load();
    _seen = n;
  }

  Future<void> _load() async {
    try {
      final rows = await widget.notify.inScope(widget.scope);
      // The unread state renders once (bold), then exactly these rows are
      // marked read for next time.
      final unread = [for (final r in rows) if (r.isUnread) r.id];
      if (unread.isNotEmpty) {
        await widget.notify.markRead(unread);
        await _bell?.refresh();
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

  /// Whose switches the list's settings show.
  Set<String> get _audiences => switch (widget.scope.name) {
        'customer' => const {'customer'},
        'courier' => const {'courier'},
        'shop' => const {'shop'},
        _ => const <String>{},
      };

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
        'phone_verified' => Icons.verified_user_outlined,
        'test_push' => Icons.send_outlined,
        'platform_message' => Icons.campaign_outlined,
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
      appBar: AppBar(
        title: Text(strings.notifications),
        actions: [
          IconButton(
            key: const Key('notification-settings-open'),
            tooltip: context.tr('Réglages des notifications'),
            icon: const Icon(Icons.tune),
            onPressed: () => NotificationSettingsSheet.open(context,
                notify: widget.notify, audiences: _audiences),
          ),
        ],
      ),
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

/// The shopper's bell on the street and on a vitrine (115): drawn for a
/// signed-in person only — a stranger has no bell to read.
class ShopperBell extends StatelessWidget {
  const ShopperBell({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: scope.session,
      builder: (context, _) {
        final phase = scope.session.phase;
        final signedIn = phase == SessionPhase.ready ||
            phase == SessionPhase.noOrg ||
            phase == SessionPhase.picking;
        if (!signedIn || scope.notify.me == null) return const SizedBox.shrink();
        return NotificationBell(
          key: const Key('shopper-bell'),
          notify: scope.notify,
          scope: NotifyScope.customer,
          listRoute: Routes.myNotifications,
        );
      },
    );
  }
}

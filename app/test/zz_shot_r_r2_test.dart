import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/core/notify/push_client.dart';
import 'package:kaj_app/features/notify/notification_settings_sheet.dart';

import 'zz_shot_r_lib.dart';

class _Notify extends NotificationsRepository {
  _Notify() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<List<NotificationPref>> prefs() async => const [
        NotificationPref(type: 'order_updates', audience: 'customer', label: 'Mes commandes', enabled: true),
        NotificationPref(type: 'shop_new', audience: 'customer', label: 'Nouveautés de mes vitrines', enabled: false),
      ];
}

class _Phone extends PushDevice {
  _Phone(this.p, this.on);
  final PushPermission p;
  final bool on;
  @override
  Future<bool> available() async => true;
  @override
  Future<bool> ensure(NotificationsRepository n) async => on;
  @override
  Future<PushPermission> permission() async => p;
}

void main() {
  setUpAll(loadFonts);
  for (final (name, p, on) in [
    ('on', PushPermission.granted, true),
    ('off', PushPermission.prompt, false),
    ('blocked', PushPermission.blocked, false),
  ]) {
    for (final lang in ['fr', 'en']) {
      testWidgets('r2 $name $lang', (tester) async {
        size(tester, 390, 844);
        await tester.pumpWidget(app(
            Scaffold(
                body: SafeArea(
                    child: NotificationSettingsSheet(
                        notify: _Notify(), audiences: const {'customer'}, device: _Phone(p, on)))),
            lang: lang));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await shoot(tester, 'b122_R_r2_notifications_${name}_$lang');
      });
    }
  }
}

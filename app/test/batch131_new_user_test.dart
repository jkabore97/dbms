import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/admin/center/settings_section.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Batch 131 (129): every platform admin hears of each new account.
void main() {
  NotificationRow row(Map<String, dynamic> params, {String message = 'Nouveau compte : Awa (Google)'}) =>
      NotificationRow.fromRow({
        'id': 'n1', 'kind': 'new_user', 'message': message, 'params': params,
        'created_at': '2026-10-12T10:00:00Z',
      });

  Future<List<String>> lines(WidgetTester tester, String lang, List<NotificationRow> rows) async {
    late List<String> out;
    await tester.pumpWidget(MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: Builder(builder: (context) {
        out = [for (final r in rows) notificationLine(context, r)];
        return const SizedBox();
      }),
    ));
    return out;
  }

  testWidgets('the bell says the new account and how it signed up, in English and in French', (tester) async {
    final rows = [
      row({'to': 'platform', 'name': 'Awa Ouédraogo', 'method': 'google'}),
      row({'to': 'platform', 'name': 'Fatou', 'method': 'apple'}),
      row({'to': 'platform', 'name': 'issa@example.org', 'method': 'email'}),
      row({'to': 'platform', 'name': '+22670000000', 'method': 'phone'}),
    ];
    expect(await lines(tester, 'en', rows), [
      'New account: Awa Ouédraogo (Google)',
      'New account: Fatou (Apple)',
      'New account: issa@example.org (email)',
      'New account: +22670000000 (phone)',
    ]);
    // A French phone shows the server's line, word for word the push.
    expect(await lines(tester, 'fr', [rows.first]), ['Nouveau compte : Awa (Google)']);
  });

  test('it belongs to the platform\'s list, and opens the person\'s fiche in « Personnes »', () {
    final n = row({
      'to': 'platform',
      'user_id': '12912912-0000-0000-0000-000000000004',
      'name': 'Awa',
      'method': 'google',
      'contact': 'awa+1@example.org',
    });
    expect(n.scope, 'platform');
    expect(NotificationRow.scopeOf('new_user', null, {'to': 'platform'}), 'platform');
    final target = Uri.parse(notificationTarget(n)!);
    expect(target.path, Routes.consolePeople);
    expect(target.queryParameters,
        {'q': 'awa+1@example.org', 'personne': '12912912-0000-0000-0000-000000000004'});
    // Without facts: the list itself.
    expect(notificationTarget(row({})), Routes.consolePeople);
  });

  test('Réglages › Nouveaux comptes has the switch', () {
    final d = platformSettingDefs.firstWhere((d) => d.key == 'admin_new_user_notify');
    expect(d.group, 'accounts');
    expect(d.type, SettingType.flag);
  });
}

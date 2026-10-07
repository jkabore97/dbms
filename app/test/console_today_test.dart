import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/format/money.dart';
import 'package:kaj_app/features/admin/console_today.dart';

/// The platform's figures (072), under « À faire » in the command center
/// (104).
class _Admin extends AdminRepository {
  _Admin(this.today) : super(null);

  final PlatformToday? today;
  final sent = <String>[];

  @override
  Future<PlatformToday?> platformToday() async => today;

  @override
  Future<int> sendPlatformMessage(String? orgId, String message) async {
    sent.add('${orgId ?? 'all'}:$message');
    return 12;
  }
}

PlatformToday _day() =>
    PlatformToday.fromJson({
      'money': {'pro': 30000, 'spots': 2500, 'delivery_cut': 1200, 'shops_sold': 90000},
      'growth': {'businesses': 14, 'new_month': 3, 'windows_open': 4,
          'windows_stocked': 1, 'orders_week': 9, 'orders_last_week': 5,
          'shoppers_new': 4, 'windows_opened_week': 120},
      'health': {'silent_30': 6, 'empty_windows': 3, 'pins_far': 2,
          'published': 70, 'no_photo': 69},
    });

void main() {
  Future<_Admin> pump(WidgetTester tester, PlatformToday? today) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = _Admin(today);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
              body: SingleChildScrollView(child: ConsoleToday(admin: admin))),
        ),
      ]),
    ));
    await tester.pump();
    await tester.pump();
    return admin;
  }

  // What waits is « À faire »'s own now (105): test/command_center_test.dart.
  testWidgets('money, growth and health are figures', (tester) async {
    await pump(tester, _day());
    expect(find.text('À traiter'), findsNothing,
        reason: '« À faire » counts what waits, above these figures');
    expect(find.text('gagné ${moneyFormat('XOF').format(33700)}'),
        findsOneWidget);
    expect(find.text('+4 sur la semaine dernière'), findsOneWidget);
    expect(find.text('sur 70 articles en vitrine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing for anyone but the platform', (tester) async {
    await pump(tester, null);
    expect(find.text('Ce mois'), findsNothing);
  });

  testWidgets('Écrire aux boutiques sends to every business', (tester) async {
    final admin = await pump(tester, _day());
    await tester.ensureVisible(find.text('Écrire aux boutiques'));
    await tester.tap(find.text('Écrire aux boutiques'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ajoutez vos photos');
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    expect(admin.sent, ['all:Ajoutez vos photos']);
    expect(find.text('Message envoyé à 12 personnes.'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/access/plan_terms.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/features/admin/center/command_center_shell.dart';
import 'package:kaj_app/features/admin/pro_console_screen.dart';

/// The owner's screen (120): « Mara Pro » in the command center on a
/// phone, a price field touched — the page went all white under the
/// keyboard. The real page, inside the real shell.

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<PlanTerms> planTerms() async =>
      const PlanTerms(stripeOn: true, priceMonth: 2900, priceYear: 29900);
  @override
  Future<List<PlanRequest>> planRequestsOpen() async => const [];
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);
  @override
  bool get isConfigured => true;
  @override
  Future<PlatformTodo> todo() async => const PlatformTodo({});
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  for (final size in const [Size(412, 915), Size(360, 640)]) {
    testWidgets('« Mara Pro » stays drawn with the keyboard up (${size.width.toInt()})',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: GoRouter(initialLocation: Routes.consolePro, routes: [
          ShellRoute(
            builder: (_, _, child) =>
                CommandCenterShell(center: _Center(), platformAdmin: true, child: child),
            routes: [
              GoRoute(path: Routes.consolePro, builder: (_, _) => ProConsoleScreen(admin: _Admin())),
            ],
          ),
        ]),
      ));
      await _settle(tester);
      final month = find.widgetWithText(TextField, 'Prix par mois (XOF)');
      await tester.scrollUntilVisible(month, 200,
          scrollable: find
              .descendant(of: find.byType(ProConsoleScreen), matching: find.byType(Scrollable))
              .first);
      await _settle(tester);
      await tester.showKeyboard(month);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _settle(tester);
      await tester.ensureVisible(month);
      await _settle(tester);

      final list = tester.getRect(find
          .descendant(of: find.byType(ProConsoleScreen), matching: find.byType(Scrollable))
          .first);
      // The list reaches the keyboard: the keyboard taken off once.
      expect(list.bottom, size.height - 300);
      expect(list.height, greaterThan(150));
      final field = tester.getRect(month);
      expect(field.top, greaterThanOrEqualTo(list.top));
      expect(field.bottom, lessThanOrEqualTo(size.height - 300));
      expect(month.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

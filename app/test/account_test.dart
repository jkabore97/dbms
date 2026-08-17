import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/account/legal_screens.dart';
import 'package:kaj_app/features/notify/notifications_screen.dart';
import 'package:kaj_app/l10n/strings.dart';

/// The pieces item #11 adds that stand on their own: the static legal/help
/// pages, and the notification bell that stays put when offline.
void main() {
  Widget host(Widget child) => MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: child,
      );

  group('the legal and help pages', () {
    testWidgets('the privacy policy renders its headings', (tester) async {
      await tester.pumpWidget(host(const PrivacyScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Politique de confidentialité'), findsOneWidget);
      expect(find.text('Ce que nous collectons'), findsOneWidget);
      expect(find.text('Où elles sont stockées'), findsOneWidget);
    });

    testWidgets('the terms render', (tester) async {
      await tester.pumpWidget(host(const TermsScreen()));
      await tester.pumpAndSettle();
      expect(find.text("Conditions d'utilisation"), findsOneWidget);
      expect(find.text('Votre compte'), findsOneWidget);
    });

    testWidgets('the FAQ answers the offline question', (tester) async {
      await tester.pumpWidget(host(const FaqScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Questions fréquentes'), findsOneWidget);
      expect(
        find.text("L'application fonctionne-t-elle sans internet ?"),
        findsOneWidget,
      );
    });
  });

  group('the notification bell', () {
    IconButton bell(WidgetTester tester) =>
        tester.widget<IconButton>(find.byType(IconButton));

    testWidgets('is present but inert when offline', (tester) async {
      await tester.pumpWidget(host(Scaffold(
        appBar: AppBar(actions: [
          NotificationBell(
            notify: NotificationsRepository(null),
            listRoute: '/x',
            enabled: false,
          ),
        ]),
      )));
      await tester.pumpAndSettle();
      // The bell is still on the bar, but disabled — a control that greys out
      // reads as "later", where one that vanishes reads as "never existed".
      expect(find.byType(NotificationBell), findsOneWidget);
      expect(bell(tester).onPressed, isNull);
    });

    testWidgets('is live when online', (tester) async {
      await tester.pumpWidget(host(Scaffold(
        appBar: AppBar(actions: [
          NotificationBell(
            notify: NotificationsRepository(null),
            listRoute: '/x',
            enabled: true,
          ),
        ]),
      )));
      await tester.pumpAndSettle();
      expect(bell(tester).onPressed, isNotNull);
    });
  });
}

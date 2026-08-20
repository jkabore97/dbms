import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/features/admin/platform_audit_screen.dart';

/// The platform-wide activity log (048): it lists events across every business,
/// names each one, and the action filter narrows it.
class _FakeConsole extends ConsoleRepository {
  _FakeConsole() : super(null);

  final _all = [
    PlatformAuditEvent(
        id: 3,
        at: DateTime(2026, 1, 3, 10, 15),
        orgId: 'a',
        orgName: 'Boutique A',
        action: 'delete',
        tableName: 'products',
        actorLabel: 'Awa',
        summary: 'Savon retiré'),
    PlatformAuditEvent(
        id: 2,
        at: DateTime(2026, 1, 2, 9, 0),
        orgId: 'b',
        orgName: 'Ferme B',
        action: 'update',
        tableName: 'orgs',
        actorLabel: 'Boro',
        summary: 'Nom modifié'),
  ];

  @override
  Future<List<PlatformAuditEvent>> platformAudit({
    int limit = 50,
    int? before,
    String? orgId,
    String? action,
    String? table,
  }) async =>
      action == null ? _all : _all.where((e) => e.action == action).toList();
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('lists events across businesses, named', (tester) async {
    await tester.pumpWidget(wrap(PlatformAuditScreen(console: _FakeConsole())));
    await tester.pump();

    expect(find.text('Savon retiré'), findsOneWidget);
    expect(find.text('Nom modifié'), findsOneWidget);
    expect(find.textContaining('Boutique A'), findsOneWidget);
    expect(find.textContaining('Ferme B'), findsOneWidget);
  });

  testWidgets('the Suppressions filter narrows to deletions', (tester) async {
    await tester.pumpWidget(wrap(PlatformAuditScreen(console: _FakeConsole())));
    await tester.pump();

    await tester.tap(find.text('Suppressions'));
    await tester.pump(); // reload

    expect(find.text('Savon retiré'), findsOneWidget);
    expect(find.text('Nom modifié'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/console/console_repository.dart';
import 'package:kaj_app/core/console/models.dart';
import 'package:kaj_app/features/admin/platform_console_screen.dart';

/// The owner: « How do I delete an association even when the owner is
/// still there? It doesn't allow me. » The console's « Supprimer… » never
/// sent the second, explicit act the server asks for a business with books
/// (an association's contributions), so it was always refused. Now it asks,
/// says how many entries, and deletes them only on « oui ».
class _Admin extends AdminRepository {
  _Admin() : super(null);

  final calls = <String>[];

  @override
  Future<Set<String>> eventsAllowedOrgs() async => const {};

  @override
  Future<void> setEventsAllowed(String orgId, bool on) async => calls.add('allow:$orgId $on');

  @override
  Future<void> deleteOrg({required String orgId, required String confirmName, bool force = false}) async {
    calls.add('delete:$orgId force=$force');
    if (!force) throw Exception('Entraide has 12 entries in its books. Deleting destroys them permanently.');
  }
}

class _Console extends ConsoleRepository {
  _Console({this.kind = 'association', this.archived = true}) : super(null);

  final String kind;
  final bool archived;

  @override
  bool get isConfigured => true;

  @override
  Future<PlatformOverview> overview() async => const PlatformOverview(total: 1, active: 0);

  @override
  Future<OrgPage> searchOrgs({
    String? query,
    String? profile,
    String status = 'active',
    String? activity,
    String sort = 'activity',
    int limit = 50,
    int offset = 0,
  }) async =>
      OrgPage(rows: [
        OrgRow(id: 'a1', name: 'Entraide', slug: 'entraide', profile: kind, currency: 'XOF', memberCount: 1,
            archivedAt: archived ? DateTime(2026, 11, 1) : null),
      ], total: 1);
}

void main() {
  setUpAll(() async => initializeDateFormatting('fr_FR', null));

  testWidgets('an archived association with books and its owner: deleted, its books too once said yes', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = _Admin();
    await tester.pumpWidget(MaterialApp(home: PlatformConsoleScreen(console: _Console(), admin: admin)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Entraide');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(admin.calls, ['delete:a1 force=false']);
    expect(find.text('Ses comptes aussi ?'), findsOneWidget);
    expect(find.textContaining('12 écriture(s)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('console-delete-books')));
    await tester.pumpAndSettle();
    expect(admin.calls, ['delete:a1 force=false', 'delete:a1 force=true']);
  });

  // 167: an Événementiel let in while the module is closed, from its row.
  testWidgets('an Événementiel: « Autoriser l’Événementiel » lets it in', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final admin = _Admin();
    await tester.pumpWidget(MaterialApp(home: PlatformConsoleScreen(console: _Console(kind: 'events', archived: false), admin: admin)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autoriser l’Événementiel (module fermé)'));
    await tester.pumpAndSettle();
    expect(admin.calls, ['allow:a1 true']);
  });

  testWidgets('a shop has no such entry', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PlatformConsoleScreen(console: _Console(kind: 'retail', archived: false), admin: _Admin())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Événementiel'), findsNothing);
  });
}

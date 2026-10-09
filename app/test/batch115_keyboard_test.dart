import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/admin/models.dart';
import 'package:kaj_app/core/auth/models.dart';
import 'package:kaj_app/core/console/command_center.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:kaj_app/core/retail/models.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:kaj_app/core/shopper/shopper_repository.dart';
import 'package:kaj_app/core/storefront/storefront_repository.dart';
import 'package:kaj_app/core/theme/kaj_theme.dart';
import 'package:kaj_app/features/admin/center/center_search.dart';
import 'package:kaj_app/features/admin/member_edit_sheet.dart';
import 'package:kaj_app/features/church/record_transfer_sheet.dart';
import 'package:kaj_app/features/common/step_flow.dart';
import 'package:kaj_app/features/farm/for_sale_screen.dart';
import 'package:kaj_app/features/retail/sale_flow.dart';
import 'package:kaj_app/features/services/services_screen.dart';
import 'package:kaj_app/features/shopper/addresses_screen.dart';
import 'package:kaj_app/features/storefront/storefront_screen.dart' as street;
import 'package:kaj_app/l10n/strings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The owner's « In some entries, when the keyboard comes up I can't see
/// the text anymore » (batch 115, A6): the worst offenders opened as the
/// app opens them, on a 360 × 640 phone, the keyboard up (300 px): the
/// field being typed into and the sheet's primary button are both on
/// screen, above the keyboard, and nothing overflows. The old « Nouveau
/// service » sheet kept for editing is the first of them; the command
/// center's search the second.

const _phone = Size(360, 640);
const _keyboard = 300.0;

/// What is left above the keyboard.
final _visible = Rect.fromLTWH(0, 0, _phone.width, _phone.height - _keyboard);

bool _inside(Rect r) =>
    r.top >= _visible.top - 0.5 &&
    r.bottom <= _visible.bottom + 0.5 &&
    r.left >= -0.5 &&
    r.right <= _visible.right + 0.5;

Widget _app(Widget home) => MaterialApp(
      theme: kajTheme(kajPalette),
      locale: const Locale('fr'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      home: home,
    );

/// Opens [sheet] as the app does (scroll-controlled, under the status bar),
/// types into [field] with the keyboard up, and checks [field] and
/// [button] are on screen.
Future<void> _sheetWithKeyboard(WidgetTester tester, WidgetBuilder sheet,
    {required Finder field, required Finder button}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('open'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: sheet,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  )));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  await _type(tester, field, button);
}

Future<void> _type(WidgetTester tester, Finder field, Finder button) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.showKeyboard(field);
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'nothing overflows with the keyboard up');
  final f = tester.getRect(field);
  final b = tester.getRect(button);
  expect(_inside(f), isTrue, reason: 'the field typed into is above the keyboard: $f');
  expect(_inside(b), isTrue, reason: 'the primary button is above the keyboard: $b');
  expect(b.overlaps(f), isFalse, reason: 'the button is not over the field');
  // The field whole, not cut by the edge of its scroll view.
  final view = find.ancestor(of: field, matching: find.byType(Scrollable));
  if (view.evaluate().isNotEmpty) {
    final v = tester.getRect(view.first);
    expect(f.top >= v.top - 0.5 && f.bottom <= v.bottom + 0.5, isTrue,
        reason: 'the field is whole in its scroll view: $f in $v');
  }
  // A tap on the button lands on it, not on something drawn over it.
  expect(_tappable(tester, button), isTrue, reason: 'the button can be tapped');
}

bool _tappable(WidgetTester tester, Finder button) {
  final targets = {
    for (final e in tester.hitTestOnBinding(tester.getCenter(button)).path) e.target,
  };
  final mine = {
    for (final e in [
      ...button.evaluate(),
      ...find.descendant(of: button, matching: find.byWidgetPredicate((_) => true)).evaluate(),
    ])
      e.renderObject,
  };
  return targets.any(mine.contains);
}

class _Shop extends RetailRepository {
  _Shop() : super(null);
}

const _shop = OrgSummary(id: 'r1', name: 'Boutique Awa', profile: 'retail', roles: ['owner'], currency: 'XOF');
const _farm = OrgSummary(id: 'f1', name: 'Ferme du Nord', profile: 'farm', roles: ['owner'], currency: 'XOF');

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('fr_FR', null);
  });

  testWidgets('the service kept for editing: its last field and « Enregistrer » (shop, farm, association)',
      (tester) async {
    await _sheetWithKeyboard(
      tester,
      (_) => ServiceSheet(
        org: _shop,
        retail: _Shop(),
        service: const Product(id: 's1', name: 'Coupe homme', salePrice: 1500, quantity: 0, isService: true),
      ),
      field: find.byKey(const Key('service-description')),
      button: find.byKey(const Key('service-save')),
    );
  });

  testWidgets('a farm\'s article for sale: its price and « Enregistrer »', (tester) async {
    await _sheetWithKeyboard(
      tester,
      (_) => ForSaleSheet(
        org: _farm,
        retail: _Shop(),
        product: const Product(id: 'p1', name: 'Œufs', salePrice: 2500, quantity: 10),
      ),
      field: find.byKey(const Key('for-sale-price')),
      button: find.byKey(const Key('for-sale-save')),
    );
  });

  testWidgets('a member\'s details: the family name and « Enregistrer »', (tester) async {
    await _sheetWithKeyboard(
      tester,
      (_) => EditMemberSheet(
        admin: AdminRepository(null),
        member: const Member(
            membershipId: 'm1', userId: 'u1', role: 'employee', scopeKind: 'org',
            scopeId: 'r1', visibility: 'full', firstName: 'Awa', lastName: 'Ouédraogo'),
      ),
      field: find.byKey(const Key('member-last')),
      button: find.byKey(const Key('member-save')),
    );
  });

  testWidgets('the shopper\'s address: its note for the courier and « Enregistrer »', (tester) async {
    await _sheetWithKeyboard(
      tester,
      (_) => AddressSheet(shopper: ShopperRepository(null), tiles: false),
      field: find.byKey(const Key('address-note')),
      button: find.byKey(const Key('address-save')),
    );
  });

  testWidgets('the vitrine\'s order: the word for the shop and « Envoyer la commande »', (tester) async {
    await _sheetWithKeyboard(
      tester,
      (_) => street.OrderSheet(
        items: const [PublicItem(id: 'p1', name: 'Savon', price: 450, inStock: true)],
        basket: const {'p1': 2},
        currency: 'XOF',
        delivers: false,
        onSubmit: ({required lines, required fulfilment, note, address, phone,
                required payment, dropLat, dropLng}) async => null,
        quote: (lat, lng) async => null,
      ),
      field: find.byKey(const Key('order-note')),
      button: find.widgetWithText(FilledButton, 'Envoyer la commande'),
    );
  });

  testWidgets('Wave at the till: the sender\'s name and « Paiement reçu »', (tester) async {
    await _sheetWithKeyboard(
      tester,
      (_) => const WavePaymentSheet(merchant: 'M-1', amount: 900, currency: 'XOF'),
      field: find.byType(TextField),
      button: find.widgetWithText(FilledButton, 'Paiement reçu'),
    );
  });

  testWidgets('an association\'s transfer: its name and « Enregistrer le transfert »', (tester) async {
    final db = (await tester.runAsync(() => LocalDb.open(path: inMemoryDatabasePath)))!;
    addTearDown(() => tester.runAsync(db.close));
    await _sheetWithKeyboard(
      tester,
      (_) => RecordTransferSheet(db: db, orgId: 'a1'),
      field: find.byType(TextField).last,
      button: find.widgetWithText(FilledButton, 'Enregistrer le transfert'),
    );
  });

  testWidgets('a step of a flow: the last field and « Suivant » above the keyboard', (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(StepFlow(
      title: 'Facture',
      store: MemoryFlowStore(),
      steps: [
        FlowStep(
          id: 'who',
          title: 'Pour qui ?',
          help: 'Le nom du client, son numéro et un mot.',
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final k in ['a', 'b', 'c'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(key: Key('field-$k'), maxLines: k == 'c' ? 3 : 1),
                ),
            ],
          ),
        ),
      ],
      summary: (_) => const Text('Résumé'),
      onSave: () async => true,
      done: (_) => const Text('Fait'),
    )));
    await tester.pumpAndSettle();
    await _type(tester, find.byKey(const Key('field-c')), find.byKey(const Key('flow-next')));
  });

  testWidgets('the command center\'s search on a phone: never blank with the keyboard up',
      (tester) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open'),
            onPressed: () => showCenterSearch(context, _Center()),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final field = tester.getRect(find.byKey(const Key('center-search-field')));
    expect(_inside(field), isTrue, reason: 'the search field is on screen: $field');
    // What to type is said under it, above the keyboard.
    final help = find.textContaining('Une entreprise par son nom');
    expect(help, findsOneWidget);
    expect(tester.getRect(help).top, lessThan(_visible.bottom), reason: 'the panel is not blank');
    // The list fills exactly what the keyboard leaves: nothing blank.
    final list = tester.getRect(find.byKey(const Key('center-search-list')));
    expect(list.bottom, closeTo(_visible.bottom, 1), reason: 'the panel reaches the keyboard: $list');
    // Typed: the answers are listed above the keyboard.
    await tester.enterText(find.byKey(const Key('center-search-field')), 'Awa');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final hit = find.byKey(const Key('hit-org-o1'));
    expect(hit, findsOneWidget);
    expect(tester.getRect(hit).top, lessThan(_visible.bottom));
  });
}

class _Center extends CommandCenterRepository {
  _Center() : super(null);

  @override
  Future<SearchResults> search(String query) async => SearchResults.fromJson(const {
        'businesses': [
          {'id': 'o1', 'name': 'Boutique Awa', 'profile': 'retail'},
        ],
      });
}

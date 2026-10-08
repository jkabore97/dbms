import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kaj_app/core/admin/admin_repository.dart';
import 'package:kaj_app/core/courier/courier_dossier.dart';
import 'package:kaj_app/core/nav/router.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';
import 'package:kaj_app/features/admin/courier_review_screen.dart';
import 'package:kaj_app/features/admin/couriers_screen.dart';
import 'package:kaj_app/features/courier/become_courier_screen.dart';
import 'package:kaj_app/features/notify/notification_text.dart';
import 'package:kaj_app/features/storefront/shop_style.dart';
import 'package:kaj_app/l10n/strings.dart';

/// Becoming a courier (112), for a person who is not a business — the
/// shop's, the farm's and the association's people apply the same way.
///
/// A fake server keeps the dossier the way 112 does (the steps open, the
/// photos as booleans, the timeline); test_batch112.sql proves the real one.

/// A 1×1 PNG: what the camera hands back here.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _all = ['zone', 'hours', 'vehicle', 'selfie', 'id', 'phone', 'charter'];

class _Server extends CourierDossierRepository {
  _Server({Map<String, dynamic>? start, this.mobileMoney = false, this.licenceRequired = false})
      : row = start ?? {},
        super(null);

  Map<String, dynamic> row;
  final bool mobileMoney;
  final bool licenceRequired;
  final saves = <(String, Map<String, Object?>)>[];
  int sends = 0;
  final decisions = <(String, String?, List<String>?, String?)>[];
  final undone = <String>[];

  Map<String, dynamic> get _json => {
        'status': row['status'],
        'courier_status': row['courier_status'],
        'files': {
          for (final p in ['selfie', 'id_front', 'id_back', 'licence']) p: (row['files'] ?? {})[p] == true,
        },
        'open_steps': row['status'] == null || row['status'] == 'draft'
            ? _all
            : row['status'] == 'refused'
                ? row['reopened']
                : <String>[],
        'timeline': row['timeline'] ?? [],
        'refusal': row['status'] == 'refused'
            ? {'reason': row['reason'], 'note': row['note'], 'steps': row['reopened']}
            : null,
        'rules': {
          'licence_required': licenceRequired,
          'phone_verified': false,
          'mobile_money': mobileMoney,
          'charter_version': 1,
        },
        for (final k in ['city', 'zones', 'days', 'hours_from', 'hours_to', 'vehicle', 'vehicle_make',
            'vehicle_model', 'vehicle_colour', 'vehicle_plate', 'id_kind', 'phone', 'payout_number',
            'charter_version', 'verified_phone'])
          k: row[k],
      };

  @override
  bool get isConfigured => true;

  @override
  Future<CourierDossier> mine() async => CourierDossier.fromJson(_json);

  @override
  Future<CourierDossier> save(String step, Map<String, Object?> answers) async {
    saves.add((step, answers));
    row['status'] ??= 'draft';
    row.addAll(answers);
    return mine();
  }

  @override
  Future<CourierDossier> send() async {
    sends++;
    row['status'] = 'pending';
    row['courier_status'] = 'pending';
    row['timeline'] = [
      ...(row['timeline'] as List? ?? []),
      {'at': '2026-10-08T10:00:00Z', 'kind': 'sent'},
    ];
    return mine();
  }

  // The platform's side.
  @override
  Future<List<CourierApplicationRow>> applications() async => [
        CourierApplicationRow.fromRow({
          'user_id': 'u-awa', 'name': 'Awa Livreuse', 'status': 'pending', 'courier_status': 'pending',
          'city': 'Ouagadougou', 'vehicle': 'moto', 'sent_at': '2026-10-08T09:00:00Z',
        }),
        CourierApplicationRow.fromRow({
          'user_id': 'u-ali', 'name': 'Ali Cycliste', 'status': 'refused',
          'city': 'Bobo-Dioulasso', 'vehicle': 'velo', 'decided_at': '2026-10-07T09:00:00Z',
          'refusal_reason': 'blurry',
        }),
      ];

  @override
  Future<CourierDossier> dossier(String userId) async => CourierDossier.fromJson({
        'user_id': userId,
        'name': 'Awa Livreuse',
        'status': row['status'] ?? 'pending',
        'courier_status': row['courier_status'] ?? 'pending',
        'city': 'Ouagadougou',
        'zones': ['Gounghin', 'Pissy'],
        'days': ['lun', 'mar', 'sam'],
        'hours_from': '07:30',
        'hours_to': '19:00',
        'vehicle': 'moto',
        'vehicle_make': 'Yamaha',
        'vehicle_model': 'Crypton',
        'vehicle_colour': 'Rouge',
        'vehicle_plate': '11 KK 2233',
        'id_kind': 'cnib',
        'phone': '+22670112002',
        'phone_verified': true,
        'charter_version': 1,
        'charter_at': '2026-10-08T08:00:00Z',
        'sent_at': '2026-10-08T09:00:00Z',
        'photos': {
          'selfie': 'courier/u-awa/s.jpg',
          'id_front': 'courier/u-awa/f.jpg',
          'id_back': 'courier/u-awa/b.jpg',
          'licence': null,
        },
        'timeline': [
          {'at': '2026-10-08T09:00:00Z', 'kind': 'sent'},
        ],
        'rules': {'licence_required': false, 'phone_verified': false, 'mobile_money': false, 'charter_version': 1},
      });

  @override
  Future<String?> decide(String userId, String decision, {String? reason, List<String>? steps, String? note}) async {
    decisions.add((decision, reason, steps, note));
    row['status'] = decision == 'approve' ? 'approved' : 'refused';
    return 'action-1';
  }

  @override
  Future<void> undo(String actionId) async {
    undone.add(actionId);
    row['status'] = 'pending';
  }
}

class _Files extends CourierFiles {
  _Files(this.server) : super(null, url: 'https://up.example');

  final _Server server;
  final uploads = <(String, int, String)>[];
  final asked = <String>[];
  int purges = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<void> upload(String part, Uint8List bytes, String contentType) async {
    uploads.add((part, bytes.length, contentType));
    (server.row['files'] ??= <String, bool>{})[part] = true;
  }

  @override
  Future<Uint8List> photo(String key) async {
    asked.add(key);
    return _png;
  }

  @override
  Future<void> purge() async => purges++;
}

class _Admin extends AdminRepository {
  _Admin() : super(null);
  @override
  Future<List<PlatformCourier>> platformCouriers() async => [
        PlatformCourier.fromRow({'user_id': 'u-awa', 'name': 'Awa Livreuse', 'phone': '+22670112002',
            'status': 'pending', 'created_at': '2026-10-08T09:00:00Z'}),
        // Registered before dossiers: approved from the list as before.
        PlatformCourier.fromRow({'user_id': 'u-old', 'name': 'Oumar Ancien', 'phone': '+22611200007',
            'status': 'pending', 'created_at': '2026-09-01T09:00:00Z'}),
        PlatformCourier.fromRow({'user_id': 'u-ok', 'name': 'Issa Approuvé', 'phone': '+22611200009',
            'status': 'approved', 'created_at': '2026-08-01T09:00:00Z'}),
      ];
}

Widget _app(Widget home, {List<RouteBase> more = const []}) {
  final router = GoRouter(initialLocation: '/x', routes: [
    GoRoute(path: '/x', builder: (_, _) => home),
    GoRoute(path: Routes.courier, builder: (_, _) => const Scaffold(body: Text('ESPACE LIVREUR'))),
    GoRoute(path: Routes.directory, builder: (_, _) => const Scaffold(body: Text('LA RUE'))),
    GoRoute(path: '/console/livreurs/dossier/:id',
        builder: (_, s) => Scaffold(body: Text('DOSSIER ${s.pathParameters['id']}'))),
    ...more,
  ]);
  return MaterialApp.router(
    routerConfig: router,
    locale: const Locale('fr'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('courier-next')));
  await _settle(tester);
}

Future<CourierShot?> _camera({required bool selfie, bool gallery = false}) async =>
    (bytes: _png, type: 'image/png');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR', null));

  group('the dossier, one question per screen', () {
    testWidgets('a moto, start to « Envoyer ma demande »: each step saved, the photos sent, then the wait',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server();
      final files = _Files(server);
      await tester.pumpWidget(_app(BecomeCourierScreen(dossier: server, files: files, camera: _camera)));
      await _settle(tester);

      // The applicant's own due photos go as the page opens.
      expect(files.purges, 1);
      expect(find.byKey(const Key('courier-intro')), findsOneWidget);
      await tester.tap(find.byKey(const Key('courier-start')));
      await _settle(tester);

      // 1. Where: « Suivant » waits for a town and a quartier.
      expect(find.text('Où livrez-vous ?'), findsOneWidget);
      expect(find.text('Étape 1 sur 9'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('courier-next'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('courier-city')), 'Ouagadougou');
      await tester.enterText(find.byKey(const Key('courier-zone')), 'Gounghin');
      await tester.tap(find.byKey(const Key('courier-zone-add')));
      await tester.enterText(find.byKey(const Key('courier-zone')), 'Pissy');
      await tester.tap(find.byKey(const Key('courier-zone-add')));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'Pissy'), findsOneWidget);
      await _next(tester);
      expect(server.saves.last, ('zone', {'city': 'Ouagadougou', 'zones': ['Gounghin', 'Pissy']}));

      // 2. When.
      expect(find.text('Quand êtes-vous disponible ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('courier-day-lun')));
      await tester.tap(find.byKey(const Key('courier-day-sam')));
      await tester.pump();
      await _next(tester);
      expect(server.saves.last.$1, 'hours');
      expect(server.saves.last.$2['days'], ['lun', 'sam']);
      expect(server.saves.last.$2['hours_from'], '08:00');

      // 3. On what — a moto asks its make, model, colour and plate next.
      await tester.tap(find.byKey(const Key('courier-vehicle-moto')));
      await tester.pump();
      await _next(tester);
      expect(server.saves.last.$1, 'hours', reason: 'a moto is saved with its details');
      expect(find.byKey(const Key('courier-plate')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('courier-make')), 'Yamaha');
      await tester.enterText(find.byKey(const Key('courier-model')), 'Crypton');
      await tester.enterText(find.byKey(const Key('courier-colour')), 'Rouge');
      await tester.enterText(find.byKey(const Key('courier-plate')), '11 KK 2233');
      await tester.pump();
      await _next(tester);
      expect(server.saves.last, ('vehicle', {
        'vehicle': 'moto', 'vehicle_make': 'Yamaha', 'vehicle_model': 'Crypton',
        'vehicle_colour': 'Rouge', 'vehicle_plate': '11 KK 2233',
      }));

      // 4. The selfie: the front camera, the picture sent, then « Suivant ».
      expect(find.text('Une photo de vous'), findsOneWidget);
      expect(find.text('Sans lunettes de soleil ni casquette'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('courier-next'))).onPressed, isNull);
      await tester.tap(find.descendant(of: find.byKey(const Key('courier-photo-selfie')),
          matching: find.text('Prendre la photo')));
      await _settle(tester);
      expect(files.uploads.single, ('selfie', _png.length, 'image/png'));
      expect(find.text('Envoyée ✓'), findsOneWidget);
      await _next(tester);

      // 5. The ID: the kind, front and back; a moto's licence offered, optional.
      expect(find.text('Votre pièce d\'identité'), findsOneWidget);
      expect(find.text('Permis de conduire (facultatif)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('courier-id-cnib')));
      for (final part in ['id_front', 'id_back']) {
        await tester.tap(find.descendant(of: find.byKey(Key('courier-photo-$part')),
            matching: find.text('Prendre la photo')));
        await _settle(tester);
      }
      expect(files.uploads.map((u) => u.$1), ['selfie', 'id_front', 'id_back']);
      await _next(tester);
      expect(server.saves.last, ('id', {'id_kind': 'cnib'}));

      // 6. WhatsApp — RULE M: no mobile payment, no payout number; cash said.
      expect(find.byKey(const Key('courier-payout')), findsNothing);
      expect(find.text('Vos courses vous sont payées en espèces, à la porte.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '70112002');
      await tester.pump();
      await _next(tester);
      expect(server.saves.last, ('phone', {'phone': '+22670112002'}));

      // 7. The charter, accepted.
      expect(find.text('La charte du livreur'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('courier-next'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('courier-charter')));
      await tester.pump();
      await _next(tester);
      expect(server.saves.last, ('charter', {'charter_version': 1}));

      // 8. The summary, then « Envoyer ma demande ».
      expect(find.text('Tout est prêt ?'), findsOneWidget);
      expect(find.text('Étape 9 sur 9'), findsOneWidget);
      expect(find.text('Envoyer ma demande'), findsOneWidget);
      await _next(tester);
      expect(server.sends, 1);
      expect(find.byKey(const Key('courier-pending')), findsOneWidget);
      expect(find.text('Demande envoyée'), findsOneWidget);
      expect(find.text('En cours d\'examen'), findsNWidgets(2), reason: 'the title and the timeline\'s now');
    });

    testWidgets('a vélo: no details screen, no licence; with mobile payment on, the payout number is asked',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server(mobileMoney: true, start: {
        'status': 'draft', 'city': 'Bobo-Dioulasso', 'zones': ['Sarfalao'],
        'days': ['lun'], 'hours_from': '08:00', 'hours_to': '12:00',
      });
      final files = _Files(server);
      await tester.pumpWidget(_app(BecomeCourierScreen(dossier: server, files: files, camera: _camera)));
      await _settle(tester);
      expect(find.text('Continuer ma demande'), findsOneWidget);
      await tester.tap(find.byKey(const Key('courier-start')));
      await _settle(tester);
      // A draft resumes on its first step not done: the vehicle.
      expect(find.text('Comment livrez-vous ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('courier-vehicle-velo')));
      await tester.pump();
      await _next(tester);
      expect(server.saves.last, ('vehicle', {'vehicle': 'velo'}));
      expect(find.text('Une photo de vous'), findsOneWidget, reason: 'no details screen for a vélo');
      await tester.tap(find.text('Prendre la photo'));
      await _settle(tester);
      await _next(tester);
      expect(find.byKey(const Key('courier-photo-licence')), findsNothing);
      await tester.tap(find.byKey(const Key('courier-id-passeport')));
      for (final part in ['id_front', 'id_back']) {
        await tester.tap(find.descendant(of: find.byKey(Key('courier-photo-$part')),
            matching: find.text('Prendre la photo')));
        await _settle(tester);
      }
      await _next(tester);
      expect(find.byKey(const Key('courier-payout')), findsOneWidget);
      expect(find.byKey(const Key('courier-cash-line')), findsNothing);
    });

    testWidgets('licence required by the platform: a moto cannot go on without it', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server(licenceRequired: true, start: {
        'status': 'draft', 'city': 'Ouaga', 'zones': ['Gounghin'], 'days': ['lun'],
        'hours_from': '08:00', 'hours_to': '12:00', 'vehicle': 'moto', 'vehicle_make': 'Y',
        'vehicle_model': 'C', 'vehicle_colour': 'R', 'vehicle_plate': '11 KK', 'id_kind': 'cnib',
        'files': {'selfie': true, 'id_front': true, 'id_back': true},
      });
      await tester.pumpWidget(_app(BecomeCourierScreen(dossier: server, files: _Files(server), camera: _camera)));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('courier-start')));
      await _settle(tester);
      expect(find.text('Votre pièce d\'identité'), findsOneWidget);
      expect(find.text('Permis de conduire'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('courier-next'))).onPressed, isNull);
      await tester.tap(find.descendant(of: find.byKey(const Key('courier-photo-licence')),
          matching: find.text('Prendre la photo')));
      await _settle(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('courier-next'))).onPressed, isNotNull);
    });

    testWidgets('sent back « photo floue »: the reason, then only the selfie reopens, the rest kept',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server(start: {
        'status': 'refused', 'reason': 'blurry', 'note': 'Le visage est flou', 'reopened': ['selfie'],
        'city': 'Ouagadougou', 'zones': ['Gounghin'], 'days': ['lun'], 'hours_from': '08:00',
        'hours_to': '12:00', 'vehicle': 'velo', 'id_kind': 'cnib', 'phone': '+22670112002',
        'charter_version': 1, 'files': {'selfie': true, 'id_front': true, 'id_back': true},
        'timeline': [
          {'at': '2026-10-08T09:00:00Z', 'kind': 'sent'},
          {'at': '2026-10-08T10:00:00Z', 'kind': 'refused', 'reason': 'blurry'},
        ],
      });
      final files = _Files(server);
      await tester.pumpWidget(_app(BecomeCourierScreen(dossier: server, files: files, camera: _camera)));
      await _settle(tester);
      expect(find.byKey(const Key('courier-refused')), findsOneWidget);
      expect(find.text('Photo floue'), findsOneWidget);
      expect(find.text('« Le visage est flou »'), findsOneWidget);
      expect(find.text('À refaire : Selfie. Le reste de votre demande est gardé.'), findsOneWidget);
      expect(find.text('À corriger : Photo floue'), findsOneWidget, reason: 'the timeline');
      await tester.tap(find.byKey(const Key('courier-fix')));
      await _settle(tester);
      // Two screens only: the selfie, then the summary.
      expect(find.text('Étape 1 sur 2'), findsOneWidget);
      expect(find.text('Une photo de vous'), findsOneWidget);
      await tester.tap(find.text('Reprendre'));
      await _settle(tester);
      expect(files.uploads.single.$1, 'selfie');
      await _next(tester);
      expect(find.text('Tout est prêt ?'), findsOneWidget);
      // Only the reopened step is editable from the summary.
      expect(find.text('Modifier'), findsOneWidget);
      await _next(tester);
      expect(server.sends, 1);
      expect(server.saves, isEmpty, reason: 'nothing else was rewritten');
    });

    testWidgets('approved: « Vous êtes livreur » opens the courier space; suspended said in words',
        (tester) async {
      final server = _Server(start: {'status': 'approved', 'courier_status': 'approved'});
      await tester.pumpWidget(_app(BecomeCourierScreen(dossier: server, files: _Files(server), camera: _camera)));
      await _settle(tester);
      expect(find.text('Vous êtes livreur'), findsOneWidget);
      await tester.tap(find.byKey(const Key('courier-open-space')));
      await _settle(tester);
      expect(find.text('ESPACE LIVREUR'), findsOneWidget);

      final suspended = _Server(start: {'status': 'approved', 'courier_status': 'suspended'});
      await tester.pumpWidget(_app(BecomeCourierScreen(dossier: suspended, files: _Files(suspended), camera: _camera)));
      await _settle(tester);
      expect(find.text('Votre accès livreur est suspendu. Contactez la plateforme.'), findsOneWidget);
    });

    testWidgets('while examined, the page asks again on its own: the approval lands', (tester) async {
      final server = _Server(start: {'status': 'pending', 'courier_status': 'pending',
          'timeline': [{'at': '2026-10-08T09:00:00Z', 'kind': 'sent'}]});
      await tester.pumpWidget(_app(BecomeCourierScreen(
          dossier: server, files: _Files(server), camera: _camera, pollEvery: const Duration(seconds: 5))));
      await _settle(tester);
      expect(find.byKey(const Key('courier-pending')), findsOneWidget);
      server.row['status'] = 'approved';
      server.row['courier_status'] = 'approved';
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
      expect(find.text('Vous êtes livreur'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the platform\'s review', () {
    testWidgets('the selfie beside the ID, fetched through the private route; approve, with « Annuler »',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server(start: {'status': 'pending'});
      final files = _Files(server);
      await tester.pumpWidget(_app(CourierReviewScreen(userId: 'u-awa', dossier: server, files: files)));
      await _settle(tester);
      expect(files.asked, ['courier/u-awa/s.jpg', 'courier/u-awa/f.jpg', 'courier/u-awa/b.jpg']);
      // Side by side: the selfie and the front on one row.
      final selfie = tester.getTopLeft(find.byKey(const Key('review-photo-selfie')));
      final front = tester.getTopLeft(find.byKey(const Key('review-photo-id_front')));
      expect(selfie.dy, front.dy);
      expect(find.text('+22670112002 · vérifié sur WhatsApp'), findsOneWidget);
      expect(find.textContaining('Yamaha Crypton'), findsOneWidget);
      expect(find.text('Ouagadougou · Gounghin, Pissy'), findsOneWidget);
      // A moto with no licence photo: the slot says so.
      expect(find.text('Aucune photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-approve')));
      await _settle(tester);
      expect(server.decisions.single, ('approve', null, null, null));
      expect(find.text('Décision enregistrée. Le livreur est prévenu.'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await _settle(tester);
      expect(server.undone, ['action-1']);
    });

    testWidgets('« Refuser »: a ready reason presets the step to redo; « autre » needs a word', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server(start: {'status': 'pending'});
      await tester.pumpWidget(_app(CourierReviewScreen(userId: 'u-awa', dossier: server, files: _Files(server))));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('review-refuse')));
      await _settle(tester);
      for (final r in ['Photo floue', 'Pièce illisible', 'Visage différent de la pièce', 'Informations manquantes', 'Autre raison']) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
      await tester.tap(find.byKey(const Key('refuse-face')));
      await tester.pump();
      expect(tester.widget<FilterChip>(find.byKey(const Key('refuse-step-selfie'))).selected, isTrue);
      expect(tester.widget<FilterChip>(find.byKey(const Key('refuse-step-id'))).selected, isTrue);
      await tester.tap(find.byKey(const Key('refuse-other')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('refuse-step-vehicle')));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('refuse-send'))).onPressed, isNull,
          reason: '« autre » without a word');
      await tester.enterText(find.byKey(const Key('refuse-note')), 'La plaque ne correspond pas');
      await tester.pump();
      await tester.tap(find.byKey(const Key('refuse-send')));
      await _settle(tester);
      expect(server.decisions.single, ('refuse', 'other', ['vehicle'], 'La plaque ne correspond pas'));
    });

    testWidgets('« Demander une nouvelle photo »: the selfie or the ID', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server(start: {'status': 'pending'});
      await tester.pumpWidget(_app(CourierReviewScreen(userId: 'u-awa', dossier: server, files: _Files(server))));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('review-new-photo')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('review-photo-id')));
      await _settle(tester);
      expect(server.decisions.single, ('new_photo', 'id', null, null));
      // Decided: no more buttons.
      expect(find.byKey(const Key('review-approve')), findsNothing);
    });

    testWidgets('« Livreurs »: dossiers to validate first, then those sent back; an old registration keeps « Approuver »; the due photos purged',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server();
      final files = _Files(server);
      await tester.pumpWidget(_app(CouriersScreen(admin: _Admin(), dossier: server, files: files)));
      await _settle(tester);
      expect(files.purges, 1);
      expect(find.text('À valider'), findsOneWidget);
      expect(find.text('À corriger par le livreur'), findsOneWidget);
      // Awa's dossier waits: reviewed, not approved from the list.
      expect(find.descendant(of: find.byKey(const Key('dossier-u-awa')), matching: find.text('Examiner')),
          findsOneWidget);
      expect(find.text('Awa Livreuse'), findsOneWidget, reason: 'once, in « À valider »');
      expect(find.text('Photo floue · 7 oct.'), findsOneWidget);
      // Oumar registered before dossiers: his « Approuver » is as before.
      expect(find.widgetWithText(FilledButton, 'Approuver'), findsOneWidget);
      expect(find.text('Suspendre'), findsOneWidget);
      await tester.tap(find.text('Examiner'));
      await _settle(tester);
      expect(find.text('DOSSIER u-awa'), findsOneWidget);
    });
  });

  group('the doors in', () {
    test('the routes the shopper profile (113) links to, as agreed', () {
      expect(Routes.becomeCourier, '/devenir-livreur');
      expect(Routes.consoleCourierFile('u1'), '/console/livreurs/dossier/u1');
      final src = File('lib/core/nav/router.dart').readAsStringSync();
      // Signed in without a business, with one, picking: the page is allowed.
      expect(RegExp(r'at\(Routes\.becomeCourier\)').allMatches(src).length, 3);
      expect(src.contains('path: Routes.becomeCourier'), isTrue);
      expect(src.contains("'\${Routes.consoleCouriers}/dossier/:userId'"), isTrue);
    });

    testWidgets('the street\'s foot says « Devenir livreur »; a vitrine\'s foot does not', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ShopFooter(onBecomeCourier: () => tapped++)))));
      await tester.tap(find.byKey(const Key('footer-become-courier')));
      expect(tapped, 1);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ShopFooter(onDirectory: () {})))));
      expect(find.byKey(const Key('footer-become-courier')), findsNothing);
      final street = File('lib/features/storefront/directory_screen.dart').readAsStringSync();
      final vitrine = File('lib/features/storefront/storefront_screen.dart').readAsStringSync();
      expect(RegExp(r'ShopFooter\(onBecomeCourier: \(\) => context\.go\(Routes\.becomeCourier\)\)')
          .allMatches(street).length, 2);
      expect(vitrine.contains('onBecomeCourier'), isFalse);
    });

    testWidgets('the bell: the reason and the new photo in English, each opening the dossier', (tester) async {
      String? line;
      NotificationRow row(String kind, Map<String, dynamic> params) => NotificationRow.fromRow({
            'id': 'n1', 'kind': kind, 'message': 'fr', 'params': params,
            'created_at': '2026-10-08T10:00:00Z',
          });
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        home: Builder(builder: (context) {
          line = [
            notificationLine(context, row('courier_refused', {'reason': 'blurry', 'note': 'Le visage est flou'})),
            notificationLine(context, row('courier_photo', {'reason': 'new_id'})),
            notificationLine(context, row('courier_application', {'name': 'Awa'})),
          ].join(' | ');
          return const SizedBox();
        }),
      ));
      expect(line,
          'Your courier application needs a fix: blurry photo. Le visage est flou | '
          'Mara asks for a new photo of your ID. | New courier application: Awa');
      expect(notificationTarget(row('courier_refused', {})), Routes.becomeCourier);
      expect(notificationTarget(row('courier_photo', {})), Routes.becomeCourier);
      expect(notificationTarget(row('courier_application', {})), Routes.consoleCouriers);
      expect(notificationTarget(row('courier_approved', {})), Routes.courier);
    });

    test('the privacy page says where the ID photos are and when they go', () {
      final js = File('../workers/kaj-app/src/legal.js').readAsStringSync();
      expect(js.contains('"# Devenir livreur"'), isTrue);
      expect(js.contains("seule l'équipe Mara qui examine les demandes peut les voir"), isTrue);
      expect(js.contains('effacées 30 jours après le refus'), isTrue);
    });
  });
}

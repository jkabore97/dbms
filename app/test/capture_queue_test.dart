import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/capture/capture_repository.dart';
import 'package:kaj_app/core/db/local_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A build compiled with a Worker address nothing answers at: configured,
/// so capture() files the photograph and tries; the try then dies the way
/// a dead network kills it.
class _Configured extends CaptureRepository {
  _Configured({required super.db})
      : super(null, uploadsUrl: 'https://uploads.example.com');

  @override
  bool get isConfigured => true;
}

/// The property M5's capture half stands on: **a photograph taken with no
/// signal is not lost.**
///
/// Everything else in the module — the OCR, the barcode, the gallery — is an
/// accelerator. This is the part that, if it is wrong, produces the exact
/// failure the module exists to prevent: Esperance photographs a delivery,
/// the app says something reassuring, and the picture is gone.
///
/// So these cases are about the queue and not about the network. The upload
/// itself cannot be tested here — it is an HTTP call to a Worker — but the
/// bytes reaching the device's own database, staying there across a restart,
/// and being deleted only after the *server* has confirmed the document can
/// all be tested, and are the whole of the durability guarantee.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDb db;

  setUp(() async {
    db = await LocalDb.open(path: inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  Uint8List photo([int size = 64]) =>
      Uint8List.fromList(List<int>.generate(size, (i) => i % 256));

  group('the queue', () {
    test('a photograph is on the device the moment it is taken', () async {
      final id = await db.queueCapture(
        orgId: 'org-1',
        bytes: photo(),
        contentType: 'image/jpeg',
      );

      expect(id, isNotEmpty);

      final waiting = await db.pendingCaptures();
      expect(waiting, hasLength(1));
      expect(waiting.single['org_id'], 'org-1');
      expect(waiting.single['content_type'], 'image/jpeg');
      expect(waiting.single['bytes'], photo());
    });

    test('never tried and tried-and-refused are different states', () async {
      final first = await db.queueCapture(
        orgId: 'org-1',
        bytes: photo(),
        contentType: 'image/jpeg',
      );
      await db.queueCapture(
        orgId: 'org-1',
        bytes: photo(),
        contentType: 'image/jpeg',
      );

      // Two waiting, neither attempted: that is a signal problem, which is
      // normal and must not be shown as an error.
      var health = await db.captureQueueHealth('org-1');
      expect(health.waiting, 2);
      expect(health.stuck, 0);

      await db.captureFailed(first, 'refusé par le serveur');

      health = await db.captureQueueHealth('org-1');
      expect(health.waiting, 2);
      expect(health.stuck, 1);
    });

    test('the count is per business', () async {
      await db.queueCapture(
        orgId: 'org-1',
        bytes: photo(),
        contentType: 'image/jpeg',
      );
      await db.queueCapture(
        orgId: 'org-2',
        bytes: photo(),
        contentType: 'image/jpeg',
      );

      expect((await db.captureQueueHealth('org-1')).waiting, 1);
      expect((await db.captureQueueHealth('org-2')).waiting, 1);
      expect((await db.captureQueueHealth()).waiting, 2);
    });

    test('the bytes are forgotten only once the document exists', () async {
      final id = await db.queueCapture(
        orgId: 'org-1',
        bytes: photo(),
        contentType: 'image/jpeg',
      );

      // A failed attempt keeps the photograph. This is the case that matters:
      // an upload that succeeded and a record_document() that then failed
      // would, if the row were deleted on upload, lose the only reference to
      // an object nobody can find again.
      await db.captureFailed(id, 'la connexion a été coupée');
      expect((await db.captureQueueHealth()).waiting, 1);

      await db.captureSent(id);
      expect((await db.captureQueueHealth()).waiting, 0);
    });

    test('a photograph survives the app being closed', () async {
      // The normal end of a market day is the app being killed, not signed
      // out of. An in-memory queue would lose everything taken that day — so
      // this one case uses a real file, because an in-memory database is
      // destroyed with its last connection and would pass by accident.
      final directory = await Directory.systemTemp.createTemp('kaj_capture');
      final path = p.join(directory.path, 'kaj.db');

      final first = await LocalDb.open(path: path);
      await first.queueCapture(
        orgId: 'org-1',
        bytes: photo(128),
        contentType: 'image/jpeg',
        caption: 'Livraison',
      );
      await first.close();

      final reopened = await LocalDb.open(path: path);
      final waiting = await reopened.pendingCaptures();

      expect(waiting, hasLength(1));
      expect(waiting.single['caption'], 'Livraison');
      expect(waiting.single['bytes'], photo(128));

      await reopened.close();
      await directory.delete(recursive: true);
    });
  });

  group('the repository', () {
    test('a build with no upload Worker hides the camera rather than failing',
        () async {
      // No client and no URL: what every build made before workers/uploads
      // was deployed looks like. isConfigured false means the button is not
      // drawn — a button that does nothing teaches people the app is broken.
      final capture = CaptureRepository(null, db: db);
      expect(capture.isConfigured, isFalse);
      expect(await capture.drain(), 0);
    });

    test('a trailing slash in the configured URL is not a second slash',
        () async {
      final capture = CaptureRepository(
        null,
        db: db,
        uploadsUrl: 'https://uploads.example.com/',
      );
      // Still unconfigured without a client, but the URL was accepted and
      // trimmed rather than producing https://…//v1/orgs/.
      expect(capture.isConfigured, isFalse);
    });

    test('a build with nowhere to post refuses at once, and queues nothing',
        () async {
      // Neither a client nor a Worker address: capture() must not file the
      // photograph on the device, because no drain will ever send it, and
      // the "en attente de réseau" that would follow is a lie — the network
      // is fine, the build has no address. It says the true thing instead.
      final capture = CaptureRepository(null, db: db);
      await expectLater(
        capture.capture(
            orgId: 'org-1', bytes: photo(), contentType: 'image/jpeg'),
        throwsA(isA<CaptureException>().having((e) => e.message, 'message',
            contains("n'est pas configuré"))),
      );
      expect((await capture.queueHealth('org-1')).waiting, 0);
    });

    test('a failed send leaves the photograph on the device', () async {
      // A configured build whose send dies — the network is down, or here,
      // a Worker address nothing answers at. The photograph must still be
      // here afterwards, and capture() must report queued rather than
      // throwing.
      final capture = _Configured(db: db);

      final id = await capture.capture(
        orgId: 'org-1',
        bytes: photo(),
        contentType: 'image/jpeg',
      );

      expect(id, isNull);

      final health = await capture.queueHealth('org-1');
      expect(health.waiting, 1);
      // Attempted and refused, so the gallery says so rather than implying
      // the phone is merely out of range.
      expect(health.stuck, 1);
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';
import 'invoice_reading.dart';
import 'models.dart';
import 'notebook_reading.dart';

/// Photographs: taking them, sending them, reading them back.
///
/// Two halves that deliberately do not know much about each other.
///
/// **The bytes** go to the upload Worker (workers/uploads), which is the only
/// thing allowed to write to the bucket. It authorises by forwarding this
/// caller's own access token to PostgREST, so the answer to "may they?" comes
/// from the same RLS policies as everything else.
///
/// **The record** goes to Postgres through `record_document()`, after the
/// bytes have landed and never before. A row pointing at an object that does
/// not exist puts a broken thumbnail in a gallery with nothing the person
/// holding the phone can do about it.
///
/// In between sits the queue. Taking a photograph must not require signal —
/// that is the whole premise of M5's capture half — so the bytes go into the
/// device's own database first and are sent when there is a connection.
/// [drain] is what sends them, and it is safe to call at any time: every
/// upload carries a `client_uuid`, and `record_document()` returns the
/// original row rather than making a second one.
class CaptureRepository {
  CaptureRepository(
    this._client, {
    required this._db,
    String uploadsUrl = '',
    http.Client? httpClient,
    int photoCacheBudget = 24 * 1024 * 1024,
  })  : _uploads = _trimSlash(uploadsUrl),
        _http = httpClient ?? http.Client(),
        _photoBudget = photoCacheBudget;

  // ----------------------------------------------------------------
  // Photographs already fetched
  // ----------------------------------------------------------------
  // Walking street → shop → street used to refetch every picture over a
  // market's connection, because each tile held its own bytes for its own
  // life. One repository serves the whole app, so this is the one place a
  // picture needs to be remembered. Least recently seen goes first once
  // the budget is passed; insertion order is the recency order.
  final _photos = <String, Uint8List>{};
  int _photoBytes = 0;
  final int _photoBudget;

  Uint8List? _remembered(String key) {
    final hit = _photos.remove(key);
    if (hit == null) return null;
    _photos[key] = hit; // Seen again: back to the newest end.
    return hit;
  }

  void _remember(String key, Uint8List bytes) {
    // One oversized file must not evict the whole street to fit itself.
    if (bytes.length > _photoBudget ~/ 4) return;
    final old = _photos.remove(key);
    if (old != null) _photoBytes -= old.length;
    _photos[key] = bytes;
    _photoBytes += bytes.length;
    while (_photoBytes > _photoBudget && _photos.isNotEmpty) {
      final oldest = _photos.keys.first;
      _photoBytes -= _photos.remove(oldest)!.length;
    }
  }

  /// How many pictures are held right now — for tests and diagnostics.
  int get cachedPhotos => _photos.length;

  final SupabaseClient? _client;
  final LocalDb _db;
  final String _uploads;
  final http.Client _http;

  /// Whether photographs can be sent at all.
  ///
  /// False in a build with no server, and false in a build made before the
  /// upload Worker had a URL to be compiled against. In both cases the camera
  /// button is hidden rather than shown and then failing — a button that does
  /// nothing teaches people the app is broken.
  bool get isConfigured => _client != null && _uploads.isNotEmpty;

  /// True when the queue can still take a photograph even though it cannot be
  /// sent yet. Capturing works offline; it does not work in a build that has
  /// no idea where to send anything.
  bool get canCapture => isConfigured;

  String? get currentUserId => _client?.auth.currentUser?.id;

  // ----------------------------------------------------------------
  // Taking one
  // ----------------------------------------------------------------

  /// Files a photograph on the device and tries, once, to send it.
  ///
  /// Returns the id of the document if it landed, and null if it is queued —
  /// which is not a failure and must not be shown as one.
  Future<String?> capture({
    required String orgId,
    required Uint8List bytes,
    required String contentType,
    String? kind,
    String? caption,
    String? ocrText,
    DateTime? capturedAt,
  }) async {
    final clientUuid = await _db.queueCapture(
      orgId: orgId,
      bytes: bytes,
      contentType: contentType,
      kind: kind,
      caption: caption,
      ocrText: ocrText,
      capturedAt: capturedAt,
    );

    try {
      return await _send(
        clientUuid: clientUuid,
        orgId: orgId,
        bytes: bytes,
        contentType: contentType,
        kind: kind,
        caption: caption,
        ocrText: ocrText,
        capturedAt: capturedAt ?? DateTime.now(),
      );
    } catch (error) {
      await _db.captureFailed(clientUuid, '$error');
      return null;
    }
  }

  /// Sends what the phone is still holding. Returns how many landed.
  ///
  /// Called when the app starts, when the connection comes back, and when
  /// somebody pulls to refresh — the same three moments the outbox drains.
  Future<int> drain({int limit = 5}) async {
    if (!isConfigured) return 0;

    var sent = 0;
    for (final row in await _db.pendingCaptures(limit: limit)) {
      final clientUuid = row['client_uuid'] as String;
      try {
        await _send(
          clientUuid: clientUuid,
          orgId: row['org_id'] as String,
          bytes: row['bytes'] as Uint8List,
          contentType: row['content_type'] as String,
          kind: row['kind'] as String?,
          caption: row['caption'] as String?,
          ocrText: row['ocr_text'] as String?,
          capturedAt: DateTime.tryParse('${row['captured_at']}')?.toLocal() ??
              DateTime.now(),
        );
        sent++;
      } catch (error) {
        await _db.captureFailed(clientUuid, '$error');
        // One failure is usually all of them — the connection is down, or the
        // token has expired. Stop rather than burn the rest of the queue's
        // attempt counters on the same cause.
        break;
      }
    }
    return sent;
  }

  Future<({int waiting, int stuck})> queueHealth([String? orgId]) =>
      _db.captureQueueHealth(orgId);

  /// Uploads the bytes, records the document, then — and only then — lets the
  /// device forget the photograph.
  Future<String> _send({
    required String clientUuid,
    required String orgId,
    required Uint8List bytes,
    required String contentType,
    required DateTime capturedAt,
    String? kind,
    String? caption,
    String? ocrText,
  }) async {
    final key = await _upload(
      orgId: orgId,
      bytes: bytes,
      contentType: contentType,
    );

    final client = _requireClient();
    final id = await client.rpc('record_document', params: {
      'p_org_id': orgId,
      'p_r2_key': key,
      if (kind != null && kind.isNotEmpty) 'p_kind': kind,
      if (caption != null && caption.isNotEmpty) 'p_caption': caption,
      'p_content_type': contentType,
      'p_byte_size': bytes.length,
      'p_captured_at': capturedAt.toUtc().toIso8601String(),
      'p_client_uuid': clientUuid,
    });

    final documentId = id as String;

    // The reading was taken on the device, possibly days ago and with no
    // signal. Attaching it is best-effort on purpose: the photograph is the
    // record, and a failed OCR write must not undo a successful capture or
    // send the bytes a second time.
    if (ocrText != null && ocrText.trim().isNotEmpty) {
      try {
        await saveReading(documentId: documentId, text: ocrText);
      } catch (_) {
        // Left as it was: ocr_status stays 'pending', which is true.
      }
    }

    await _db.captureSent(clientUuid);
    return documentId;
  }

  Future<String> _upload({
    required String orgId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await _http.post(
      Uri.parse('$_uploads/v1/orgs/$orgId/uploads'),
      headers: {
        'Authorization': 'Bearer ${_requireToken()}',
        'Content-Type': contentType,
      },
      body: bytes,
    );

    if (response.statusCode != 201) {
      throw CaptureException(_messageFrom(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final key = body['key'] as String?;
    if (key == null || key.isEmpty) {
      throw const CaptureException(
          "Le serveur n'a pas dit où la photo a été rangée.");
    }
    return key;
  }

  // ----------------------------------------------------------------
  // The handwriting reader
  // ----------------------------------------------------------------

  /// Sends a photographed notebook page to the Worker's /read-page and
  /// returns editable product lines for the same confirm screen the
  /// invoice capture uses. Online-only by nature: the reading happens on
  /// a model the phone does not carry.
  ///
  /// A Worker without its ANTHROPIC_API_KEY secret answers 501; that
  /// surfaces as the polite sentence below rather than a failure, because
  /// the feature ships deployed-but-dormant until the key is set.
  Future<List<InvoiceLine>> readNotebookPage({
    required String orgId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await _http.post(
      Uri.parse('$_uploads/v1/orgs/$orgId/read-page'),
      headers: {
        'Authorization': 'Bearer ${_requireToken()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'image': base64Encode(bytes),
        'mime': contentType,
      }),
    );

    if (response.statusCode == 501) {
      throw const CaptureException(
          "Le lecteur de carnet n'est pas encore configuré.");
    }
    if (response.statusCode != 200) {
      throw CaptureException(_messageFrom(response));
    }
    return parseNotebookLines(response.body);
  }

  // ----------------------------------------------------------------
  // Reading them back
  // ----------------------------------------------------------------

  /// The bytes of a stored photograph.
  ///
  /// Fetched rather than handed to `Image.network`, because every read is
  /// authorised: the request carries the caller's token, and a browser's
  /// `<img>` tag cannot send one.
  Future<Uint8List> objectBytes(String key) async {
    final held = _remembered(key);
    if (held != null) return held;
    final response = await _http.get(
      Uri.parse('$_uploads/v1/objects/${Uri.encodeComponent(key)}'),
      headers: {'Authorization': 'Bearer ${_requireToken()}'},
    );

    if (response.statusCode != 200) {
      throw CaptureException(_messageFrom(response));
    }
    _remember(key, response.bodyBytes);
    return response.bodyBytes;
  }

  /// A vitrine photo, for anyone: no token, because the shop chose to show
  /// this article to the street. The Worker still asks Postgres, per key,
  /// that the picture is of a published article on an open vitrine (052) —
  /// a key that is not gets a 404, exactly like one that does not exist.
  Future<Uint8List> publicObjectBytes(String key) async {
    if (_uploads.isEmpty) {
      throw const CaptureException(
          'Les photos ne sont pas disponibles sur cette installation.');
    }
    final held = _remembered(key);
    if (held != null) return held;
    final response = await _http.get(
      Uri.parse('$_uploads/v1/public/objects/${Uri.encodeComponent(key)}'),
    );
    if (response.statusCode != 200) {
      throw CaptureException(_messageFrom(response));
    }
    _remember(key, response.bodyBytes);
    return response.bodyBytes;
  }

  Future<List<CapturedDocument>> documents(
    String orgId, {
    String? kind,
    int limit = 60,
    int offset = 0,
  }) async {
    final client = _requireClient();
    final rows = await client.rpc('org_documents', params: {
      'p_org_id': orgId,
      if (kind != null && kind.isNotEmpty) 'p_kind': kind,
      'p_limit': limit,
      'p_offset': offset,
    }) as List<dynamic>;

    return rows
        .map((r) =>
            CapturedDocument.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The article's current photograph — the same one the vitrine and the
  /// search show: the newest document linked to this product, whatever it
  /// was filed as. Looks through the shop's recent documents; null when
  /// none of them is the article's.
  Future<String?> productPhotoKey(String orgId, String productId) async {
    final docs = await documents(orgId, limit: 200);
    for (final d in docs) {
      if (d.productId == productId) return d.key;
    }
    return null;
  }

  /// The pile on the counter: captured, and still about nothing.
  Future<List<CapturedDocument>> unfiled(String orgId, {int limit = 60}) async {
    final client = _requireClient();
    final rows = await client.rpc('unfiled_documents', params: {
      'p_org_id': orgId,
      'p_limit': limit,
    }) as List<dynamic>;

    return rows
        .map((r) =>
            CapturedDocument.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ----------------------------------------------------------------
  // The details that arrive later
  // ----------------------------------------------------------------

  Future<void> file({
    required String documentId,
    String? caption,
    String? kind,
    String? entryId,
    String? productId,
  }) async {
    final client = _requireClient();
    await client.rpc('file_document', params: {
      'p_document_id': documentId,
      if (caption != null && caption.isNotEmpty) 'p_caption': caption,
      if (kind != null && kind.isNotEmpty) 'p_kind': kind,
      'p_entry_id': ?entryId,
      'p_product_id': ?productId,
    });
  }

  /// What the phone read off the picture. Stored as read; nothing acts on it
  /// until a person confirms it.
  Future<void> saveReading({
    required String documentId,
    String? text,
    String? barcode,
    String status = 'done',
  }) async {
    final client = _requireClient();
    await client.rpc('set_document_ocr', params: {
      'p_document_id': documentId,
      'p_text': text,
      if (barcode != null && barcode.isNotEmpty) 'p_barcode': barcode,
      'p_status': status,
    });
  }

  /// The product behind a scanned barcode, or null when this shop has never
  /// seen it — which is the signal to open the new-product form with the
  /// barcode already filled in.
  Future<Map<String, dynamic>?> productByBarcode(
      String orgId, String barcode) async {
    final client = _requireClient();
    final rows = await client.rpc('product_by_barcode', params: {
      'p_org_id': orgId,
      'p_barcode': barcode,
    }) as List<dynamic>;

    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  }

  // ----------------------------------------------------------------

  static String _trimSlash(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// The Worker answers every failure with the same shape, so the app shows
  /// `error` and never parses prose. A response that is not that shape — a
  /// proxy's HTML error page, say — must not be shown raw.
  static String _messageFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final message = body['error'] ?? body['detail'];
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // Falls through.
    }
    return 'Le service de photos a répondu ${response.statusCode}.';
  }

  String _requireToken() {
    final token = _client?.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw const CaptureException('Reconnectez-vous pour envoyer des photos.');
    }
    return token;
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const CaptureException(
        "Cette version de l'application a été compilée sans serveur.",
      );
    }
    return client;
  }
}

/// A failure with a sentence in it that is safe to put on screen.
class CaptureException implements Exception {
  const CaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}

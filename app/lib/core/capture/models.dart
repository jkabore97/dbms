/// What a photograph is, once it has been taken.
///
/// Deliberately almost entirely nullable. The whole premise of M5's capture
/// half is that a picture with nothing filled in is a complete record — every
/// required field at capture time loses a user — so a model that demands a
/// caption or a kind would be arguing with the schema.
class CapturedDocument {
  const CapturedDocument({
    required this.id,
    required this.key,
    this.kind,
    this.caption,
    this.contentType,
    this.byteSize,
    this.capturedAt,
    this.ocrStatus = 'pending',
    this.ocrText,
    this.barcode,
    this.productId,
    this.productName,
    this.entryId,
    this.entryLabel,
    this.uploadedName,
  });

  final String id;

  /// Where the bytes are, in the bucket. Passed to the upload Worker to read
  /// them back; never turned into a public URL, because there is no such
  /// thing here — every read is authorised.
  final String key;

  /// 'photo' | 'receipt' | 'invoice' | 'product_photo' — free text, and null
  /// for most rows.
  final String? kind;
  final String? caption;
  final String? contentType;
  final int? byteSize;

  /// When the picture was taken, which on Ignace's phone can be days before
  /// it reached the server.
  final DateTime? capturedAt;

  final String ocrStatus;

  /// What the phone read off the image. Advisory — a person confirms it
  /// before it becomes a product, and nothing reads it automatically.
  final String? ocrText;
  final String? barcode;

  final String? productId;
  final String? productName;
  final String? entryId;
  final String? entryLabel;
  final String? uploadedName;

  bool get isFiled =>
      productId != null || entryId != null || (caption?.isNotEmpty ?? false);

  bool get isPdf => contentType == 'application/pdf';

  /// What to call it in a list when nobody has named it.
  String get title {
    final c = caption;
    if (c != null && c.trim().isNotEmpty) return c.trim();
    final p = productName;
    if (p != null && p.trim().isNotEmpty) return p.trim();
    final e = entryLabel;
    if (e != null && e.trim().isNotEmpty) return e.trim();
    return 'Photo sans nom';
  }

  factory CapturedDocument.fromRow(Map<String, dynamic> row) {
    DateTime? when(Object? v) =>
        v == null ? null : DateTime.tryParse('$v')?.toLocal();

    return CapturedDocument(
      id: row['id'] as String,
      key: row['r2_key'] as String,
      kind: row['kind'] as String?,
      caption: row['caption'] as String?,
      contentType: row['content_type'] as String?,
      byteSize: (row['byte_size'] as num?)?.toInt(),
      capturedAt: when(row['captured_at']),
      ocrStatus: (row['ocr_status'] as String?) ?? 'pending',
      ocrText: row['ocr_text'] as String?,
      barcode: row['barcode'] as String?,
      productId: row['product_id'] as String?,
      productName: row['product_name'] as String?,
      entryId: row['entry_id'] as String?,
      entryLabel: row['entry_label'] as String?,
      uploadedName: row['uploaded_name'] as String?,
    );
  }
}

/// A photograph waiting somewhere in the app to be uploaded.
///
/// The bytes live on the device until they land. This is the retail
/// equivalent of the outbox: a sale can be retried because it is small and
/// idempotent, and so can a photograph — but a photograph is megabytes, so it
/// is queued in its own place rather than as an outbox row.
class PendingCapture {
  const PendingCapture({
    required this.clientUuid,
    required this.orgId,
    required this.bytes,
    required this.contentType,
    required this.capturedAt,
    this.kind,
    this.caption,
    this.lastError,
  });

  final String clientUuid;
  final String orgId;
  final List<int> bytes;
  final String contentType;
  final DateTime capturedAt;
  final String? kind;
  final String? caption;

  /// Why the last attempt failed. Null while it has never been tried, which
  /// is how "waiting for signal" is told apart from "the server refused this"
  /// — the same distinction the device tab makes for the outbox.
  final String? lastError;

  PendingCapture withError(String? error) => PendingCapture(
        clientUuid: clientUuid,
        orgId: orgId,
        bytes: bytes,
        contentType: contentType,
        capturedAt: capturedAt,
        kind: kind,
        caption: caption,
        lastError: error,
      );
}

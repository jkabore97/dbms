import 'package:uuid/uuid.dart';

import '../db/local_db.dart';
import 'visitor_id_store_stub.dart'
    if (dart.library.js_interop) 'visitor_id_store_web.dart';

/// Where the app's device storage keeps the id (084's key, unchanged).
const visitorIdKey = 'street.visitor_id';

/// What record_vitrine_visit (123) takes: 16 to 64 of [A-Za-z0-9-].
final _valid = RegExp(r'^[A-Za-z0-9-]{16,64}$');

/// This device, as one visitor of the street (084, 123): a random id made
/// once and kept on the device — on the web in the browser's localStorage,
/// on Android and iOS in the app's own device storage — never a hardware
/// id, never the person or their account: signed in or not, the same id.
/// An id kept before that does not have the form the server takes is
/// replaced by a new one.
Future<String> deviceVisitorId(LocalDb db) async {
  final browser = readBrowserVisitorId();
  if (browser != null && _valid.hasMatch(browser)) return browser;
  String? id;
  try {
    id = await db.readPref(visitorIdKey);
  } catch (_) {}
  if (id == null || !_valid.hasMatch(id)) {
    id = const Uuid().v4();
    try {
      await db.writePref(visitorIdKey, id);
    } catch (_) {}
  }
  writeBrowserVisitorId(id);
  return id;
}

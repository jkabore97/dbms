/// Android, iOS and the tests: no browser storage — the visitor id lives in
/// the app's own device storage alone (visitor_id.dart).
String? readBrowserVisitorId() => null;

void writeBrowserVisitorId(String id) {}

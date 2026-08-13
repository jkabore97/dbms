/// The web half of the conditional import in `text_reader.dart`.
///
/// ML Kit has no web implementation, so the browser build compiles this file
/// and never sees the plugin. Saying "not available" here is not a
/// degradation: capture works completely without OCR, which is exactly why it
/// could be added last and why every caller treats false as ordinary.
bool get isAvailable => false;

Future<String?> readText(String path) async => null;

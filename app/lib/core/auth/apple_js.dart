/// Apple's « Sign in with Apple JS », loaded on the website only when it is
/// needed (139): at « Supprimer mon compte » for somebody who signed in
/// with Apple, whose token is revoked from a fresh code. Never on page
/// load: nobody else downloads Apple's script.
library;

export 'apple_js_stub.dart' if (dart.library.js_interop) 'apple_js_web.dart';

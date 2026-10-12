/// Which incoming links may sign this device in (SEC_AUDIT_2 M3).
///
/// supabase_flutter watches every link the app is opened with —
/// bf.kaj.app://login-callback on a phone, the page's own address on the
/// web — and by default turns any link carrying `access_token` and
/// `refresh_token` into a session, even in the PKCE flow (gotrue's
/// getSessionFromUrl checks a `code` first, then accepts raw tokens). A
/// link somebody else made — their own account's tokens in it — tapped by
/// a shopkeeper would then quietly sign the phone into the stranger's
/// account: the books typed next, a Pro bought, would be theirs (login
/// CSRF).
///
/// So a link is taken as a sign-in only when it carries a PKCE `code` —
/// which Supabase can exchange only with the code verifier this device
/// kept when it started the sign-in itself (Google, an e-mail
/// confirmation asked from here) — and never when it carries a token. A
/// link with an error and no token is passed on too, so a refused Google
/// sign-in still says why. Everything else — a token link, a link that is
/// only an address in the app — is left alone: no session is made from it.
bool isPkceAuthCallback(Uri uri) {
  try {
    final query = uri.queryParameters;
    final fragment =
        uri.fragment.isEmpty ? const <String, String>{} : Uri.splitQueryString(uri.fragment);
    bool has(String key) => query.containsKey(key) || fragment.containsKey(key);
    const tokens = ['access_token', 'refresh_token', 'provider_token', 'provider_refresh_token'];
    if (tokens.any(has)) return false;
    return query.containsKey('code') ||
        has('error') ||
        has('error_code') ||
        has('error_description');
  } catch (_) {
    // A link that cannot even be read is no sign-in.
    return false;
  }
}

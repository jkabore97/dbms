/// The Supabase project's origin, as the client wants it: no trailing
/// slash and no API path. A value pasted from the dashboard's « API URL »
/// box with `/rest/v1` (or `/auth/v1`) on its end made every call go to
/// `/rest/v1/rest/v1/…` and answer 404 — the iPhone build 3 showed no
/// vitrine and no sign-in buttons that way.
String supabaseOrigin(String raw) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  for (final path in const ['/rest/v1', '/auth/v1']) {
    if (url.endsWith(path)) {
      url = url.substring(0, url.length - path.length);
    }
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

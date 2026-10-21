import 'package:http/http.dart' as http;

/// The website's calls to PostgREST through its own address (web first
/// load).
///
/// From marakaj.com every request to `<project>.supabase.co` is another
/// origin: the browser first sends an OPTIONS « preflight » for nearly each
/// one (they carry `apikey` and `Authorization`), and opens a second
/// connection for them — on a 3G line, a round trip or two before the
/// street or a vitrine shows a single shop. The site's Worker answers
/// `https://marakaj.com/sb/rest/v1/…` by passing the request on to the
/// project (workers/kaj-app/src/supabase_proxy.js), so from the browser it
/// is the same origin: no preflight, the connection already open.
///
/// Only PostgREST (tables and RPCs, `/rest/v1`) is sent that way. Sign-in,
/// token refresh and Google's redirects (`/auth/v1`) stay direct: Supabase
/// limits those per visitor's IP address, and through the Worker every
/// visitor would share one. The realtime websocket stays direct too — a
/// websocket has no preflight. And the session stays under the key it
/// always had (supabase_flutter names it after the project's host), because
/// Supabase is still initialised with the project's own address: only the
/// requests' destination changes, here.
///
/// The web build only, and only when the build is given a proxy
/// (`--dart-define=SUPABASE_WEB_PROXY=/sb`, the deploy's repository
/// variable). Unset — or on Android and iOS, whatever it says — nothing
/// changes: every call goes to the project as before.
String? restProxyBase({
  required String supabaseUrl,
  required String proxy,
  required bool isWeb,
  required Uri pageUrl,
}) {
  if (!isWeb || supabaseUrl.isEmpty) return null;
  var base = proxy.trim();
  if (base.isEmpty) return null;
  if (base.startsWith('/')) {
    // A path on the site itself, whichever of its names the page was
    // opened on (marakaj.com, www.marakaj.com): same origin either way.
    if (!pageUrl.hasScheme || !pageUrl.scheme.startsWith('http')) return null;
    base = '${pageUrl.origin}$base';
  } else {
    final uri = Uri.tryParse(base);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
      return null;
    }
  }
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return base;
}

/// Sends every request for `<supabaseUrl>/rest/v1…` to `<proxy>/rest/v1…`
/// instead, the rest of the address (table, RPC, query) unchanged; any
/// other request — auth, storage, functions, another host — goes out as it
/// came. Given to `Supabase.initialize(httpClient: …)` around the
/// TimeoutClient, so the bound and its abort still apply to the copy.
class SameOriginRestClient extends http.BaseClient {
  SameOriginRestClient(this._inner,
      {required String supabaseUrl, required String proxyBase})
      : _from = '${Uri.parse(supabaseUrl)}/rest/v1',
        _to = '$proxyBase/rest/v1';

  final http.Client _inner;
  final String _from;
  final String _to;

  /// [url] on the proxy, or null when it is not a PostgREST address.
  Uri? rewrite(Uri url) {
    final s = url.toString();
    if (!s.startsWith(_from)) return null;
    final rest = s.substring(_from.length);
    // `/rest/v1` itself, `/rest/v1/…` or `/rest/v1?…` — never
    // `/rest/v10` or a host that only starts the same.
    if (rest.isNotEmpty && !rest.startsWith('/') && !rest.startsWith('?')) {
      return null;
    }
    return Uri.parse('$_to$rest');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final to = rewrite(request.url);
    // Only a plain request (what PostgREST sends) is copied; anything else
    // — a streamed or multipart body — is sent as it is, direct.
    if (to == null || request is! http.Request || request.finalized) {
      return _inner.send(request);
    }
    final trigger =
        request is http.Abortable ? (request as http.Abortable).abortTrigger : null;
    final copy = trigger == null
        ? http.Request(request.method, to)
        : http.AbortableRequest(request.method, to, abortTrigger: trigger);
    copy
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    final bytes = request.bodyBytes;
    if (bytes.isNotEmpty) copy.bodyBytes = bytes;
    return _inner.send(copy);
  }

  @override
  void close() => _inner.close();
}

import 'package:flutter_web_plugins/url_strategy.dart';

/// Drops the `#` from every address.
///
/// Without this the app lives at `/#/o/<id>/factures`, which works but reads
/// as a URL somebody has to apologise for. The clean form is only safe because
/// the Worker serving the bundle is configured with
/// `not_found_handling = "single-page-application"` — see
/// `workers/kaj-app/wrangler.toml`. Without that, reloading any page but the
/// root would 404 against Cloudflare before Flutter ever started.
void useCleanUrls() => usePathUrlStrategy();

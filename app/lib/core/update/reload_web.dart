import 'package:web/web.dart' as web;

/// A full reload, past any cached bundle: what "Recharger" on the update
/// banner does. The Worker serves the new files; the browser only has to
/// ask for them again.
void reloadPage() {
  web.window.location.reload();
}

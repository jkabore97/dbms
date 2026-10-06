/// Where Mara lives on the internet: the address a shop's vitrine link,
/// the Android app's update check and every shared link point to.
///
/// On the web the running origin is used instead wherever that matters (a
/// preview stays a preview); the Android app has no origin of its own, so it
/// is compiled with this. `--dart-define=SITE_URL=…` overrides it for a
/// staging build.
const siteOrigin = String.fromEnvironment('SITE_URL',
    defaultValue: 'https://marakaj.com');

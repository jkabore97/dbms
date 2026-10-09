import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/tr.dart';
import 'app_download_env.dart';
import 'app_download_env_stub.dart'
    if (dart.library.js_interop) 'app_download_env_web.dart';

export 'app_download_env.dart';

/// The APK of the latest release: Android's link until Google Play is live.
const apkDownloadUrl =
    'https://github.com/jkabore97/dbms/releases/latest/download/kaj-arm64-v8a.apk';
const playStoreUrl = 'https://play.google.com/store/apps/details?id=bf.kaj.app';

/// The store links (122's app_store_links): Android's — Google Play once
/// the platform says it is live, the APK before — and the App Store's
/// address, null until the platform sets one.
class AppLinks {
  const AppLinks({required this.android, this.androidStore = false, this.ios});

  /// What a database before 122, or no signal, leaves: the APK, no App Store.
  const AppLinks.fallback()
      : android = apkDownloadUrl,
        androidStore = false,
        ios = null;

  factory AppLinks.fromJson(Map<String, dynamic> j) {
    final android = '${j['android'] ?? ''}'.trim();
    final ios = '${j['ios'] ?? ''}'.trim();
    return AppLinks(
      android: android.startsWith('https://') ? android : apkDownloadUrl,
      androidStore: j['android_store'] == true,
      ios: ios.startsWith('https://') ? ios : null,
    );
  }

  final String android;

  /// Android's link is Google Play's listing, not the APK.
  final bool androidStore;
  final String? ios;

  /// Read by the signed-out street too (granted to anon).
  static Future<AppLinks> fetch(SupabaseClient? client) async {
    if (client == null) return const AppLinks.fallback();
    try {
      final r = await client.rpc('app_store_links');
      if (r is Map) return AppLinks.fromJson(Map<String, dynamic>.from(r));
    } catch (_) {}
    return const AppLinks.fallback();
  }
}

/// How often the pop-up comes back after it was shown.
const appDownloadEvery = Duration(days: 7);

/// The web's « download the app » pop-up, over a street page (the street,
/// a vitrine): a small card at the top, on a phone's browser only — never on
/// a computer, never in the installed web app, never in the Android app —
/// once every seven days. Android: Google Play (or the APK); iPhone: the
/// App Store once it has an address, else how to add Mara to the home
/// screen. It belongs to the page, so an order sheet or the sign-in sheet
/// opened over the page covers it; the sign-in page has none.
class AppDownloadPrompt extends StatefulWidget {
  const AppDownloadPrompt({
    super.key,
    required this.child,
    this.client,
    this.env,
    this.links,
    this.delay = const Duration(seconds: 2),
    this.now,
  });

  final Widget child;
  final SupabaseClient? client;

  /// The browser; [browserEnv] when null (none outside a browser).
  final AppDownloadEnv? env;

  /// The store links; [AppLinks.fetch] when null.
  final Future<AppLinks> Function()? links;

  /// The page is drawn before the pop-up comes.
  final Duration delay;
  final DateTime Function()? now;

  @override
  State<AppDownloadPrompt> createState() => _AppDownloadPromptState();
}

class _AppDownloadPromptState extends State<AppDownloadPrompt> {
  late final AppDownloadEnv _env = widget.env ?? browserEnv();
  AppLinks? _links;
  Timer? _timer;

  DateTime _now() => (widget.now ?? DateTime.now)();

  bool get _due {
    if (_env.phone == null || _env.standalone) return false;
    final last = _env.readShownAt();
    return last == null || _now().difference(last) >= appDownloadEvery;
  }

  @override
  void initState() {
    super.initState();
    if (_due) _timer = Timer(widget.delay, _open);
  }

  Future<void> _open() async {
    final links = await (widget.links ?? () => AppLinks.fetch(widget.client))();
    if (!mounted || !_due) return;
    _env.writeShownAt(_now());
    setState(() => _links = links);
  }

  void _close() => setState(() => _links = null);

  Future<void> _go(String url) async {
    _close();
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final links = _links;
    if (links == null) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _Card(
                    phone: _env.phone!,
                    links: links,
                    onLater: _close,
                    onGo: _go,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.phone,
    required this.links,
    required this.onLater,
    required this.onGo,
  });

  final AppPhone phone;
  final AppLinks links;
  final VoidCallback onLater;
  final void Function(String url) onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ios = phone == AppPhone.ios;
    final homeScreen = ios && links.ios == null;
    final String body;
    final String? action;
    final String? url;
    if (!ios) {
      body = links.androidStore
          ? context.tr('L\'application Mara est plus rapide et vous prévient de vos commandes. Elle est sur Google Play.')
          : context.tr('L\'application Mara est plus rapide et vous prévient de vos commandes. Téléchargez-la pour Android (fichier APK).');
      action = links.androidStore
          ? context.tr('Ouvrir Google Play')
          : context.tr('Télécharger pour Android');
      url = links.android;
    } else if (!homeScreen) {
      body = context.tr('L\'application Mara est plus rapide et vous prévient de vos commandes. Elle est sur l\'App Store.');
      action = context.tr('Ouvrir l\'App Store');
      url = links.ios;
    } else {
      body = context.tr('Ajoutez Mara à l\'écran d\'accueil : dans Safari, touchez Partager, puis « Sur l\'écran d\'accueil ».');
      action = null;
      url = null;
    }
    return Material(
      key: const Key('app-download'),
      color: scheme.surface,
      elevation: 3,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(homeScreen ? Icons.add_to_home_screen : Icons.phone_iphone,
                      color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        homeScreen
                            ? context.tr('Mara sur votre écran d\'accueil')
                            : context.tr('Mara sur votre téléphone'),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('app-download-later'),
                  onPressed: onLater,
                  child: Text(context.tr('Plus tard')),
                ),
                if (action != null && url != null)
                  FilledButton(
                    key: const Key('app-download-go'),
                    onPressed: () => onGo(url!),
                    child: Text(action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

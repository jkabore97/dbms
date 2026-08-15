import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../db/local_db.dart';

/// The languages a person can actually pick.
///
/// French first because it is the language the app was written in and the one
/// every key is guaranteed to have.
const enabledLocales = <Locale>[
  Locale('fr'),
  Locale('en'),
];

/// Scaffolded and deliberately hidden.
///
/// Mooré and Dioula have ARB files (`app_mos.arb`, `app_dyu.arb`) so a human
/// speaker has something to fill in, but machine-drafting the vocabulary of
/// money in languages this project cannot verify would put wrong words on
/// screens where wrong words cost people money. Moving a locale from this
/// list to [enabledLocales] — one line — is what publishes it, once a speaker
/// has reviewed the file. Keys still missing at that point fall back to
/// French, which is the same screen the user has today.
const draftLocales = <Locale>[
  Locale('mos'),
  Locale('dyu'),
];

/// Which language this device shows, and where that choice is kept.
///
/// The choice is **per device, on purpose** — unlike the business colour,
/// which belongs to the org. Language is personal: two people behind the same
/// counter can read different languages, and the phone is the person's. It is
/// also needed *before* sign-in (the sign-in screen is exactly where somebody
/// who cannot read French is most stuck), so it cannot live on the profile or
/// the org; it lives in the device database beside the PIN.
///
/// Null means "follow the phone", which is the default and what everybody has
/// until they touch the setting. A phone set to a language the app does not
/// speak falls back to French.
class LocaleController extends ChangeNotifier {
  LocaleController(this._db);

  final LocalDb _db;

  Locale? _chosen;

  /// The explicit choice, or null for "follow the phone".
  Locale? get chosen => _chosen;

  /// What the app will actually display right now.
  Locale get effective => _chosen ?? platformResolved();

  /// Reads the stored choice. Called once at startup, before `runApp`, so the
  /// first frame is already in the right language — a screen that flashes
  /// French before switching teaches somebody the setting did not work.
  Future<void> load() async {
    final stored = await _db.readPref('locale');
    if (stored != null && stored.isNotEmpty) {
      final locale = Locale(stored);
      if (enabledLocales.contains(locale)) _chosen = locale;
    }
  }

  Future<void> choose(Locale? locale) async {
    _chosen = locale;
    await _db.writePref('locale', locale?.languageCode);
    notifyListeners();
  }

  /// What "follow the phone" resolves to: the first device language the app
  /// speaks, or French. Static because the language screen needs the answer
  /// to describe the default option, with no controller state involved.
  static Locale platformResolved() {
    // Through the binding, not PlatformDispatcher.instance: they are the same
    // object in production, but only the binding's is overridable by tests —
    // and a locale source tests cannot vary is a locale source tests cannot
    // cover.
    for (final device in WidgetsBinding.instance.platformDispatcher.locales) {
      for (final supported in enabledLocales) {
        if (device.languageCode == supported.languageCode) return supported;
      }
    }
    return const Locale('fr');
  }
}

/// Serves Material's own strings (dialog buttons, tooltips, date pickers) in
/// French for locales Material has never heard of.
///
/// Flutter ships Material translations for `fr` and `en` but not for `mos` or
/// `dyu`, and a locale without MaterialLocalizations does not degrade — it
/// throws on the first dialog. This delegate is what makes enabling a draft
/// locale a one-line change instead of a crash: the app's own strings come
/// from the reviewed ARB file, and the framework's chrome stays French.
class MaterialFallbackDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const MaterialFallbackDelegate();

  @override
  bool isSupported(Locale locale) =>
      draftLocales.any((d) => d.languageCode == locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('fr'));

  @override
  bool shouldReload(MaterialFallbackDelegate old) => false;
}

/// The same fallback for the lower-level widget strings.
class WidgetsFallbackDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const WidgetsFallbackDelegate();

  @override
  bool isSupported(Locale locale) =>
      draftLocales.any((d) => d.languageCode == locale.languageCode);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('fr'));

  @override
  bool shouldReload(WidgetsFallbackDelegate old) => false;
}

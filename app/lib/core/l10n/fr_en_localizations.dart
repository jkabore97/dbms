import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_custom.dart';
import 'package:intl/intl.dart' as intl;

import 'fr_en_date_data.dart';

/// Material, Cupertino and widget strings, and the calendar, for the two
/// languages the app speaks — French and English — and no others.
///
/// Flutter's GlobalMaterialLocalizations.delegate (and its Cupertino and
/// widgets siblings) answer for some eighty languages, and with them comes
/// every language's translation table and calendar; intl's
/// `date_symbol_data_local.dart`, which main.dart used to start with, adds
/// every calendar again. On the web all of it is downloaded before the first
/// frame (web first load), for screens only ever shown in French or English.
///
/// These delegates build exactly what Flutter's own do for `fr` and `en` —
/// the same generated classes (MaterialLocalizationFr…), the same intl
/// formats, the same date data (fr_en_date_data.dart, copied from Flutter's)
/// — so nothing on screen changes; the rest is left out of the build.
const frEnLanguages = {'fr', 'en'};

bool _datesReady = false;

/// French and English date formatting in intl, replacing
/// `initializeDateFormatting` (which loads every locale). Safe to call
/// again. `DateFormat(…, 'fr_FR')` resolves to `fr`, and a format with no
/// locale (intl's default, `en_US`) to `en`, as before.
void initializeFrEnDateFormatting() {
  if (_datesReady) return;
  frEnDateSymbols.forEach((locale, symbols) {
    initializeDateFormattingCustom(
      locale: locale,
      symbols: symbols,
      patterns: frEnDatePatterns[locale],
    );
  });
  _datesReady = true;
}

String _language(Locale locale) =>
    locale.languageCode == 'en' ? 'en' : 'fr';

/// [GlobalMaterialLocalizations.delegate], for fr and en only.
class FrEnMaterialLocalizations
    extends LocalizationsDelegate<MaterialLocalizations> {
  const FrEnMaterialLocalizations();

  static final _loaded = <String, MaterialLocalizations>{};

  @override
  bool isSupported(Locale locale) =>
      frEnLanguages.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    initializeFrEnDateFormatting();
    final name = _language(locale);
    return SynchronousFuture(_loaded.putIfAbsent(name, () {
      final fullYear = intl.DateFormat.y(name);
      final compactDate = intl.DateFormat.yMd(name);
      final shortDate = intl.DateFormat.yMMMd(name);
      final mediumDate = intl.DateFormat.MMMEd(name);
      final longDate = intl.DateFormat.yMMMMEEEEd(name);
      final yearMonth = intl.DateFormat.yMMMM(name);
      final shortMonthDay = intl.DateFormat.MMMd(name);
      final decimal = intl.NumberFormat.decimalPattern(name);
      final twoDigits = intl.NumberFormat('00', name);
      return name == 'en'
          ? MaterialLocalizationEn(
              fullYearFormat: fullYear,
              compactDateFormat: compactDate,
              shortDateFormat: shortDate,
              mediumDateFormat: mediumDate,
              longDateFormat: longDate,
              yearMonthFormat: yearMonth,
              shortMonthDayFormat: shortMonthDay,
              decimalFormat: decimal,
              twoDigitZeroPaddedFormat: twoDigits,
            )
          : MaterialLocalizationFr(
              fullYearFormat: fullYear,
              compactDateFormat: compactDate,
              shortDateFormat: shortDate,
              mediumDateFormat: mediumDate,
              longDateFormat: longDate,
              yearMonthFormat: yearMonth,
              shortMonthDayFormat: shortMonthDay,
              decimalFormat: decimal,
              twoDigitZeroPaddedFormat: twoDigits,
            );
    }));
  }

  @override
  bool shouldReload(FrEnMaterialLocalizations old) => false;
}

/// [GlobalCupertinoLocalizations.delegate], for fr and en only.
class FrEnCupertinoLocalizations
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const FrEnCupertinoLocalizations();

  static final _loaded = <String, CupertinoLocalizations>{};

  @override
  bool isSupported(Locale locale) =>
      frEnLanguages.contains(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    initializeFrEnDateFormatting();
    final name = _language(locale);
    return SynchronousFuture(_loaded.putIfAbsent(name, () {
      final fullYear = intl.DateFormat.y(name);
      final day = intl.DateFormat.d(name);
      final weekday = intl.DateFormat.E(name);
      final mediumDate = intl.DateFormat.MMMEd(name);
      final hour = intl.DateFormat('HH', name);
      final minute = intl.DateFormat.m(name);
      final twoDigitMinute = intl.DateFormat('mm', name);
      final second = intl.DateFormat.s(name);
      final decimal = intl.NumberFormat.decimalPattern(name);
      return name == 'en'
          ? CupertinoLocalizationEn(
              fullYearFormat: fullYear,
              dayFormat: day,
              weekdayFormat: weekday,
              mediumDateFormat: mediumDate,
              singleDigitHourFormat: hour,
              singleDigitMinuteFormat: minute,
              doubleDigitMinuteFormat: twoDigitMinute,
              singleDigitSecondFormat: second,
              decimalFormat: decimal,
            )
          : CupertinoLocalizationFr(
              fullYearFormat: fullYear,
              dayFormat: day,
              weekdayFormat: weekday,
              mediumDateFormat: mediumDate,
              singleDigitHourFormat: hour,
              singleDigitMinuteFormat: minute,
              doubleDigitMinuteFormat: twoDigitMinute,
              singleDigitSecondFormat: second,
              decimalFormat: decimal,
            );
    }));
  }

  @override
  bool shouldReload(FrEnCupertinoLocalizations old) => false;
}

/// [GlobalWidgetsLocalizations.delegate], for fr and en only.
class FrEnWidgetsLocalizations
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const FrEnWidgetsLocalizations();

  @override
  bool isSupported(Locale locale) =>
      frEnLanguages.contains(locale.languageCode);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture(_language(locale) == 'en'
          ? const WidgetsLocalizationEn()
          : const WidgetsLocalizationFr());

  @override
  bool shouldReload(FrEnWidgetsLocalizations old) => false;
}

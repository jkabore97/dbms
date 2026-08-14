/// Country dialling codes, for the picker in front of every phone field.
///
/// Until now every phone field in the app was prefixed with a hardcoded
/// `+226`. That is right for almost everybody who will use this — and wrong in
/// the two cases that matter most:
///
///   * the owner whose supplier, accountant or brother-in-law is in Abidjan,
///     Lomé or Paris, and who is invited by number;
///   * anybody using the app from outside Burkina Faso at all.
///
/// A hardcoded prefix does not merely mislabel those numbers, it corrupts
/// them: [normalize] pastes the default code onto anything not starting with
/// `+`, so an Ivorian number typed into a `+226` field becomes a Burkinabè
/// number that belongs to someone else, and the SMS goes to a stranger.
///
/// The list is deliberately not all 240 territories. Every entry here is one I
/// can state with confidence; a wrong dialling code in a list nobody audits is
/// worse than an absent one, because the field still looks answered. West
/// Africa is first because that is where the phone in question usually is, and
/// the rest is ordered by name so the search box does the work.
class CountryCode {
  const CountryCode(this.iso, this.dial, this.name, {this.trunkZero = true});

  /// ISO 3166-1 alpha-2, shown in the field.
  ///
  /// Shown as letters rather than a flag emoji on purpose: Flutter web paints
  /// text to a canvas, and regional-indicator pairs fall back to two boxed
  /// letters in several browsers. "BF" is those same two letters, deliberately.
  final String iso;

  /// E.164 country calling code, with its `+`.
  final String dial;

  /// The country in French, which is what the label is read in.
  final String name;

  /// Whether a leading `0` is a national trunk prefix to be dropped, rather
  /// than a digit of the number itself.
  ///
  /// True nearly everywhere, and the assumption the app made unconditionally
  /// until a round-trip test caught what that costs next door. Côte d'Ivoire
  /// moved to ten-digit numbers in 2021 and its mobiles begin `01`, `05`,
  /// `07` — that zero *is* the number. Dropping it turned `+22507123456`
  /// into `+2257123456`, which is not a shorter way of writing the same
  /// number, it is a different one. Italy keeps the leading zero of a
  /// landline for the same reason.
  ///
  /// Left true for everywhere I am confident a leading zero is a trunk code
  /// (Ghana, Nigeria, France, the UK…) and for the francophone West African
  /// plans where no leading zero is ever typed, so the flag cannot bite.
  final bool trunkZero;

  /// What the server stores, built from what somebody typed under this
  /// country. Spaces, dashes and brackets go; an explicit `+` or `00` is
  /// obeyed rather than overridden, because typing one is how a person says
  /// which country they meant.
  String toE164(String typed) {
    var cleaned = typed.replaceAll(RegExp(r'[\s\-().]'), '');
    if (cleaned.startsWith('00')) cleaned = '+${cleaned.substring(2)}';
    if (cleaned.startsWith('+')) return cleaned;
    if (trunkZero && cleaned.startsWith('0')) cleaned = cleaned.substring(1);
    return '$dial$cleaned';
  }

  /// The inverse, for showing a stored number in a field that already names
  /// the country: `+22507123456` under CI displays as `07123456`.
  String localPart(String e164) =>
      e164.startsWith(dial) ? e164.substring(dial.length) : e164;

  @override
  String toString() => '$iso $dial';
}

/// The eight members of UEMOA plus their neighbours: the numbers actually
/// dialled from a shop in Ouagadougou.
const westAfrica = <CountryCode>[
  CountryCode('BF', '+226', 'Burkina Faso'),
  // Ten digits since 2021, beginning 01/05/07 for mobiles. That zero is a
  // digit, not a trunk prefix — see [CountryCode.trunkZero].
  CountryCode('CI', '+225', "Côte d'Ivoire", trunkZero: false),
  CountryCode('ML', '+223', 'Mali'),
  CountryCode('NE', '+227', 'Niger'),
  CountryCode('SN', '+221', 'Sénégal'),
  CountryCode('TG', '+228', 'Togo'),
  CountryCode('BJ', '+229', 'Bénin'),
  CountryCode('GH', '+233', 'Ghana'),
  CountryCode('NG', '+234', 'Nigéria'),
  CountryCode('GN', '+224', 'Guinée'),
];

/// Everything else, by French name.
const otherCountries = <CountryCode>[
  CountryCode('ZA', '+27', 'Afrique du Sud'),
  CountryCode('DZ', '+213', 'Algérie'),
  CountryCode('DE', '+49', 'Allemagne'),
  CountryCode('AO', '+244', 'Angola'),
  CountryCode('SA', '+966', 'Arabie saoudite'),
  CountryCode('AR', '+54', 'Argentine'),
  CountryCode('AU', '+61', 'Australie'),
  CountryCode('AT', '+43', 'Autriche'),
  CountryCode('BE', '+32', 'Belgique'),
  CountryCode('BR', '+55', 'Brésil'),
  CountryCode('BI', '+257', 'Burundi'),
  CountryCode('CM', '+237', 'Cameroun'),
  CountryCode('CA', '+1', 'Canada'),
  CountryCode('CV', '+238', 'Cap-Vert'),
  CountryCode('CL', '+56', 'Chili'),
  CountryCode('CN', '+86', 'Chine'),
  CountryCode('CY', '+357', 'Chypre'),
  CountryCode('CG', '+242', 'Congo-Brazzaville'),
  CountryCode('CD', '+243', 'Congo-Kinshasa'),
  CountryCode('KR', '+82', 'Corée du Sud'),
  CountryCode('DK', '+45', 'Danemark'),
  CountryCode('EG', '+20', 'Égypte'),
  CountryCode('AE', '+971', 'Émirats arabes unis'),
  CountryCode('ES', '+34', 'Espagne'),
  CountryCode('US', '+1', 'États-Unis'),
  CountryCode('ET', '+251', 'Éthiopie'),
  CountryCode('FI', '+358', 'Finlande'),
  CountryCode('FR', '+33', 'France'),
  CountryCode('GA', '+241', 'Gabon'),
  CountryCode('GM', '+220', 'Gambie'),
  CountryCode('GW', '+245', 'Guinée-Bissau'),
  CountryCode('GQ', '+240', 'Guinée équatoriale'),
  CountryCode('GR', '+30', 'Grèce'),
  CountryCode('IN', '+91', 'Inde'),
  CountryCode('ID', '+62', 'Indonésie'),
  CountryCode('IE', '+353', 'Irlande'),
  CountryCode('IL', '+972', 'Israël'),
  // Landlines keep their leading zero: +39 06 … is Rome.
  CountryCode('IT', '+39', 'Italie', trunkZero: false),
  CountryCode('JP', '+81', 'Japon'),
  CountryCode('JO', '+962', 'Jordanie'),
  CountryCode('KE', '+254', 'Kenya'),
  CountryCode('LB', '+961', 'Liban'),
  CountryCode('LR', '+231', 'Libéria'),
  CountryCode('LY', '+218', 'Libye'),
  CountryCode('LU', '+352', 'Luxembourg'),
  CountryCode('MG', '+261', 'Madagascar'),
  CountryCode('MY', '+60', 'Malaisie'),
  CountryCode('MA', '+212', 'Maroc'),
  CountryCode('MR', '+222', 'Mauritanie'),
  CountryCode('MX', '+52', 'Mexique'),
  CountryCode('MZ', '+258', 'Mozambique'),
  CountryCode('NA', '+264', 'Namibie'),
  CountryCode('NO', '+47', 'Norvège'),
  CountryCode('NL', '+31', 'Pays-Bas'),
  CountryCode('PH', '+63', 'Philippines'),
  CountryCode('PL', '+48', 'Pologne'),
  CountryCode('PT', '+351', 'Portugal'),
  CountryCode('QA', '+974', 'Qatar'),
  CountryCode('CF', '+236', 'République centrafricaine'),
  CountryCode('GB', '+44', 'Royaume-Uni'),
  CountryCode('RU', '+7', 'Russie'),
  CountryCode('RW', '+250', 'Rwanda'),
  CountryCode('SL', '+232', 'Sierra Leone'),
  CountryCode('SG', '+65', 'Singapour'),
  CountryCode('SE', '+46', 'Suède'),
  CountryCode('CH', '+41', 'Suisse'),
  CountryCode('TZ', '+255', 'Tanzanie'),
  CountryCode('TD', '+235', 'Tchad'),
  CountryCode('CZ', '+420', 'Tchéquie'),
  CountryCode('TH', '+66', 'Thaïlande'),
  CountryCode('TN', '+216', 'Tunisie'),
  CountryCode('TR', '+90', 'Turquie'),
  CountryCode('UG', '+256', 'Ouganda'),
  CountryCode('ZM', '+260', 'Zambie'),
  CountryCode('ZW', '+263', 'Zimbabwe'),
];

/// West Africa first, then the rest.
const allCountries = <CountryCode>[...westAfrica, ...otherCountries];

/// The one a field starts on when nothing else is known.
const defaultCountry = CountryCode('BF', '+226', 'Burkina Faso');

/// The entry matching [iso], or Burkina Faso.
///
/// ISO rather than dialling code because `+1` is two countries and would
/// otherwise silently resolve to whichever is listed first.
CountryCode countryByIso(String? iso) {
  if (iso == null) return defaultCountry;
  final wanted = iso.toUpperCase();
  for (final country in allCountries) {
    if (country.iso == wanted) return country;
  }
  return defaultCountry;
}

/// The best guess at which country an already-E.164 number belongs to, for
/// reopening a form on a number somebody saved earlier.
///
/// Longest dialling code wins, so `+225` is not read as `+2`. Ambiguous codes
/// resolve to the first listed, which is why this is only used to preselect a
/// picker the person can correct — never to rewrite the number itself.
CountryCode? countryOfNumber(String e164) {
  if (!e164.startsWith('+')) return null;
  CountryCode? best;
  for (final country in allCountries) {
    if (e164.startsWith(country.dial)) {
      if (best == null || country.dial.length > best.dial.length) {
        best = country;
      }
    }
  }
  return best;
}

/// Matches a country against what has been typed into the search box:
/// name, ISO code, or dialling code with or without its `+`.
bool countryMatches(CountryCode country, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final digits = q.replaceAll('+', '');
  return country.name.toLowerCase().contains(q) ||
      country.iso.toLowerCase().contains(q) ||
      (digits.isNotEmpty && country.dial.substring(1).startsWith(digits));
}

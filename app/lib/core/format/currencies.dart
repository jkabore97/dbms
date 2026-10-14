/// The world's money as this app writes it (144): every ISO 4217 code a
/// business may keep its books in, its name in French and in English, and
/// how many decimals it has — the franc CFA (XOF, XAF), the yen, the won,
/// the Guinean franc none; every other two.
///
/// The dinars of Tunisia, Libya, Kuwait, Bahrain and Jordan and the Omani
/// rial have three in ISO 4217, but every money column of the books is
/// numeric(14,2) / (12,2): a third decimal would be cut on save. Until
/// those columns are widened (a decision of its own), they are written and
/// typed with two — never a third shown or accepted.
///
/// And which money a country uses ([countryCurrency]): a business's
/// currency follows where it is, by default — a São Paulo association
/// starts in reais, a Paris shop in euros, an Ouagadougou farm in francs
/// CFA. The person may still choose another.
///
/// Mara's own prices (Pro, the spots, the platform's delivery tariff) are
/// not here: they are the platform's, set in the command center.
library;

/// One currency: its ISO 4217 [code], its name in French ([fr]) and in
/// English ([en]), and its minor units ([decimals]).
class CurrencyInfo {
  const CurrencyInfo(this.code, this.fr, this.en, [this.decimals = 2]);

  final String code;
  final String fr;
  final String en;
  final int decimals;

  /// Its name in [language] ('en' or anything else, read as French).
  String name(String language) => language == 'en' ? en : fr;
}

/// Every currency the app knows, by code — the ones of every country in
/// the phone list (country_codes.dart) and a few more.
const worldCurrencies = <String, CurrencyInfo>{
  // The franc CFA first: most businesses here are in one of the two.
  'XOF': CurrencyInfo('XOF', 'Franc CFA (UEMOA)', 'CFA franc (WAEMU)', 0),
  'XAF': CurrencyInfo('XAF', 'Franc CFA (CEMAC)', 'CFA franc (CEMAC)', 0),
  'EUR': CurrencyInfo('EUR', 'Euro', 'Euro'),
  'USD': CurrencyInfo('USD', 'Dollar américain', 'US dollar'),
  // Africa.
  'GHS': CurrencyInfo('GHS', 'Cedi ghanéen', 'Ghanaian cedi'),
  'NGN': CurrencyInfo('NGN', 'Naira nigérian', 'Nigerian naira'),
  'GNF': CurrencyInfo('GNF', 'Franc guinéen', 'Guinean franc', 0),
  'MAD': CurrencyInfo('MAD', 'Dirham marocain', 'Moroccan dirham'),
  'DZD': CurrencyInfo('DZD', 'Dinar algérien', 'Algerian dinar'),
  'TND': CurrencyInfo('TND', 'Dinar tunisien', 'Tunisian dinar'),
  'LYD': CurrencyInfo('LYD', 'Dinar libyen', 'Libyan dinar'),
  'EGP': CurrencyInfo('EGP', 'Livre égyptienne', 'Egyptian pound'),
  'MRU': CurrencyInfo('MRU', 'Ouguiya mauritanien', 'Mauritanian ouguiya'),
  'CVE': CurrencyInfo('CVE', 'Escudo cap-verdien', 'Cape Verdean escudo'),
  'GMD': CurrencyInfo('GMD', 'Dalasi gambien', 'Gambian dalasi'),
  'LRD': CurrencyInfo('LRD', 'Dollar libérien', 'Liberian dollar'),
  'SLE': CurrencyInfo('SLE', 'Leone sierra-léonais', 'Sierra Leonean leone'),
  'CDF': CurrencyInfo('CDF', 'Franc congolais', 'Congolese franc'),
  'AOA': CurrencyInfo('AOA', 'Kwanza angolais', 'Angolan kwanza'),
  'BIF': CurrencyInfo('BIF', 'Franc burundais', 'Burundian franc', 0),
  'RWF': CurrencyInfo('RWF', 'Franc rwandais', 'Rwandan franc', 0),
  'UGX': CurrencyInfo('UGX', 'Shilling ougandais', 'Ugandan shilling', 0),
  'KES': CurrencyInfo('KES', 'Shilling kényan', 'Kenyan shilling'),
  'TZS': CurrencyInfo('TZS', 'Shilling tanzanien', 'Tanzanian shilling'),
  'ETB': CurrencyInfo('ETB', 'Birr éthiopien', 'Ethiopian birr'),
  'MGA': CurrencyInfo('MGA', 'Ariary malgache', 'Malagasy ariary'),
  'MZN': CurrencyInfo('MZN', 'Metical mozambicain', 'Mozambican metical'),
  'ZMW': CurrencyInfo('ZMW', 'Kwacha zambien', 'Zambian kwacha'),
  'NAD': CurrencyInfo('NAD', 'Dollar namibien', 'Namibian dollar'),
  'ZAR': CurrencyInfo('ZAR', 'Rand sud-africain', 'South African rand'),
  'BWP': CurrencyInfo('BWP', 'Pula botswanais', 'Botswana pula'),
  'MWK': CurrencyInfo('MWK', 'Kwacha malawite', 'Malawian kwacha'),
  'KMF': CurrencyInfo('KMF', 'Franc comorien', 'Comorian franc', 0),
  'DJF': CurrencyInfo('DJF', 'Franc djiboutien', 'Djiboutian franc', 0),
  'MUR': CurrencyInfo('MUR', 'Roupie mauricienne', 'Mauritian rupee'),
  'SCR': CurrencyInfo('SCR', 'Roupie seychelloise', 'Seychellois rupee'),
  'STN': CurrencyInfo('STN', 'Dobra santoméen', 'São Tomé and Príncipe dobra'),
  'SDG': CurrencyInfo('SDG', 'Livre soudanaise', 'Sudanese pound'),
  // Europe.
  'GBP': CurrencyInfo('GBP', 'Livre sterling', 'Pound sterling'),
  'CHF': CurrencyInfo('CHF', 'Franc suisse', 'Swiss franc'),
  'DKK': CurrencyInfo('DKK', 'Couronne danoise', 'Danish krone'),
  'NOK': CurrencyInfo('NOK', 'Couronne norvégienne', 'Norwegian krone'),
  'SEK': CurrencyInfo('SEK', 'Couronne suédoise', 'Swedish krona'),
  'ISK': CurrencyInfo('ISK', 'Couronne islandaise', 'Icelandic króna', 0),
  'PLN': CurrencyInfo('PLN', 'Złoty polonais', 'Polish złoty'),
  'CZK': CurrencyInfo('CZK', 'Couronne tchèque', 'Czech koruna'),
  'HUF': CurrencyInfo('HUF', 'Forint hongrois', 'Hungarian forint'),
  'RON': CurrencyInfo('RON', 'Leu roumain', 'Romanian leu'),
  'RUB': CurrencyInfo('RUB', 'Rouble russe', 'Russian ruble'),
  'UAH': CurrencyInfo('UAH', 'Hryvnia ukrainienne', 'Ukrainian hryvnia'),
  'TRY': CurrencyInfo('TRY', 'Livre turque', 'Turkish lira'),
  // The Americas.
  'CAD': CurrencyInfo('CAD', 'Dollar canadien', 'Canadian dollar'),
  'MXN': CurrencyInfo('MXN', 'Peso mexicain', 'Mexican peso'),
  'BRL': CurrencyInfo('BRL', 'Réal brésilien', 'Brazilian real'),
  'ARS': CurrencyInfo('ARS', 'Peso argentin', 'Argentine peso'),
  'CLP': CurrencyInfo('CLP', 'Peso chilien', 'Chilean peso', 0),
  'COP': CurrencyInfo('COP', 'Peso colombien', 'Colombian peso'),
  'PEN': CurrencyInfo('PEN', 'Sol péruvien', 'Peruvian sol'),
  'HTG': CurrencyInfo('HTG', 'Gourde haïtienne', 'Haitian gourde'),
  'DOP': CurrencyInfo('DOP', 'Peso dominicain', 'Dominican peso'),
  // The Middle East.
  'AED': CurrencyInfo('AED', 'Dirham des Émirats', 'UAE dirham'),
  'SAR': CurrencyInfo('SAR', 'Riyal saoudien', 'Saudi riyal'),
  'QAR': CurrencyInfo('QAR', 'Riyal qatari', 'Qatari riyal'),
  'KWD': CurrencyInfo('KWD', 'Dinar koweïtien', 'Kuwaiti dinar'),
  'BHD': CurrencyInfo('BHD', 'Dinar bahreïni', 'Bahraini dinar'),
  'OMR': CurrencyInfo('OMR', 'Rial omanais', 'Omani rial'),
  'JOD': CurrencyInfo('JOD', 'Dinar jordanien', 'Jordanian dinar'),
  'LBP': CurrencyInfo('LBP', 'Livre libanaise', 'Lebanese pound'),
  'ILS': CurrencyInfo('ILS', 'Shekel israélien', 'Israeli shekel'),
  // Asia and Oceania.
  'CNY': CurrencyInfo('CNY', 'Yuan chinois', 'Chinese yuan'),
  'JPY': CurrencyInfo('JPY', 'Yen japonais', 'Japanese yen', 0),
  'KRW': CurrencyInfo('KRW', 'Won sud-coréen', 'South Korean won', 0),
  'INR': CurrencyInfo('INR', 'Roupie indienne', 'Indian rupee'),
  'PKR': CurrencyInfo('PKR', 'Roupie pakistanaise', 'Pakistani rupee'),
  'BDT': CurrencyInfo('BDT', 'Taka bangladais', 'Bangladeshi taka'),
  'IDR': CurrencyInfo('IDR', 'Roupie indonésienne', 'Indonesian rupiah'),
  'MYR': CurrencyInfo('MYR', 'Ringgit malaisien', 'Malaysian ringgit'),
  'SGD': CurrencyInfo('SGD', 'Dollar de Singapour', 'Singapore dollar'),
  'THB': CurrencyInfo('THB', 'Baht thaïlandais', 'Thai baht'),
  'PHP': CurrencyInfo('PHP', 'Peso philippin', 'Philippine peso'),
  'VND': CurrencyInfo('VND', 'Dông vietnamien', 'Vietnamese đồng', 0),
  'HKD': CurrencyInfo('HKD', 'Dollar de Hong Kong', 'Hong Kong dollar'),
  'AUD': CurrencyInfo('AUD', 'Dollar australien', 'Australian dollar'),
  'NZD': CurrencyInfo('NZD', 'Dollar néo-zélandais', 'New Zealand dollar'),
};

/// The money of each country (ISO 3166-1 alpha-2), for every country of
/// the phone list and a few more. Before 144 any country the app did not
/// name fell back to XOF — a São Paulo association read « XOF — Franc CFA
/// (UEMOA) ». A country absent here is not guessed: see [currencyOfCountry].
const countryCurrency = <String, String>{
  // UEMOA: the West African franc CFA.
  'BF': 'XOF', 'BJ': 'XOF', 'CI': 'XOF', 'GW': 'XOF', 'ML': 'XOF',
  'NE': 'XOF', 'SN': 'XOF', 'TG': 'XOF',
  // CEMAC: the Central African franc CFA.
  'CM': 'XAF', 'CF': 'XAF', 'CG': 'XAF', 'GA': 'XAF', 'GQ': 'XAF', 'TD': 'XAF',
  // The rest of Africa.
  'GH': 'GHS', 'NG': 'NGN', 'GN': 'GNF', 'MA': 'MAD', 'DZ': 'DZD',
  'TN': 'TND', 'LY': 'LYD', 'EG': 'EGP', 'MR': 'MRU', 'CV': 'CVE',
  'GM': 'GMD', 'LR': 'LRD', 'SL': 'SLE', 'CD': 'CDF', 'AO': 'AOA',
  'BI': 'BIF', 'RW': 'RWF', 'UG': 'UGX', 'KE': 'KES', 'TZ': 'TZS',
  'ET': 'ETB', 'MG': 'MGA', 'MZ': 'MZN', 'ZM': 'ZMW', 'NA': 'NAD',
  'ZA': 'ZAR', 'BW': 'BWP', 'MW': 'MWK', 'KM': 'KMF', 'DJ': 'DJF',
  'MU': 'MUR', 'SC': 'SCR', 'ST': 'STN', 'SD': 'SDG',
  // Zimbabwe's own ZiG exists (ZWG, 2024), but prices there are written
  // in dollars; the person may still choose.
  'ZW': 'USD',
  // The euro area (Bulgaria since 2026, Croatia since 2023) and the
  // countries that use the euro without being in it.
  'AT': 'EUR', 'BE': 'EUR', 'BG': 'EUR', 'CY': 'EUR', 'DE': 'EUR',
  'EE': 'EUR', 'ES': 'EUR', 'FI': 'EUR', 'FR': 'EUR', 'GR': 'EUR',
  'HR': 'EUR', 'IE': 'EUR', 'IT': 'EUR', 'LT': 'EUR', 'LU': 'EUR',
  'LV': 'EUR', 'MT': 'EUR', 'NL': 'EUR', 'PT': 'EUR', 'SI': 'EUR',
  'SK': 'EUR', 'MC': 'EUR', 'SM': 'EUR', 'VA': 'EUR', 'AD': 'EUR',
  'ME': 'EUR', 'XK': 'EUR', 'RE': 'EUR', 'GP': 'EUR', 'MQ': 'EUR',
  'GF': 'EUR', 'YT': 'EUR',
  // The rest of Europe.
  'GB': 'GBP', 'CH': 'CHF', 'LI': 'CHF', 'DK': 'DKK', 'NO': 'NOK',
  'SE': 'SEK', 'IS': 'ISK', 'PL': 'PLN', 'CZ': 'CZK', 'HU': 'HUF',
  'RO': 'RON', 'RU': 'RUB', 'UA': 'UAH', 'TR': 'TRY',
  // The dollar area.
  'US': 'USD', 'PR': 'USD', 'EC': 'USD', 'SV': 'USD', 'PA': 'USD',
  'TL': 'USD',
  // The rest of the Americas.
  'CA': 'CAD', 'MX': 'MXN', 'BR': 'BRL', 'AR': 'ARS', 'CL': 'CLP',
  'CO': 'COP', 'PE': 'PEN', 'HT': 'HTG', 'DO': 'DOP',
  // The Middle East.
  'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'KW': 'KWD', 'BH': 'BHD',
  'OM': 'OMR', 'JO': 'JOD', 'LB': 'LBP', 'IL': 'ILS',
  // Asia and Oceania.
  'CN': 'CNY', 'JP': 'JPY', 'KR': 'KRW', 'IN': 'INR', 'PK': 'PKR',
  'BD': 'BDT', 'ID': 'IDR', 'MY': 'MYR', 'SG': 'SGD', 'TH': 'THB',
  'PH': 'PHP', 'VN': 'VND', 'HK': 'HKD', 'AU': 'AUD', 'NZ': 'NZD',
};

/// The currency of the country [iso]; null when this table does not know
/// that country (never a guess: the franc CFA for Brazil was the bug).
String? currencyOfCountryOrNull(String iso) => countryCurrency[iso.toUpperCase()];

/// How many decimals [code] is written with: ISO 4217's minor units — 0
/// for the franc CFA, the yen, the won…, 2 for the rest (the three-decimal
/// dinars too, see above) and for a code this table does not know.
int currencyDecimals(String code) => worldCurrencies[code.toUpperCase()]?.decimals ?? 2;

/// The name of [code] in [language] ('fr' or 'en'); the code itself for
/// one this table does not know.
String currencyName(String code, String language) =>
    worldCurrencies[code.toUpperCase()]?.name(language) ?? code;

/// The currencies to offer in a picker: [first] (the business's own, or
/// the country's) on top, then the two francs CFA, the euro and the
/// dollar, then every other by code — and [first] even when unknown here.
List<String> currencyChoices(String first) => <String>{
      first.toUpperCase(),
      'XOF', 'XAF', 'EUR', 'USD',
      ...(worldCurrencies.keys.toList()..sort()),
    }.toList();

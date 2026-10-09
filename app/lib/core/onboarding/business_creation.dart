import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/local_db.dart';
import '../phone/country_codes.dart';
import 'application_form.dart';

/// Creating one's business, at once (111): no request, no wait. The person
/// answers a few questions — one per screen — and create_my_business()
/// makes the business, its owner, its starting chart, exactly as Mara's
/// own « Nouvelle entreprise » does. The server checks every answer again;
/// what the app checks is only so a button can say no before anything is
/// sent.

/// What the server says before the first screen (my_business_start).
class BusinessStart {
  const BusinessStart({
    this.locked = false,
    this.phoneRequired = false,
    this.verifiedPhone,
    this.form,
  });

  /// A second business needs Mara Pro on one already owned (099).
  final bool locked;

  /// The platform asks for a number proved on WhatsApp first
  /// (Réglages › create_phone_verified).
  final bool phoneRequired;

  /// The account's proved number (« +226… »), or null.
  final String? verifiedPhone;

  /// The creation page Mara set (107's form): welcome, kinds, questions.
  final ApplicationForm? form;

  factory BusinessStart.fromJson(Map<String, dynamic> j) => BusinessStart(
        locked: j['locked'] == true,
        phoneRequired: j['phone_required'] == true,
        verifiedPhone: j['verified_phone'] as String?,
        form: ApplicationForm.fromJson(j['form']),
      );
}

/// The address as typed (business_address_check): its problem, or taken
/// with a free one to suggest.
class AddressCheck {
  const AddressCheck({required this.slug, this.problem, this.taken = false, this.suggestion});

  final String slug;
  final String? problem;
  final bool taken;
  final String? suggestion;

  bool get free => problem == null && !taken;

  factory AddressCheck.fromJson(Map<String, dynamic> j) => AddressCheck(
        slug: '${j['slug'] ?? ''}',
        problem: j['problem'] as String?,
        taken: j['taken'] == true,
        suggestion: j['suggestion'] as String?,
      );
}

/// The answers as they are given, kept on the device until the business
/// exists (and taken up again where they were left).
class BusinessDraft {
  BusinessDraft({
    this.step = 0,
    this.profile,
    this.name = '',
    this.slug = '',
    this.slugTouched = false,
    this.activity,
    this.about = '',
    this.city = '',
    this.area = '',
    this.phoneIso = 'BF',
    this.phone = '',
    this.currency,
    Map<String, Object?>? answers,
  }) : answers = answers ?? {};

  /// The screen the person was on.
  int step;

  /// 'retail' | 'farm' | 'association'.
  String? profile;
  String name;
  String slug;

  /// The address was changed by hand: the name no longer writes it.
  bool slugTouched;

  /// A shop's or a farm's line of trade, an association's kind (102).
  String? activity;
  String about;
  String city;
  String area;

  /// The phone's country (ISO) and the number as typed under it.
  String phoneIso;
  String phone;

  /// Chosen by hand; null follows the phone's country.
  String? currency;

  /// The creation page's questions, by id.
  final Map<String, Object?> answers;

  bool get isEmpty => profile == null && name.trim().isEmpty;

  Map<String, Object?> toJson() => {
        'step': step,
        'profile': profile,
        'name': name,
        'slug': slug,
        'slug_touched': slugTouched,
        'activity': activity,
        'about': about,
        'city': city,
        'area': area,
        'phone_iso': phoneIso,
        'phone': phone,
        'currency': currency,
        'answers': answers,
      };

  factory BusinessDraft.fromJson(Map<String, dynamic> j) => BusinessDraft(
        step: (j['step'] as num?)?.toInt() ?? 0,
        profile: j['profile'] as String?,
        name: '${j['name'] ?? ''}',
        slug: '${j['slug'] ?? ''}',
        slugTouched: j['slug_touched'] == true,
        activity: j['activity'] as String?,
        about: '${j['about'] ?? ''}',
        city: '${j['city'] ?? ''}',
        area: '${j['area'] ?? ''}',
        phoneIso: '${j['phone_iso'] ?? 'BF'}',
        phone: '${j['phone'] ?? ''}',
        currency: j['currency'] as String?,
        answers: j['answers'] is Map
            ? Map<String, Object?>.from(j['answers'] as Map)
            : null,
      );
}

/// Where the answers wait on the device, one draft per account.
abstract class DraftStore {
  Future<BusinessDraft?> read();
  Future<void> write(BusinessDraft? draft);
}

class LocalDraftStore implements DraftStore {
  LocalDraftStore(this._db, String? userId) : _key = 'create_business_draft:${userId ?? ''}';

  final LocalDb _db;
  final String _key;

  @override
  Future<BusinessDraft?> read() async {
    try {
      final raw = await _db.readPref(_key);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      return j is Map ? BusinessDraft.fromJson(Map<String, dynamic>.from(j)) : null;
    } catch (_) {
      // A draft the device cannot read is no draft: the questions start again.
      return null;
    }
  }

  @override
  Future<void> write(BusinessDraft? draft) async {
    try {
      await _db.writePref(_key, draft == null ? null : jsonEncode(draft.toJson()));
    } catch (_) {
      // Keeping the answers is a comfort; failing to must never stop them.
    }
  }
}

/// The server's side, apart so a test can stand in for it.
abstract class BusinessCreation {
  Future<BusinessStart> start();
  Future<AddressCheck> checkAddress(String slug);

  /// Creates the business; returns its id. [phone] is E.164.
  Future<String> create({
    required String profile,
    required String name,
    required String slug,
    required String activity,
    required String about,
    required String city,
    required String area,
    required String phone,
    required String currency,
    Map<String, Object?>? answers,
  });
}

class SupabaseBusinessCreation implements BusinessCreation {
  SupabaseBusinessCreation(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _c {
    final client = _client;
    if (client == null) {
      throw StateError('Pas de serveur : cette version a été construite sans Supabase.');
    }
    return client;
  }

  @override
  Future<BusinessStart> start() async {
    final v = await _c.rpc('my_business_start');
    return BusinessStart.fromJson(v is Map ? Map<String, dynamic>.from(v) : const {});
  }

  @override
  Future<AddressCheck> checkAddress(String slug) async {
    final v = await _c.rpc('business_address_check', params: {'p_slug': slug});
    return AddressCheck.fromJson(v is Map ? Map<String, dynamic>.from(v) : {'slug': slug});
  }

  @override
  Future<String> create({
    required String profile,
    required String name,
    required String slug,
    required String activity,
    required String about,
    required String city,
    required String area,
    required String phone,
    required String currency,
    Map<String, Object?>? answers,
  }) async {
    final id = await _c.rpc('create_my_business', params: {
      'p_profile': profile,
      'p_name': name,
      'p_slug': slug,
      'p_activity': activity,
      'p_about': about,
      'p_city': city,
      'p_area': area,
      'p_phone': phone,
      'p_currency': currency,
      'p_answers': answers == null || answers.isEmpty ? null : answers,
    });
    return id as String;
  }
}

/// The currency a business starts with, from its phone's country: the CFA
/// franc of UEMOA (XOF) and of CEMAC (XAF), else the country's own when
/// the app knows it, else XOF — the person may change it.
String currencyOfCountry(String iso) => switch (iso.toUpperCase()) {
      'BF' || 'ML' || 'NE' || 'CI' || 'SN' || 'TG' || 'BJ' || 'GW' => 'XOF',
      'CM' || 'GA' || 'TD' || 'CF' || 'CG' || 'GQ' => 'XAF',
      'GH' => 'GHS',
      'NG' => 'NGN',
      'GN' => 'GNF',
      'MA' => 'MAD',
      'GB' => 'GBP',
      'US' => 'USD',
      'CA' => 'CAD',
      'CN' => 'CNY',
      'FR' || 'BE' || 'DE' || 'ES' || 'IT' || 'PT' || 'NL' || 'LU' || 'AT' || 'IE' ||
      'FI' || 'GR' || 'CY' => 'EUR',
      _ => 'XOF',
    };

/// The towns offered as one tap wherever a city is asked (the « où »
/// screen of a new business, the shopper's « Ma ville »): the person's own
/// country first — for Burkina, 086's league_towns in order of size — then
/// the big cities of their part of the world, then a few of every other
/// (122: « more international, not just Africa »). Any other is typed.
///
/// [iso] is the person's country (their phone number's, see [townCountry]).
/// Six of their own towns, three of their region, two of every other —
/// about seventeen chips. Names are in French, the language a town is
/// stored in whatever the screen's language (a league counts by name).
List<String> suggestedTowns(String? iso) {
  final country = (iso ?? 'BF').toUpperCase();
  final region = _regionOf(country);
  final out = <String>[...?_townsByCountry[country]?.take(6)];
  void add(Iterable<String> towns) {
    for (final t in towns) {
      if (!out.contains(t)) out.add(t);
    }
  }

  add(_hubs[region]!.take(out.isEmpty ? 6 : 3));
  for (final other in _regionOrder) {
    if (other == region) continue;
    // West Africa's own neighbours already lead; the rest of the continent
    // is not needed twice.
    if (region == _Region.westAfrica && other == _Region.africa) continue;
    add(_hubs[other]!.take(2));
  }
  return out;
}

/// The country to suggest towns for: the person's phone number's, else the
/// phone's own region setting, else Burkina.
String townCountry(String? e164, {String? deviceRegion}) {
  final byNumber = e164 == null ? null : countryOfNumber(e164);
  if (byNumber != null) return byNumber.iso;
  final region = deviceRegion ??
      WidgetsBinding.instance.platformDispatcher.locale.countryCode;
  return (region == null || region.isEmpty) ? defaultCountry.iso : region.toUpperCase();
}

const _townsByCountry = <String, List<String>>{
  'BF': ['Ouagadougou', 'Bobo-Dioulasso', 'Koudougou', 'Ouahigouya', 'Banfora',
      'Kaya', 'Tenkodogo', 'Fada N\'Gourma', 'Dédougou'],
  'CI': ['Abidjan', 'Bouaké', 'Yamoussoukro', 'Daloa', 'San-Pédro', 'Korhogo'],
  'SN': ['Dakar', 'Thiès', 'Saint-Louis', 'Touba', 'Kaolack', 'Ziguinchor'],
  'ML': ['Bamako', 'Sikasso', 'Ségou', 'Mopti', 'Kayes'],
  'NE': ['Niamey', 'Zinder', 'Maradi', 'Tahoua'],
  'TG': ['Lomé', 'Sokodé', 'Kara', 'Kpalimé'],
  'BJ': ['Cotonou', 'Porto-Novo', 'Parakou', 'Abomey-Calavi'],
  'GH': ['Accra', 'Kumasi', 'Tamale', 'Takoradi'],
  'NG': ['Lagos', 'Abuja', 'Kano', 'Ibadan', 'Port Harcourt'],
  'GN': ['Conakry', 'Kankan', 'Labé', 'Nzérékoré'],
  'CM': ['Douala', 'Yaoundé', 'Bafoussam', 'Garoua'],
  'GA': ['Libreville', 'Port-Gentil', 'Franceville'],
  'MA': ['Casablanca', 'Rabat', 'Marrakech', 'Tanger', 'Fès'],
  'FR': ['Paris', 'Lyon', 'Marseille', 'Toulouse', 'Lille', 'Bordeaux'],
  'BE': ['Bruxelles', 'Liège', 'Anvers', 'Charleroi'],
  'DE': ['Berlin', 'Hambourg', 'Munich', 'Francfort'],
  'ES': ['Madrid', 'Barcelone', 'Valence', 'Séville'],
  'IT': ['Rome', 'Milan', 'Naples', 'Turin'],
  'GB': ['London', 'Manchester', 'Birmingham'],
  'US': ['New York', 'Washington', 'Atlanta', 'Houston', 'Los Angeles', 'Chicago'],
  'CA': ['Montréal', 'Toronto', 'Ottawa', 'Québec', 'Vancouver'],
  'BR': ['São Paulo', 'Rio de Janeiro', 'Brasília'],
  'CN': ['Shanghai', 'Pékin', 'Canton', 'Shenzhen'],
  'IN': ['Mumbai', 'Delhi', 'Bangalore'],
  'JP': ['Tokyo', 'Osaka', 'Kyoto'],
  'AE': ['Dubai', 'Abu Dhabi', 'Sharjah'],
  'TR': ['Istanbul', 'Ankara', 'Izmir'],
};

enum _Region { westAfrica, africa, europe, americas, asia, middleEast }

const _regionOrder = [
  _Region.westAfrica,
  _Region.europe,
  _Region.americas,
  _Region.middleEast,
  _Region.asia,
  _Region.africa,
];

/// The big cities of each part of the world, best known first.
const _hubs = <_Region, List<String>>{
  _Region.westAfrica: ['Abidjan', 'Dakar', 'Bamako', 'Lomé', 'Cotonou', 'Accra', 'Lagos'],
  _Region.africa: ['Douala', 'Kinshasa', 'Casablanca', 'Nairobi', 'Johannesburg', 'Le Caire'],
  _Region.europe: ['Paris', 'Bruxelles', 'London', 'Berlin', 'Madrid', 'Rome'],
  _Region.americas: ['Montréal', 'New York', 'Toronto', 'São Paulo', 'Mexico'],
  _Region.middleEast: ['Dubai', 'Istanbul', 'Doha', 'Riyad'],
  _Region.asia: ['Tokyo', 'Shanghai', 'Mumbai', 'Singapour', 'Séoul'],
};

_Region _regionOf(String iso) {
  if (westAfrica.any((c) => c.iso == iso) ||
      const {'LR', 'SL', 'GM', 'GW', 'MR', 'CV'}.contains(iso)) {
    return _Region.westAfrica;
  }
  if (const {'FR', 'BE', 'DE', 'ES', 'IT', 'PT', 'NL', 'LU', 'AT', 'IE', 'FI', 'GR',
    'CY', 'GB', 'CH', 'DK', 'SE', 'NO', 'PL'}.contains(iso)) {
    return _Region.europe;
  }
  if (const {'US', 'CA', 'BR', 'MX', 'AR', 'CL', 'CO', 'HT', 'PE'}.contains(iso)) {
    return _Region.americas;
  }
  if (const {'AE', 'SA', 'QA', 'TR', 'LB', 'JO', 'IL', 'KW', 'OM', 'BH'}.contains(iso)) {
    return _Region.middleEast;
  }
  if (const {'CN', 'JP', 'KR', 'IN', 'ID', 'MY', 'SG', 'TH', 'VN', 'PH', 'AU'}.contains(iso)) {
    return _Region.asia;
  }
  return _Region.africa;
}
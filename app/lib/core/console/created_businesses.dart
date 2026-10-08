import '../onboarding/application_form.dart';

/// « Activités créées » (111's platform_created_businesses): the
/// businesses people created themselves, and the requests of before —
/// approved by Mara, or refused with the reason — newest first.
class CreatedBusinesses {
  const CreatedBusinesses({this.items = const [], this.oldRequests = 0});

  factory CreatedBusinesses.fromJson(Map<String, dynamic> j) => CreatedBusinesses(
        items: [
          for (final r in (j['items'] is List ? j['items'] as List : const []))
            if (r is Map) CreatedBusiness.fromJson(Map<String, dynamic>.from(r)),
        ],
        oldRequests: (j['old_requests'] as num?)?.toInt() ?? 0,
      );

  final List<CreatedBusiness> items;

  /// Requests an older app sent, still waiting: nothing approves them now —
  /// the person creates their business themselves.
  final int oldRequests;
}

class CreatedBusiness {
  const CreatedBusiness({
    required this.how,
    required this.name,
    this.orgId,
    this.slug,
    this.profile = 'retail',
    this.archived = false,
    this.activity,
    this.about,
    this.city,
    this.area,
    this.phone,
    this.person,
    this.personPhone,
    this.personEmail,
    this.note,
    this.answers = const [],
    this.at,
  });

  factory CreatedBusiness.fromJson(Map<String, dynamic> j) {
    String? text(Object? v) {
      final t = '${v ?? ''}'.trim();
      return t.isEmpty ? null : t;
    }

    return CreatedBusiness(
      how: text(j['how']) ?? 'created',
      name: text(j['name']) ?? '',
      orgId: text(j['org_id']),
      slug: text(j['slug']),
      profile: text(j['profile']) ?? 'retail',
      archived: j['archived'] == true,
      activity: text(j['activity']),
      about: text(j['about']),
      city: text(j['city']),
      area: text(j['area']),
      phone: text(j['phone']),
      person: text(j['person']),
      personPhone: text(j['person_phone']),
      personEmail: text(j['person_email']),
      note: text(j['note']),
      answers: [
        for (final a in (j['answers'] is List ? j['answers'] as List : const []))
          if (a is Map) ApplicationAnswer.fromJson(Map<String, dynamic>.from(a)),
      ],
      at: j['at'] == null ? null : DateTime.tryParse('${j['at']}')?.toLocal(),
    );
  }

  /// 'created' (by the person, 111), 'approved' or 'rejected' (a request
  /// of before, decided by Mara).
  final String how;
  final String name;
  final String? orgId;
  final String? slug;
  final String profile;
  final bool archived;

  /// The line of trade, or an association's kind (111's chips).
  final String? activity;
  final String? about;
  final String? city;
  final String? area;
  final String? phone;
  final String? person;
  final String? personPhone;
  final String? personEmail;

  /// Why a request was refused.
  final String? note;
  final List<ApplicationAnswer> answers;
  final DateTime? at;
}

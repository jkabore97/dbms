/// A public event on the street (162): what street_events and street_event
/// say of it.
class StreetEvent {
  const StreetEvent({
    required this.slug,
    required this.title,
    required this.kind,
    required this.startsAt,
    this.dateFr,
    this.place,
    this.orgName,
    this.poster,
    this.posterStock,
    this.posterFete,
    this.card,
    this.tickets = false,
    this.fromPrice,
    this.currency = 'XOF',
    this.payWhatsapp,
    this.types = const [],
    this.salesOpen = false,
    this.sponsored = false,
  });

  factory StreetEvent.fromJson(Map<String, dynamic> j) {
    final offer = j['offer'] is Map ? Map<String, dynamic>.from(j['offer'] as Map) : null;
    return StreetEvent(
      slug: '${j['slug'] ?? ''}',
      title: '${j['title'] ?? ''}',
      kind: '${j['kind'] ?? ''}',
      startsAt: DateTime.tryParse('${j['starts_at']}')?.toLocal() ?? DateTime.now(),
      dateFr: j['date_fr'] as String?,
      place: j['place'] as String?,
      orgName: j['org_name'] as String?,
      poster: j['poster'] as String?,
      posterStock: j['poster_stock'] as String?,
      posterFete: j['poster_fete'] as String?,
      card: j['card'] as String?,
      tickets: j['tickets'] == true,
      fromPrice: (j['from_price'] as num?)?.toDouble(),
      currency: '${j['currency'] ?? 'XOF'}',
      payWhatsapp: j['pay_whatsapp'] as String?,
      salesOpen: offer?['open'] == true,
      sponsored: j['sponsored'] == true,
      types: [
        for (final t in (offer?['types'] as List? ?? const []))
          (
            name: '${(t as Map)['name'] ?? ''}',
            price: (t['price'] as num?)?.toDouble() ?? 0,
            left: (t['left'] as num?)?.toInt(),
          ),
      ],
    );
  }

  final String slug;
  final String title;
  final String kind;
  final DateTime startsAt;
  final String? dateFr;
  final String? place;
  final String? orgName;

  /// The card's main picture (its uploads key), the event's poster: the
  /// cover's photo wherever the card keeps it (174).
  final String? poster;

  /// A photo of the card bank when that is all the card has (174).
  final String? posterStock;

  /// A picture of Marakaj's gallery the organiser chose (175): its name in
  /// [streetGallery].
  final String? posterFete;

  /// The card's design (its template key).
  final String? card;

  /// It sells tickets (Marakaj Pro), from [fromPrice].
  final bool tickets;
  final double? fromPrice;
  final String currency;

  /// One event's page only: the organiser's WhatsApp, the ticket types with
  /// their places left (null: no limit), and whether the sale is open.
  final String? payWhatsapp;
  final List<({String name, double price, int? left})> types;
  final bool salesOpen;

  /// Its business pays a spot (165): first in the strip, said so.
  final bool sponsored;

  String get cardPath => '/e/$slug';
  String get ticketsPath => '/e/$slug/billets';
}

/// How far off an event is, said short: « En cours », « Aujourd'hui »,
/// « Demain », « Dans 3 j ». The French phrase, for context.tr().
({String phrase, int? n}) eventCountdown(DateTime startsAt, DateTime now) {
  if (!startsAt.isAfter(now)) return (phrase: 'En cours', n: null);
  final day = DateTime(now.year, now.month, now.day);
  final then = DateTime(startsAt.year, startsAt.month, startsAt.day);
  final days = then.difference(day).inDays;
  if (days <= 0) return (phrase: 'Aujourd’hui', n: null);
  if (days == 1) return (phrase: 'Demain', n: null);
  return (phrase: 'Dans {n} j', n: days);
}

/// Marakaj's gallery of event pictures (174, 175): `/cartes/fetes/<name>.jpg`,
/// photographs made for Marakaj, no text and no face. A card without a photo
/// shows its kind's; the organiser may choose any of them for the street.
const streetGallery = [
  'mariage', 'dot', 'anniversaire', 'bapteme', 'naissance', 'diplome', 'gala',
  'inauguration', 'concert', 'culture', 'conference', 'hommage', 'autre',
];

/// The gallery picture of a kind: the kinds' own, « anniv » the birthday's,
/// any other (« retraite », a kind added later) the festive gathering.
String streetPictureOfKind(String kind) =>
    kind == 'anniv' ? 'anniversaire' : (streetGallery.contains(kind) ? kind : 'autre');

/// A gallery name the app will ask for: letters, digits and dashes.
bool streetGalleryName(String? name) => name != null && RegExp(r'^[a-z0-9-]{1,40}$').hasMatch(name);

import '../format/currencies.dart';
import '../l10n/tr.dart';

/// A group of animals the farm's « Vente » can sell (150's
/// farm_animals_for_sale): a batch of birds (a flock, 009) or any other
/// group (a herd, 019), how many are alive, and the « À vendre » article
/// that follows it, when there is one.
///
/// Selling it is one operation on the server (sell_animals): the sale is
/// recorded once and the group's count goes down in the same transaction —
/// so the farmer never records the sale and « Vendus vivants » separately.
class AnimalForSale {
  const AnimalForSale({
    required this.kind,
    required this.groupId,
    required this.label,
    required this.alive,
    this.detail,
    this.productId,
    this.productName,
    this.salePrice = 0,
    this.unit,
  });

  /// 'flock' | 'herd'.
  final String kind;
  final String groupId;

  /// The batch code (« B-2026-07 ») or the herd's name.
  final String label;

  /// The breed of a batch, the species of a herd (as stored).
  final String? detail;

  /// As the server last said: for a flock, arrived less dead and sold; for
  /// a herd, its head count. 0 once closed (closed groups are not listed).
  final int alive;

  /// The article that follows this group (null: none yet — the first sale
  /// makes it).
  final String? productId;
  final String? productName;
  final double salePrice;
  final String? unit;

  bool get isFlock => kind == 'flock';

  /// Its key in the till's « waiting on this phone » counts (LocalDb).
  String get waitingKey => '$kind:$groupId';

  /// What the receipt and the sale line say: the article's name, or the
  /// name the server gives the article it makes (« Poulets de chair —
  /// B-2026-07 », a herd by its own name).
  String get lineName =>
      productName ??
      (isFlock && (detail?.trim().isNotEmpty ?? false) ? '${detail!.trim()} — $label' : label);

  factory AnimalForSale.fromRow(Map<String, dynamic> row) {
    double number(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return AnimalForSale(
      kind: '${row['kind']}',
      groupId: '${row['group_id']}',
      label: (row['label'] as String?) ?? '',
      detail: row['detail'] as String?,
      alive: number(row['alive']).round(),
      productId: row['product_id'] as String?,
      productName: row['product_name'] as String?,
      salePrice: number(row['sale_price']),
      unit: row['unit'] as String?,
    );
  }

  Map<String, Object?> toRow() => {
        'kind': kind,
        'group_id': groupId,
        'label': label,
        'detail': detail,
        'alive': alive,
        'product_id': productId,
        'product_name': productName,
        'sale_price': salePrice,
        'unit': unit,
      };
}

/// What « Vente » may sell of the farm's animals: null while the server has
/// not had 150 (the till then sells articles only, exactly as before).
/// [fromDevice]: the list this phone last read (no answer from the server).
class AnimalShelf {
  const AnimalShelf(this.animals, {this.fromDevice = false});
  final List<AnimalForSale> animals;
  final bool fromDevice;
}

/// A total typed for [quantity] heads, as sale lines that add up to it
/// exactly in the money's smallest unit: 100 000 F for 3 is 2 × 33 333 and
/// 1 × 33 334, never 99 999 (record_sale multiplies quantity by price).
/// One line when it divides; the quantity must be whole for a split.
List<({double quantity, double unitPrice})> splitTotal(
    double quantity, double total, String currency) {
  if (quantity <= 0) return const [];
  final scale = _pow10(currencyDecimals(currency));
  final cents = (total * scale).round();
  final whole = quantity == quantity.roundToDouble() && quantity >= 1;
  if (!whole) {
    return [(quantity: quantity, unitPrice: cents / scale / quantity)];
  }
  final n = quantity.round();
  final each = cents ~/ n;
  final rest = cents - each * n;
  if (rest == 0) return [(quantity: quantity, unitPrice: each / scale)];
  return [
    (quantity: (n - 1).toDouble(), unitPrice: each / scale),
    (quantity: 1, unitPrice: (each + rest) / scale),
  ];
}

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

/// 150's sentences that carry a name, said in [language]; null for any
/// other. (The ones without a name are translated as they are.)
String? animalsText(String language, String message) {
  final closed = RegExp(r'^« (.+) » est clôturé : ces animaux ne se vendent plus$')
      .firstMatch(message);
  if (closed != null) {
    return translate(language, '« {name} » est clôturé : ces animaux ne se vendent plus',
        {'name': closed.group(1)});
  }
  final taken = RegExp(r"^« (.+) » est déjà suivi par l'article « (.+) »$")
      .firstMatch(message);
  if (taken != null) {
    return translate(language, '« {group} » est déjà suivi par l\'article « {name} »',
        {'group': taken.group(1), 'name': taken.group(2)});
  }
  final delivery = RegExp(
          r"^« (.+) » suit des animaux : ils s'ajoutent depuis « Ajouter des animaux », pas comme une livraison$")
      .firstMatch(message);
  if (delivery != null) {
    return translate(language,
        '« {name} » suit des animaux : ils s\'ajoutent depuis « Ajouter des animaux », pas comme une livraison',
        {'name': delivery.group(1)});
  }
  final tracked = RegExp(r'^« (.+) » suit des animaux : son stock est toujours suivi$')
      .firstMatch(message);
  if (tracked != null) {
    return translate(language, '« {name} » suit des animaux : son stock est toujours suivi',
        {'name': tracked.group(1)});
  }
  return null;
}

// What the farm functions in 009_farm_profile.sql hand back.
//
// Unlike the accounting models, nothing here goes through a translation table.
// The farm's chart is seeded in French by `seed_farm_accounts()`, and every
// item, flock and customer name in the system was typed by somebody on the
// farm. Their words, back verbatim.

/// One consumable, and how much of it is left.
class StockItem {
  const StockItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.onHand,
    required this.belowReorder,
    this.reorderLevel,
    this.lastMovement,
  });

  final String id;
  final String name;

  /// sac | kg | litre | dose | unité — typed, not chosen from a list, for the
  /// same reason category names are.
  final String unit;

  /// Received minus consumed minus wasted, plus signed adjustments. Computed
  /// from the movements rather than stored, because a stored total is a number
  /// that can drift from the events that produced it with nothing to say so.
  final double onHand;

  final double? reorderLevel;

  /// The whole point of counting sacks: knowing on Monday that the feed runs
  /// out on Thursday, rather than finding out on Thursday.
  final bool belowReorder;

  final DateTime? lastMovement;

  /// 20 rather than 20.0, 2.5 rather than 2.500.
  String get quantityLabel => _trimNumber(onHand);

  Map<String, Object?> toCache() => {
        'item_id': id,
        'name': name,
        'unit': unit,
        'on_hand': onHand,
        'reorder_level': reorderLevel,
        'below_reorder': belowReorder,
      };

  factory StockItem.fromRow(Map<String, dynamic> row) {
    final last = row['last_movement'] as String?;
    return StockItem(
      id: row['item_id'] as String,
      name: row['name'] as String,
      unit: (row['unit'] as String?) ?? 'sac',
      onHand: _num(row['on_hand']),
      reorderLevel: row['reorder_level'] == null
          ? null
          : _num(row['reorder_level']),
      belowReorder: row['below_reorder'] as bool? ?? false,
      lastMovement: last == null ? null : DateTime.parse(last).toLocal(),
    );
  }
}

/// One batch of birds, and how it is doing.
class Flock {
  const Flock({
    required this.id,
    required this.batchCode,
    required this.arrivedOn,
    required this.ageDays,
    required this.started,
    required this.alive,
    required this.died,
    required this.sold,
    required this.eggs7d,
    required this.layRate,
    this.breed,
    this.closedOn,
  });

  final String id;
  final String batchCode;
  final String? breed;
  final DateTime arrivedOn;
  final int ageDays;

  /// How many arrived. Never edited — `alive` is this minus the mortality and
  /// sale events, so the rate birds are being lost at stays visible instead of
  /// being overwritten by a running total.
  final int started;

  final int alive;
  final int died;
  final int sold;
  final int eggs7d;

  /// Eggs in the last seven days over (birds alive × 7). The number that says
  /// something is wrong days before the money does, which is the entire
  /// argument for making somebody count eggs every morning.
  final double layRate;

  final DateTime? closedOn;

  bool get isOpen => closedOn == null;

  /// Deaths as a share of the batch. Under a few percent over a whole cycle is
  /// ordinary; the figure earns its place on screen when it is not.
  double get mortalityRate => started == 0 ? 0 : died / started;

  String get layRateLabel => '${(layRate * 100).round()} %';

  Map<String, Object?> toCache() => {
        'flock_id': id,
        'batch_code': batchCode,
        'alive': alive,
        'closed': closedOn != null,
      };

  factory Flock.fromRow(Map<String, dynamic> row) {
    final closed = row['closed_on'] as String?;
    return Flock(
      id: row['flock_id'] as String,
      batchCode: row['batch_code'] as String,
      breed: row['breed'] as String?,
      arrivedOn: DateTime.parse(row['arrived_on'] as String),
      ageDays: (row['age_days'] as num?)?.toInt() ?? 0,
      started: (row['started'] as num?)?.toInt() ?? 0,
      alive: (row['alive'] as num?)?.toInt() ?? 0,
      died: (row['died'] as num?)?.toInt() ?? 0,
      sold: (row['sold'] as num?)?.toInt() ?? 0,
      eggs7d: (row['eggs_7d'] as num?)?.toInt() ?? 0,
      layRate: _num(row['lay_rate']),
      closedOn: closed == null ? null : DateTime.parse(closed),
    );
  }
}

/// The farm's day, as the server sees it.
class FarmDay {
  const FarmDay({
    required this.eggs,
    required this.deaths,
    required this.feedUsed,
    required this.moneyIn,
    required this.moneyOut,
  });

  final int eggs;
  final double deaths;
  final double feedUsed;
  final double moneyIn;
  final double moneyOut;

  factory FarmDay.fromRow(Map<String, dynamic> row) {
    return FarmDay(
      eggs: (row['eggs'] as num?)?.toInt() ?? 0,
      deaths: _num(row['deaths']),
      feedUsed: _num(row['feed_used']),
      moneyIn: _num(row['money_in']),
      moneyOut: _num(row['money_out']),
    );
  }

  static const empty = FarmDay(
    eggs: 0,
    deaths: 0,
    feedUsed: 0,
    moneyIn: 0,
    moneyOut: 0,
  );
}

/// An invoice with money still owed on it.
class OutstandingInvoice {
  const OutstandingInvoice({
    required this.id,
    required this.number,
    required this.customerName,
    required this.issuedOn,
    required this.total,
    required this.paid,
    required this.outstanding,
    required this.daysOverdue,
    this.customerPhone,
    this.dueOn,
  });

  final String id;
  final String number;
  final String customerName;
  final String? customerPhone;
  final DateTime issuedOn;
  final DateTime? dueOn;
  final double total;

  /// The sum of the payments received, which is a list and not a boolean: a
  /// hotel that pays a third now and the rest next month is the normal case.
  final double paid;

  final double outstanding;
  final int daysOverdue;

  bool get isPartlyPaid => paid > 0;
  bool get isOverdue => daysOverdue > 0;

  factory OutstandingInvoice.fromRow(Map<String, dynamic> row) {
    final due = row['due_on'] as String?;
    return OutstandingInvoice(
      id: row['invoice_id'] as String,
      number: row['number'] as String,
      customerName: row['customer_name'] as String,
      customerPhone: row['customer_phone'] as String?,
      issuedOn: DateTime.parse(row['issued_on'] as String),
      dueOn: due == null ? null : DateTime.parse(due),
      total: _num(row['total']),
      paid: _num(row['paid']),
      outstanding: _num(row['outstanding']),
      daysOverdue: (row['days_overdue'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One line of an invoice being composed. Not a server shape — this is what
/// the screen builds before `create_invoice()` is called, and it is sent as
/// the jsonb array that function takes.
class InvoiceLineDraft {
  const InvoiceLineDraft({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String description;
  final double quantity;
  final double unitPrice;

  double get amount => quantity * unitPrice;

  Map<String, Object?> toJson() => {
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}

/// The units an item can be counted in, offered first. Typing another one
/// works — `receive_stock()` takes whatever text it is given.
const farmUnits = <String>['sac', 'kg', 'litre', 'dose', 'unité'];

/// The four things that can happen to a flock, in the words used on screen.
const flockEventLabels = <String, String>{
  'mortality': 'Mortalité',
  'weight': 'Pesée',
  'vaccination': 'Vaccination',
  'sold': 'Vendus',
};

String flockEventLabel(String kind) => flockEventLabels[kind] ?? kind;

/// Egg grades. Cracked eggs are counted separately because they are sold at a
/// different price or not at all, and a farm that counts them with the rest is
/// a farm whose lay rate looks better than its income.
const eggGrades = <String, String>{
  'normal': 'Normal',
  'petit': 'Petit',
  'fêlé': 'Fêlé',
};

String _trimNumber(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}

String trimQuantity(double value) => _trimNumber(value);

/// Postgres `numeric` arrives over PostgREST as a JSON string, not a number,
/// because a double cannot hold every value a numeric(14,3) can.
double _num(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

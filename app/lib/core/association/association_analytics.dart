/// An association's « Analyses » (148's association_analytics): what the
/// server answers, read without guessing.
///
/// A caller with 'summary' visibility is given the months (in, out, held)
/// and the member count only — every line ([income], [expenses], [gave],
/// the cotisation counts, [topGivers]) is null for them. The top givers are
/// an administrator's alone.
class AssociationAnalytics {
  const AssociationAnalytics({
    required this.full,
    required this.admin,
    required this.months,
    this.income,
    this.expenses,
    required this.registered,
    this.gave,
    this.hasDues = false,
    this.upToDate,
    this.due,
    this.late,
    this.newByMonth = const [],
    this.topGivers,
  });

  final bool full;
  final bool admin;

  /// The last 12 months, oldest first.
  final List<MonthMoney> months;
  final List<CategoryAmount>? income;
  final List<CategoryAmount>? expenses;
  final int registered;
  final int? gave;
  final bool hasDues;
  final int? upToDate;
  final int? due;
  final int? late;
  final List<MonthCount> newByMonth;
  final List<Giver>? topGivers;

  double get incomeTotal =>
      (income ?? const []).fold(0.0, (s, c) => s + c.amount);
  double get expensesTotal =>
      (expenses ?? const []).fold(0.0, (s, c) => s + c.amount);

  factory AssociationAnalytics.fromJson(Map<String, dynamic> j) {
    final m = Map<String, dynamic>.from((j['members'] as Map?) ?? const {});
    List<CategoryAmount>? cats(Object? v) => v is List
        ? [for (final e in v) CategoryAmount.fromJson(Map<String, dynamic>.from(e as Map))]
        : null;
    return AssociationAnalytics(
      full: j['full'] == true,
      admin: j['admin'] == true,
      months: [
        for (final e in (j['months'] as List? ?? const []))
          MonthMoney.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      income: cats(j['income']),
      expenses: cats(j['expenses']),
      registered: _int(m['registered']) ?? 0,
      gave: _int(m['gave']),
      hasDues: m['has_dues'] == true,
      upToDate: _int(m['up_to_date']),
      due: _int(m['due']),
      late: _int(m['late']),
      newByMonth: [
        for (final e in (m['new_by_month'] as List? ?? const []))
          MonthCount(
            month: DateTime.parse('${(e as Map)['month']}'),
            count: _int(e['count']) ?? 0,
          ),
      ],
      topGivers: j['top_givers'] is List
          ? [
              for (final e in j['top_givers'] as List)
                Giver(
                  memberId: '${(e as Map)['member_id']}',
                  name: '${e['name'] ?? ''}',
                  amount: _num(e['amount']) ?? 0,
                ),
            ]
          : null,
    );
  }
}

class MonthMoney {
  const MonthMoney({required this.month, this.income, this.expenses, this.balance});

  final DateTime month;

  /// Null when the server could not say (a summary whose report is closed).
  final double? income;
  final double? expenses;

  /// What the association held (cash, bank, mobile money) at the month's end.
  final double? balance;

  factory MonthMoney.fromJson(Map<String, dynamic> j) => MonthMoney(
        month: DateTime.parse('${j['month']}'),
        income: _num(j['income']),
        expenses: _num(j['expenses']),
        balance: _num(j['balance']),
      );
}

/// One income or expense account over the period.
class CategoryAmount {
  const CategoryAmount({
    required this.accountId,
    required this.code,
    required this.name,
    required this.amount,
    this.entries = 0,
  });

  final String accountId;
  final String code;

  /// As the books hold it (accountLabel() reads it out).
  final String name;
  final double amount;
  final int entries;

  factory CategoryAmount.fromJson(Map<String, dynamic> j) => CategoryAmount(
        accountId: '${j['account_id']}',
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        amount: _num(j['amount']) ?? 0,
        entries: _int(j['entries']) ?? 0,
      );
}

class MonthCount {
  const MonthCount({required this.month, required this.count});
  final DateTime month;
  final int count;
}

class Giver {
  const Giver({required this.memberId, required this.name, required this.amount});
  final String memberId;
  final String name;
  final double amount;
}

double? _num(Object? v) =>
    v is num ? v.toDouble() : (v == null ? null : double.tryParse('$v'));
int? _int(Object? v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));

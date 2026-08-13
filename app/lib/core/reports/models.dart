// What the report functions in 002_church_profile.sql hand back, and what the
// screens need to make of it.

/// The seeded chart of accounts is written in English — it was created before
/// there was a user interface, and renaming it now would rewrite the account
/// names on every entry already posted against them.
///
/// So the translation lives here, at the edge, where it belongs: the books
/// keep their stable identifiers and the pastor reads French.
const _accountNames = <String, String>{
  // Assets
  'Cash on Hand': 'Espèces en caisse',
  'Bank Account': 'Compte bancaire',
  'Mobile Money': 'Mobile Money',
  // Income
  'Tithes': 'Dîmes',
  'Offerings': 'Offrandes',
  'Special Collections': 'Collectes spéciales',
  'Donations': 'Dons',
  // Expenses
  'Utilities': 'Eau et électricité',
  'Rent': 'Loyer',
  'Salaries & Stipends': 'Salaires',
  'Maintenance': 'Entretien',
  'Outreach & Charity': 'Œuvres sociales',
  'Supplies': 'Fournitures',
  'Events': 'Événements',
  // The two rows church_weekly_summary adds itself
  'Total received': 'Total reçu',
  'Total spent': 'Total dépensé',
};

/// Falls through to the original rather than blanking: an account added
/// server-side after this build shipped should still be readable, in English,
/// instead of vanishing from a financial report.
String accountLabel(String name) => _accountNames[name] ?? name;

/// One line of `church_weekly_summary`.
class SummaryLine {
  const SummaryLine({
    required this.category,
    required this.label,
    required this.amount,
  });

  /// 'income' | 'expense' | 'total'
  final String category;
  final String label;
  final double amount;

  String get displayLabel => accountLabel(label);
}

/// A week's worth of money, split the way the pastor asks about it.
class WeeklySummary {
  const WeeklySummary({
    required this.income,
    required this.expenses,
    required this.totalIn,
    required this.totalOut,
    required this.weekEnding,
  });

  final List<SummaryLine> income;
  final List<SummaryLine> expenses;
  final double totalIn;
  final double totalOut;
  final DateTime weekEnding;

  double get net => totalIn - totalOut;

  DateTime get weekStarting => weekEnding.subtract(const Duration(days: 6));

  bool get isEmpty => income.isEmpty && expenses.isEmpty;

  /// The function returns income lines, expense lines, and two 'total' rows,
  /// all in one result set. This sorts them out.
  factory WeeklySummary.fromRows(
    List<Map<String, dynamic>> rows, {
    required DateTime weekEnding,
  }) {
    final income = <SummaryLine>[];
    final expenses = <SummaryLine>[];
    var totalIn = 0.0;
    var totalOut = 0.0;

    for (final row in rows) {
      final line = SummaryLine(
        category: row['category'] as String,
        label: row['label'] as String,
        amount: (row['amount'] as num).toDouble(),
      );

      switch (line.category) {
        case 'income':
          income.add(line);
        case 'expense':
          expenses.add(line);
        case 'total':
          // Matched on the label the SQL emits, not on position.
          if (line.label == 'Total received') totalIn = line.amount;
          if (line.label == 'Total spent') totalOut = line.amount;
      }
    }

    return WeeklySummary(
      income: income,
      expenses: expenses,
      totalIn: totalIn,
      totalOut: totalOut,
      weekEnding: weekEnding,
    );
  }
}

/// One holding account and what is in it.
class AccountBalance {
  const AccountBalance({required this.name, required this.balance});

  final String name;
  final double balance;

  String get displayName => accountLabel(name);

  factory AccountBalance.fromRow(Map<String, dynamic> row) => AccountBalance(
        name: row['account_name'] as String,
        balance: (row['balance'] as num).toDouble(),
      );
}

/// Somebody on the church roll.
class ChurchMember {
  const ChurchMember({required this.id, required this.fullName, this.phone});

  final String id;
  final String fullName;
  final String? phone;

  factory ChurchMember.fromRow(Map<String, dynamic> row) => ChurchMember(
        id: row['id'] as String,
        fullName: (row['full_name'] as String?) ?? 'Sans nom',
        phone: row['phone'] as String?,
      );
}

/// One gift on a year-end statement.
class GivingLine {
  const GivingLine({
    required this.date,
    required this.kind,
    required this.amount,
  });

  final DateTime date;
  final String kind;
  final double amount;

  String get displayKind => accountLabel(kind);

  factory GivingLine.fromRow(Map<String, dynamic> row) => GivingLine(
        date: DateTime.parse(row['contribution_date'] as String),
        kind: row['kind'] as String,
        amount: (row['amount'] as num).toDouble(),
      );
}

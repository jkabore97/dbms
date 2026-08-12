import '../reports/models.dart' show accountLabel;

// What the accounting functions in 007_accounting.sql hand back.
//
// Every name that comes out of the server passes through `accountLabel()` on
// the way to a screen. The seeded chart in 002 is written in English — it was
// created before there was a user interface — and the translation lives at the
// edge so the books keep stable identifiers while the pastor reads French.
// Anything somebody typed themselves is not in the translation table and falls
// through unchanged, which is exactly right: their words, back verbatim.

/// The five kinds of account, in the order a chart of accounts is read.
///
/// Ordered by what a person is looking for rather than by code: what the
/// business has, then what it owes, then what it earns and spends, with equity
/// last because almost nobody here has any and it is the hardest word.
const accountTypes = <String, String>{
  'asset': 'Ce que possède l\'activité',
  'liability': 'Ce qu\'elle doit',
  'income': 'Recettes',
  'expense': 'Dépenses',
  'equity': 'Capital',
};

const accountTypeShort = <String, String>{
  'asset': 'Actif',
  'liability': 'Passif',
  'income': 'Recette',
  'expense': 'Dépense',
  'equity': 'Capital',
};

String accountTypeLabel(String type) => accountTypeShort[type] ?? type;

/// One line of the chart of accounts, with what has landed on it.
class LedgerAccount {
  const LedgerAccount({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.isActive,
    required this.balance,
    required this.entryCount,
    this.description,
  });

  final String id;
  final String code;

  /// The name as the books hold it. Posted back verbatim when this account is
  /// chosen, which is what stops "Loyer" opening a second account beside the
  /// "Rent" that has a year of history on it.
  final String name;

  final String type;
  final bool isActive;

  /// In the type's natural direction: an expense account of 40,000 means
  /// 40,000 spent, not -40,000.
  final double balance;

  final int entryCount;
  final String? description;

  /// What to show a person. French for the seeded chart, verbatim for
  /// everything anyone typed.
  String get label => accountLabel(name);

  /// An account nothing has ever been posted to can still be renamed freely.
  /// One with history cannot be renamed into something it never meant.
  bool get hasHistory => entryCount > 0;

  factory LedgerAccount.fromRow(Map<String, dynamic> row) {
    return LedgerAccount(
      id: row['account_id'] as String,
      code: row['code'] as String,
      name: row['name'] as String,
      type: row['type'] as String,
      isActive: row['is_active'] as bool? ?? true,
      balance: _num(row['balance']),
      entryCount: (row['entry_count'] as num?)?.toInt() ?? 0,
      description: row['description'] as String?,
    );
  }

  /// The shape LocalDb.cacheAccounts stores, so the categories survive a week
  /// with no signal.
  Map<String, Object?> toCache() => {
        'account_id': id,
        'code': code,
        'name': name,
        'type': type,
        'is_active': isActive,
      };
}

/// One line of `trial_balance`. Debits and credits raw and uninterpreted —
/// the whole point of the report is that the two columns are equal.
class TrialBalanceRow {
  const TrialBalanceRow({
    required this.code,
    required this.name,
    required this.type,
    required this.debit,
    required this.credit,
  });

  final String code;
  final String name;
  final String type;
  final double debit;
  final double credit;

  String get label => accountLabel(name);
  bool get isEmpty => debit == 0 && credit == 0;

  factory TrialBalanceRow.fromRow(Map<String, dynamic> row) {
    return TrialBalanceRow(
      code: row['code'] as String,
      name: row['name'] as String,
      type: row['type'] as String,
      debit: _num(row['total_debit']),
      credit: _num(row['total_credit']),
    );
  }
}

/// One line of `income_statement` or `balance_sheet`. The two reports return
/// the same shape — a section, an account, an amount — because they are the
/// same question asked over two different halves of the chart.
class StatementLine {
  const StatementLine({
    required this.section,
    required this.code,
    required this.name,
    required this.amount,
  });

  /// 'income' | 'expense' | 'asset' | 'liability' | 'equity' | 'total'
  final String section;

  final String code;
  final String name;
  final double amount;

  bool get isTotal => section == 'total';

  /// Total rows are labelled by the server in French already; account rows are
  /// named by the books and need the translation table.
  String get label => isTotal ? name : accountLabel(name);

  factory StatementLine.fromRow(Map<String, dynamic> row) {
    return StatementLine(
      section: row['section'] as String,
      code: (row['code'] as String?) ?? '',
      name: row['name'] as String,
      amount: _num(row['amount']),
    );
  }
}

/// One movement on one account, with the balance after it.
class LedgerMovement {
  const LedgerMovement({
    required this.entryId,
    required this.occurredAt,
    required this.label,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.reversed,
    required this.recordedBy,
    this.memo,
  });

  final String entryId;
  final DateTime occurredAt;
  final String label;
  final String? memo;
  final double debit;
  final double credit;

  /// The account's balance immediately after this movement. Reading down this
  /// column until it stops matching the till is the reason the report exists.
  final double balance;

  final bool reversed;
  final String recordedBy;

  double get signed => debit - credit;

  factory LedgerMovement.fromRow(Map<String, dynamic> row) {
    return LedgerMovement(
      entryId: row['entry_id'] as String,
      occurredAt: DateTime.parse(row['occurred_at'] as String).toLocal(),
      label: (row['label'] as String?) ?? 'Entrée',
      memo: row['memo'] as String?,
      debit: _num(row['debit']),
      credit: _num(row['credit']),
      balance: _num(row['balance']),
      reversed: row['reversed'] as bool? ?? false,
      recordedBy: (row['recorded_by'] as String?) ?? 'Inconnu',
    );
  }
}

/// One entry in the journal, with both sides named.
class JournalRow {
  const JournalRow({
    required this.entryId,
    required this.occurredAt,
    required this.label,
    required this.amount,
    required this.direction,
    required this.reversed,
    required this.isReversal,
    required this.recordedBy,
    this.memo,
    this.details = const {},
    this.debitNames,
    this.creditNames,
  });

  final String entryId;
  final DateTime occurredAt;

  /// What the person typed. Not a category name — that is the point of the
  /// whole migration this reads from.
  final String label;

  final String? memo;

  /// The characteristics typed with it: a supplier, an invoice number, a
  /// beneficiary. Empty for most entries and the whole story for some.
  final Map<String, dynamic> details;

  final double amount;

  /// 'in' | 'out' | 'transfer'
  final String direction;

  final bool reversed;

  /// True when this entry is itself the correction of another one.
  final bool isReversal;

  final String recordedBy;
  final String? debitNames;
  final String? creditNames;

  String get debitLabel => _labelList(debitNames);
  String get creditLabel => _labelList(creditNames);

  static String _labelList(String? names) {
    if (names == null || names.isEmpty) return '';
    return names.split(', ').map(accountLabel).join(', ');
  }

  factory JournalRow.fromRow(Map<String, dynamic> row) {
    final raw = row['details'];
    return JournalRow(
      entryId: row['entry_id'] as String,
      occurredAt: DateTime.parse(row['occurred_at'] as String).toLocal(),
      label: (row['label'] as String?) ?? 'Entrée',
      memo: row['memo'] as String?,
      details: raw is Map ? Map<String, dynamic>.from(raw) : const {},
      amount: _num(row['amount']),
      direction: (row['direction'] as String?) ?? 'transfer',
      reversed: row['reversed'] as bool? ?? false,
      isReversal: row['is_reversal'] as bool? ?? false,
      recordedBy: (row['recorded_by'] as String?) ?? 'Inconnu',
      debitNames: row['debit_names'] as String?,
      creditNames: row['credit_names'] as String?,
    );
  }
}

/// Postgres `numeric` arrives over PostgREST as a JSON string, not a number,
/// because a double cannot hold every value a numeric(14,2) can. Every amount
/// in this file goes through here rather than through a cast that works in
/// testing and throws on the first large figure.
double _num(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

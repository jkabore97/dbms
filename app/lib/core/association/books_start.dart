/// « La caisse et la cotisation » (134, batch 138): an association's books
/// given the money already in its box, and its usual cotisation.
///
/// The server's books_start(org) says what the walkthrough's step and the
/// home's card need; set_opening_balance writes the opening (once, by an
/// administrator, over books with no movement — a balanced entry between
/// the box and « Solde de départ », equity); set_contribution_default the
/// cotisation the « Recette » flow fills in. On a database without 134 the
/// reader answers null and neither the step nor the card is drawn.
library;

/// How often the usual cotisation is paid.
enum ContributionPeriod { week, month, year }

ContributionPeriod? contributionPeriodOf(String? s) => switch (s) {
      'week' => ContributionPeriod.week,
      'month' => ContributionPeriod.month,
      'year' => ContributionPeriod.year,
      _ => null,
    };

/// The usual cotisation: an amount and how often.
class ContributionDefault {
  const ContributionDefault({required this.amount, required this.period});

  final double amount;
  final ContributionPeriod period;
}

/// What books_start(org) says.
class BooksStart {
  const BooksStart({
    required this.association,
    required this.openingSet,
    this.openingAmount,
    required this.movements,
    required this.canSet,
    required this.dismissed,
    this.contribution,
  });

  factory BooksStart.fromJson(Map<String, dynamic> j) {
    num? n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');
    final c = j['contribution'];
    ContributionDefault? contribution;
    if (c is Map) {
      final amount = n(c['amount']);
      final period = contributionPeriodOf(c['period'] as String?);
      if (amount != null && amount > 0 && period != null) {
        contribution = ContributionDefault(amount: amount.toDouble(), period: period);
      }
    }
    return BooksStart(
      association: j['association'] == true,
      openingSet: j['opening_set'] == true,
      openingAmount: n(j['opening_amount'])?.toDouble(),
      movements: j['movements'] == true,
      canSet: j['can_set'] == true,
      dismissed: j['dismissed'] == true,
      contribution: contribution,
    );
  }

  final bool association;
  final bool openingSet;
  final double? openingAmount;

  /// The books already hold an entry (other than the opening).
  final bool movements;

  /// This caller may set the opening now: an administrator of an
  /// association, nothing set, no movement.
  final bool canSet;

  /// « Plus tard » on the home's card, for the business.
  final bool dismissed;
  final ContributionDefault? contribution;

  /// The home's one-time card « Indiquez votre caisse de départ ».
  bool get offersCard => association && canSet && !dismissed;

  /// The last answer per business in this run: the « Recette » flow fills
  /// the cotisation from it when the network does not answer.
  static final lastKnown = <String, BooksStart>{};
}

/// The four doors (ReportsRepository implements them; a test stands in).
abstract class BooksStartApi {
  /// Null: the server has no 134, or this is no member.
  Future<BooksStart?> booksStart(String orgId);

  Future<void> setOpeningBalance(String orgId, double amount, {String? clientUuid});

  /// [amount] null clears it.
  Future<void> setContributionDefault(String orgId, double? amount, ContributionPeriod period);

  Future<void> dismissBooksStart(String orgId);
}

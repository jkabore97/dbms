import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/credit/credit_repository.dart';
import 'package:kaj_app/core/tontine/tontine_repository.dart';

/// The client half of the carnet and the tontine: that rows parse, that the
/// arithmetic a screen leans on is right, and that a build with no server
/// says so instead of crashing.
///
/// The SQL half — balanced books, the overpayment refusal, the rotation, the
/// privacy — is proven by test_credit_book.sql and test_tontines.sql.
void main() {
  group('the carnet parses what the server sends', () {
    test('a debtor row, and how old the debt is', () {
      final row = DebtorRow.fromRow({
        'customer_id': 'c1',
        'customer_name': 'Awa',
        'phone': '+22670000001',
        'total_owed': 3000,
        'oldest_debt':
            DateTime.now().subtract(const Duration(days: 12)).toIso8601String(),
        'open_debts': 2,
      });
      expect(row.name, 'Awa');
      expect(row.totalOwed, 3000);
      expect(row.daysOld, 12);
      expect(row.openDebts, 2);
    });

    test('a debtor with no date does not crash the age line', () {
      final row = DebtorRow.fromRow({
        'customer_id': 'c1',
        'customer_name': 'Awa',
        'phone': null,
        'total_owed': 500,
        'oldest_debt': null,
        'open_debts': 1,
      });
      expect(row.daysOld, isNull);
    });

    test('a debt row carries amount, paid and remaining', () {
      final row = DebtRow.fromRow({
        'debt_id': 'd1',
        'label': 'Sac de riz',
        'amount': 2000,
        'paid': 500,
        'remaining': 1500,
        'occurred_at': '2026-08-01T10:00:00Z',
      });
      expect(row.remaining, 1500);
      expect(row.paid, 500);
    });
  });

  group('the tontine parses its round', () {
    test('a member line, taker and payment state', () {
      final m = TontineMemberStatus.fromRow({
        'member_id': 'm1',
        'member_name': 'Moussa',
        'phone': null,
        'turn_position': 2,
        'has_paid': false,
        'is_taker': true,
      });
      expect(m.position, 2);
      expect(m.isTaker, isTrue);
      expect(m.hasPaid, isFalse);
    });

    test('a summary row', () {
      final t = TontineSummary.fromRow({
        'id': 't1',
        'name': 'Tontine du marché',
        'amount': 5000,
        'period': 'weekly',
        'current_round': 3,
      });
      expect(t.currentRound, 3);
      expect(t.amount, 5000);
    });
  });

  group('a build with no server says so', () {
    // The same posture as every other repository: isConfigured is what the
    // screens check, and the thrown sentence is the one describeError() shows.
    test('credit refuses politely', () {
      final credit = CreditRepository(null);
      expect(credit.isConfigured, isFalse);
      expect(() => credit.debtors('org'), throwsStateError);
    });

    test('tontine refuses politely', () {
      final tontine = TontineRepository(null);
      expect(tontine.isConfigured, isFalse);
      expect(() => tontine.list('org'), throwsStateError);
    });
  });
}

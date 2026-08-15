import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/notify/notifications_repository.dart';

/// The client half of the bell: rows parse, unread is derived correctly,
/// and a build with no server says so instead of crashing.
///
/// The server half — who hears what, the crossing-not-every-sale rule, the
/// RLS wall — is proven by test_notifications.sql.
void main() {
  group('a ring parses what the server sends', () {
    test('an unread row', () {
      final n = NotificationRow.fromRow({
        'id': 'n1',
        'kind': 'low_stock',
        'message': 'Stock bas : Savon (3 restant)',
        'created_at': '2026-08-15T08:00:00Z',
        'read_at': null,
      });
      expect(n.isUnread, isTrue);
      expect(n.kind, 'low_stock');
    });

    test('a read row', () {
      final n = NotificationRow.fromRow({
        'id': 'n1',
        'kind': 'debt_settled',
        'message': 'Crédit soldé : Awa a fini de payer 1000',
        'created_at': '2026-08-15T08:00:00Z',
        'read_at': '2026-08-15T09:00:00Z',
      });
      expect(n.isUnread, isFalse);
    });
  });

  group('a build with no server says so', () {
    test('the bell refuses politely', () {
      final notify = NotificationsRepository(null);
      expect(notify.isConfigured, isFalse);
      expect(() => notify.recent(), throwsStateError);
    });
  });
}

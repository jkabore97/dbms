import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/auth/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// What the app says when the server refuses something.
///
/// These exist because one of them reached a phone: a report screen showed
/// "Le serveur a refusé la demande : Could not find the function
/// public.trial_balance(p_from, p_org_id, p_to) in the schema cache" — raw
/// PostgREST English, in a French app, naming an argument list. It reads as a
/// bug in the app and is in fact a migration that was never applied to that
/// database.
void main() {
  group('a function missing from the schema cache', () {
    test('is explained as an out-of-date database, and names what is missing',
        () {
      final described = AuthRepository.describeError(
        const PostgrestException(
          message: 'Could not find the function '
              'public.trial_balance(p_from, p_org_id, p_to) in the schema cache',
          code: 'PGRST202',
        ),
      );

      expect(described, contains("n'est pas à jour"));
      expect(described, contains('trial_balance'));
      // The argument list is noise to everyone who can act on this.
      expect(described, isNot(contains('p_org_id')));
    });

    test('is recognised by the message alone when no code is attached', () {
      final described = AuthRepository.describeError(
        const PostgrestException(
          message: 'Could not find the function public.income_statement('
              'p_org_id) in the schema cache',
        ),
      );

      expect(described, contains("n'est pas à jour"));
      expect(described, contains('income_statement'));
    });
  });

  group('a refusal is not reported as an out-of-date database', () {
    test('a permission refusal is stated as one, in French', () {
      // Changed deliberately. This used to pass the raw text through, so a
      // shopkeeper saw "new row violates row-level security policy for table
      // \"invoices\"" — which names an internal table and reads as a crash,
      // when it is in fact the tenant boundary working exactly as designed.
      final described = AuthRepository.describeError(
        const PostgrestException(
            message: 'new row violates row-level security policy'),
      );

      expect(described, contains('droit'));
      expect(described, isNot(contains('row-level security')));
      expect(described, isNot(contains("n'est pas à jour")));
    });

    test('a message this app has never seen is passed through, not swallowed',
        () {
      // The guarantee that matters: an unrecognised failure must still say
      // something specific, because a generic "erreur" is unreportable and
      // whoever is debugging it has nothing to go on.
      final described = AuthRepository.describeError(
        const PostgrestException(message: 'deadlock detected'),
      );

      expect(described, contains('deadlock detected'));
      expect(described, isNot(contains("n'est pas à jour")));
    });

    test('no signal is not reported as a refusal at all', () {
      final described = AuthRepository.describeError(
        Exception('SocketException: Failed host lookup'),
      );

      expect(described, contains('connexion'));
    });
  });
}

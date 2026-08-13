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

  test('any other refusal still says what the server said', () {
    final described = AuthRepository.describeError(
      const PostgrestException(
          message: 'new row violates row-level security policy'),
    );

    expect(described, contains('row-level security'));
    expect(described, isNot(contains("n'est pas à jour")));
  });
}

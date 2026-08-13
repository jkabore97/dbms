import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns whatever the server threw into something a person can act on.
///
/// This exists because of what the app actually showed. Almost every screen
/// interpolated the raw object — `'$error'` — into a snackbar or an error
/// card, and for a failed write that renders as:
///
/// ```
/// PostgrestException(message: new row violates row-level security policy
/// for table "invoices", code: 42501, details: Forbidden, hint: null)
/// ```
///
/// in front of a shopkeeper in Ouagadougou who reads French. It is not merely
/// ugly. It tells her nothing about what to do, it names internal tables, and
/// it makes a permission decision — which is a normal, expected outcome — look
/// like the app has broken.
///
/// Three kinds of failure get three different sentences, because they need
/// three different responses from the person reading them:
///
///   * **Refused.** The server said no on purpose. The message the function
///     raised is the useful part and it is already written in French by the
///     migration that raised it, so it is passed through.
///   * **Not reachable.** No signal, or the server is down. Nothing is wrong
///     with what they did and trying again later will work.
///   * **Out of date.** The app is asking for something this database has not
///     been migrated to yet — `PGRST202`. That is an operator problem, and
///     saying so stops somebody hunting for a setting that does not exist.
String describeError(Object error) {
  if (error is AuthException) return _auth(error);
  if (error is PostgrestException) return _postgrest(error);
  if (error is StateError) return error.message;

  final text = error.toString();

  // SocketException, ClientException, TimeoutException — the transport, not
  // the server. All of them mean the same thing to the person holding it.
  if (_looksOffline(text)) {
    return 'Pas de connexion. Réessayez quand le réseau revient.';
  }

  return text;
}

String _postgrest(PostgrestException error) {
  final code = error.code ?? '';
  final message = error.message;

  // The function this build calls does not exist on this database: the app is
  // ahead of its migrations. Distinct from a permission refusal, and fixed by
  // a completely different person.
  if (code == 'PGRST202' || message.contains('Could not find the function')) {
    // Name the function, drop its argument list. Whoever can act on this
    // needs to know which migration is missing; "p_org_id, p_to" is noise to
    // every one of them.
    final name = _missingFunction(message);
    return "La base de données n'est pas à jour"
        '${name == null ? '' : ' : $name est introuvable'}. '
        'Appliquez les migrations manquantes.';
  }

  // 42501 is RLS. It is not a bug — it is the tenant boundary doing its job —
  // so it gets a sentence about permission rather than about failure.
  if (code == '42501' || message.contains('row-level security')) {
    return "Vous n'avez pas le droit de faire cela dans cette entreprise.";
  }

  if (code == '23505' || message.contains('duplicate key')) {
    return 'Cet enregistrement existe déjà.';
  }

  if (code == '23503') {
    return "Impossible : cet élément est utilisé ailleurs.";
  }

  // A `raise exception` from one of this schema's own functions. Those
  // messages are written for the person reading them — "Cette facture a déjà
  // été payée en partie" — so passing the text through is the whole point.
  // Postgres prefixes nothing, so what arrives is what the migration wrote.
  if (message.trim().isNotEmpty) return message.trim();

  return "L'opération n'a pas pu être effectuée.";
}

String _auth(AuthException error) {
  final message = error.message.toLowerCase();

  if (message.contains('signups not allowed') ||
      message.contains('user not found') ||
      message.contains('should_create_user')) {
    // Said in terms of the credential the app actually uses. It read "ce
    // numéro" while sign-in was an SMS code; sending somebody to look at
    // their phone for an account they made with an e-mail address is how a
    // correct message still wastes an afternoon.
    return "Cette adresse n'a pas encore de compte. "
        'Choisissez « Créer un compte ».';
  }
  if (message.contains('already registered') ||
      message.contains('already exists')) {
    return 'Un compte existe déjà pour ces informations. '
        'Choisissez « Se connecter ».';
  }
  if (message.contains('password') && message.contains('least')) {
    return 'Le mot de passe doit contenir au moins 6 caractères.';
  }
  if (message.contains('invalid login') ||
      message.contains('invalid credentials')) {
    return 'Adresse e-mail ou mot de passe incorrect.';
  }
  if (message.contains('token has expired') || message.contains('expired')) {
    return 'Ce code a expiré. Demandez-en un nouveau.';
  }
  // Still reachable after SMS sign-in was removed: confirming an e-mail
  // address is also a token, and it also expires.
  if (message.contains('invalid token') || message.contains('otp')) {
    return 'Ce lien est incorrect ou a déjà été utilisé.';
  }
  if (message.contains('email not confirmed')) {
    return "Confirmez votre adresse e-mail avant de vous connecter.";
  }
  if (_looksOffline(message)) {
    return 'Pas de connexion. Réessayez quand le réseau revient.';
  }
  return error.message;
}

/// `public.trial_balance(p_from, p_org_id, p_to)` -> `trial_balance`.
String? _missingFunction(String message) {
  final match =
      RegExp(r'function\s+(?:public\.)?([A-Za-z0-9_]+)').firstMatch(message);
  return match?.group(1);
}

bool _looksOffline(String text) {
  final t = text.toLowerCase();
  return t.contains('socketexception') ||
      t.contains('failed host lookup') ||
      t.contains('clientexception') ||
      t.contains('connection refused') ||
      t.contains('connection closed') ||
      t.contains('network is unreachable') ||
      t.contains('timeoutexception') ||
      t.contains('timed out');
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/tr.dart';

/// What the server asks of a shopper's number before an order (109's
/// order_phone_gate): whether the platform asks for a proved number at
/// all, and whether this account has one — and which.
class OrderPhoneGate {
  const OrderPhoneGate({
    required this.required,
    required this.verified,
    this.phone,
  });

  /// The platform's switch (Réglages › « Numéro WhatsApp vérifié avant de
  /// commander »). Off as installed.
  final bool required;

  /// This account's number was proved (auth.users.phone_confirmed_at).
  final bool verified;

  /// The proved number, « +226… », once there is one.
  final String? phone;

  /// The sheet must prove a number before the order.
  bool get mustVerify => required && !verified;

  factory OrderPhoneGate.fromJson(Map<String, dynamic> json) => OrderPhoneGate(
        required: json['required'] == true,
        verified: json['verified'] == true,
        phone: json['phone'] as String?,
      );
}

/// A number proved on WhatsApp (109). Supabase makes the six digits and
/// checks them; its « Send SMS » hook hands them to the whatsapp-otp
/// Worker, which sends them on WhatsApp. The app only asks for the change
/// and types the code back: nothing secret passes through here.
abstract class WhatsAppPhone {
  /// The server's answer, or null when there is none to have — a build with
  /// no server, a database before 109, no signal: then nothing is asked
  /// here, and place_order still says no if the platform asks for a number.
  Future<OrderPhoneGate?> gate();

  /// Asks Supabase to send a code to [e164] (« +22670123456 »).
  Future<void> sendCode(String e164);

  /// The code typed back. The account's number is then [e164], proved.
  Future<void> confirm(String e164, String code);
}

class SupabaseWhatsAppPhone implements WhatsAppPhone {
  SupabaseWhatsAppPhone(this._client);

  final SupabaseClient? _client;

  @override
  Future<OrderPhoneGate?> gate() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return null;
    try {
      // A slow line must not hold the order: no answer in time is no gate
      // here, and place_order still decides.
      final v = await client.rpc('order_phone_gate').timeout(const Duration(seconds: 8));
      return v is Map ? OrderPhoneGate.fromJson(Map<String, dynamic>.from(v)) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> sendCode(String e164) async {
    final client = _client;
    if (client == null) throw StateError('Pas de serveur.');
    await client.auth.updateUser(UserAttributes(phone: e164));
  }

  @override
  Future<void> confirm(String e164, String code) async {
    final client = _client;
    if (client == null) throw StateError('Pas de serveur.');
    await client.auth.verifyOTP(
      type: OtpType.phoneChange,
      phone: e164,
      token: code,
    );
  }
}

/// What went wrong, in a few words the shopper can act on (in [language]).
/// Supabase's codes first; the Worker's own sentences (already French) are
/// passed through; anything else is « the code did not leave » — or, when
/// [confirming] a typed code, « it could not be checked ».
String whatsAppProblem(String language, Object error, {bool confirming = false}) {
  String say(String fr) => translate(language, fr);
  if (error is AuthException) {
    final code = error.code ?? '';
    final message = error.message;
    if (code == 'phone_exists' || message.contains('already been registered')) {
      return say('Ce numéro est déjà celui d\'un autre compte Mara.');
    }
    if (code == 'otp_expired' || message.contains('expired or is invalid')) {
      return say('Code faux ou expiré. Vérifiez les 6 chiffres, ou demandez un nouveau code.');
    }
    if (code == 'over_sms_send_rate_limit' || error.statusCode == '429') {
      return say('Patientez une minute avant de demander un nouveau code.');
    }
    if (code == 'validation_failed' && message.toLowerCase().contains('phone')) {
      return say('Ce numéro n\'est pas valide.');
    }
    if (error is AuthRetryableFetchException) {
      return say('Pas de réseau. Vérifiez la connexion et réessayez.');
    }
    // The Worker's refusals, written for the shopper (workers/whatsapp-otp).
    const worker = {
      'Ce numéro ne reçoit pas WhatsApp. Vérifiez-le, ou essayez un autre numéro.',
      'Trop de codes envoyés. Réessayez dans quelques minutes.',
      'Le code n\'a pas pu partir sur WhatsApp. Réessayez dans un moment.',
      'WhatsApp n\'a pas répondu. Réessayez dans un moment.',
      'L\'envoi du code par WhatsApp n\'est pas encore configuré.',
      'Numéro de téléphone incomplet.',
    };
    if (worker.contains(message)) return say(message);
  }
  return confirming
      ? say('Le code n\'a pas pu être vérifié. Vérifiez la connexion et réessayez.')
      : say('Le code n\'a pas pu partir sur WhatsApp. Réessayez dans un moment.');
}

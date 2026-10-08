import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Reaching the people who run Kaj.
///
/// Support lives on WhatsApp because that is the phone every user already has
/// open — a support address they must install an email client to use is a
/// support address nobody uses here.
class Support {
  Support._();

  /// The support line before the platform sets its own (Réglages › « Numéro
  /// WhatsApp de l'aide Mara », 113). In full international form without
  /// spaces or a leading '+'. Left as the Burkina country code so a wrong
  /// number never silently reaches a stranger.
  static const String whatsAppNumber = '22600000000';

  /// The platform's number (113), once asked; null until then or unset.
  static String? _platform;
  static Future<void>? _asking;

  /// Asks the platform's number once, ahead of the tap: a browser opens a
  /// chat only straight from the gesture, never after a wait.
  static void warm(SupabaseClient? client) {
    if (client == null || _platform != null || _asking != null) return;
    _asking = () async {
      try {
        final v = await client.rpc('support_whatsapp');
        if (v is String && RegExp(r'^\d{8,15}$').hasMatch(v)) _platform = v;
      } catch (_) {
        // No answer: the line above, as before.
      } finally {
        _asking = null;
      }
    }();
  }

  static const String _greeting = "Bonjour, j'ai besoin d'aide avec Mara.";

  /// Opens the support chat in WhatsApp (or a browser tab on the web) — the
  /// platform's number once known (113), the line above until then. Shows a
  /// gentle message if nothing can handle the link rather than failing
  /// quietly.
  static Future<void> openWhatsApp(BuildContext context) async {
    final uri = Uri.parse(
        'https://wa.me/${_platform ?? whatsAppNumber}?text=${Uri.encodeComponent(_greeting)}');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(context.tr('Impossible d\'ouvrir WhatsApp sur cet appareil.')),
        ));
      }
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(context.tr('Impossible d\'ouvrir WhatsApp sur cet appareil.')),
        ));
      }
    }
  }
}

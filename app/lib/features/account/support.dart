import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Reaching the people who run Kaj.
///
/// Support lives on WhatsApp because that is the phone every user already has
/// open — a support address they must install an email client to use is a
/// support address nobody uses here.
class Support {
  Support._();

  /// The support line. Change this to your real support WhatsApp number, in
  /// full international form without spaces or a leading '+'. Left as the
  /// Burkina country code so a wrong number never silently reaches a stranger.
  static const String whatsAppNumber = '22600000000';

  static const String _greeting = "Bonjour, j'ai besoin d'aide avec Kaj.";

  /// Opens the support chat in WhatsApp (or a browser tab on the web). Shows a
  /// gentle message if nothing can handle the link rather than failing quietly.
  static Future<void> openWhatsApp(BuildContext context) async {
    final uri = Uri.parse(
        'https://wa.me/$whatsAppNumber?text=${Uri.encodeComponent(_greeting)}');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text("Impossible d'ouvrir WhatsApp sur cet appareil."),
        ));
      }
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text("Impossible d'ouvrir WhatsApp sur cet appareil."),
        ));
      }
    }
  }
}

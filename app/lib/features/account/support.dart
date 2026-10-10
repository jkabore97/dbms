import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kaj_app/core/errors.dart' show isSchemaOutOfDate;
import 'package:kaj_app/core/l10n/tr.dart';
import 'package:kaj_app/core/nav/app_scope.dart';
import 'package:kaj_app/core/theme/kaj_card.dart';

/// How to reach the people who run Mara (« Aide Mara », 126): the
/// platform's e-mail, its WhatsApp number and the hours it answers, set in
/// Réglages › « Aide aux clients » and read by support_contacts() — the
/// same three the site's /aide shows.
class SupportContacts {
  const SupportContacts({required this.email, this.whatsapp, required this.hours});

  /// As installed (126), and what a database before it says.
  static const fallback =
      SupportContacts(email: Support.defaultEmail, hours: Support.defaultHours);

  /// support_contacts()'s answer, each value checked; the defaults for the
  /// rest. A number that is not 8 to 15 digits is no number.
  factory SupportContacts.fromJson(Object? v) {
    final j = v is Map ? v : const {};
    final email = '${j['email'] ?? ''}'.trim();
    final hours = '${j['hours'] ?? ''}'.trim();
    return SupportContacts(
      email: Support.isEmail(email) ? email : Support.defaultEmail,
      whatsapp: Support.digits(j['whatsapp']),
      hours: hours.isEmpty || hours.runes.length > 60 ? Support.defaultHours : hours,
    );
  }

  final String email;

  /// Digits only, or null: no WhatsApp button anywhere.
  final String? whatsapp;
  final String hours;
}

class Support {
  Support._();

  static const defaultEmail = 'hello@kaj-consulting.com';
  static const defaultHours = '24 h/24, 7 j/7';

  /// What the platform said, once asked; the defaults (and no number)
  /// until then.
  static final contacts = ValueNotifier<SupportContacts>(SupportContacts.fallback);
  static bool _known = false;
  static Future<void>? _asking;

  /// The number as wa.me wants it, or null.
  static String? digits(Object? v) =>
      v is String && RegExp(r'^\d{8,15}$').hasMatch(v) ? v : null;

  /// An address someone can write to, as 126's trigger and the site's
  /// /aide check it: one « @ », a dot after it, at most 120 characters
  /// (counted as Postgres counts them), and nothing that would break out
  /// of a mailto: link or an HTML attribute — no space, < > " ' ? & , ;.
  static bool isEmail(String v) =>
      v.runes.length <= 120 &&
      RegExp(r'''^[^@\s<>"'?&,;]+@[^@\s<>"'?&,;]+\.[^@\s<>"'?&,;.]+$''').hasMatch(v);

  /// Asks the platform once, ahead of the tap: a browser opens a chat only
  /// straight from the gesture, never after a wait. A database before 126
  /// gives 113's number and the e-mail and hours as installed; no answer
  /// at all is asked again the next time.
  static Future<void> warm(SupabaseClient? client) {
    if (client == null || _known) return Future.value();
    return _asking ??= () async {
      try {
        contacts.value = SupportContacts.fromJson(await client.rpc('support_contacts'));
        _known = true;
      } catch (error) {
        if (isSchemaOutOfDate(error)) {
          try {
            final n = digits(await client.rpc('support_whatsapp'));
            contacts.value = SupportContacts(email: defaultEmail, whatsapp: n, hours: defaultHours);
            _known = true;
          } catch (_) {
            // Signed out before 126 (113's door is the signed-in's): no number.
          }
        }
      } finally {
        _asking = null;
      }
    }();
  }

  /// Forgets what was asked (tests).
  @visibleForTesting
  static void reset([SupportContacts value = SupportContacts.fallback]) {
    contacts.value = value;
    _known = value != SupportContacts.fallback;
    _asking = null;
  }

  /// The hours as this reader reads them: the installed words in their
  /// language, anything the platform typed as typed.
  /// The installed French is drawn with non-breaking spaces (« 24 h/24,
  /// 7 j/7 » never breaks between 24 and h); it is stored with plain ones,
  /// as an admin types it in Réglages.
  static String hoursText(BuildContext context, String hours) {
    if (hours != defaultHours) return hours;
    final t = context.tr('24 h/24, 7 j/7');
    return t == defaultHours ? defaultHoursShown : t;
  }

  /// [defaultHours] as drawn: non-breaking spaces inside « 24 h/24 » and
  /// « 7 j/7 ».
  static const defaultHoursShown = '24\u00A0h/24, 7\u00A0j/7';

  /// Opens the chat in WhatsApp (or a browser tab on the web) — only when
  /// the platform set a number; callers draw no button without one.
  static Future<void> openWhatsApp(BuildContext context) async {
    final number = contacts.value.whatsapp;
    if (number == null) return;
    await _launch(
      context,
      Uri.parse('https://wa.me/$number?text='
          '${Uri.encodeComponent(context.tr('Bonjour, j\'ai besoin d\'aide avec Mara.'))}'),
      context.tr('Impossible d\'ouvrir WhatsApp sur cet appareil.'),
    );
  }

  /// Opens a new e-mail to the platform's address.
  static Future<void> openEmail(BuildContext context) => _launch(
        context,
        Uri(scheme: 'mailto', path: contacts.value.email, query: 'subject=${Uri.encodeComponent('Aide Mara')}'),
        context.tr('Aucune application d\'e-mail : écrivez à {email}.', {'email': contacts.value.email}),
      );

  /// Shows a gentle message if nothing can handle the link rather than
  /// failing quietly.
  static Future<void> _launch(BuildContext context, Uri uri, String failed) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text(failed)));
  }
}

/// « Aide Mara » in the app (126): the hours, « WhatsApp » once the
/// platform set a number, « E-mail » always, and the address itself.
/// Business Compte › Aide (a shop, a farm, an association), the shopper's
/// profile › Aide, and the help page (/aide) all show this one. Asks
/// support_contacts() itself, once for the whole app.
class SupportCard extends StatefulWidget {
  const SupportCard({super.key, this.framed = true});

  /// In a card of its own; false inside a list that already frames it.
  final bool framed;

  @override
  State<SupportCard> createState() => _SupportCardState();
}

class _SupportCardState extends State<SupportCard> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Support.warm(AppScope.maybeOf(context)?.auth.client);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<SupportContacts>(
      valueListenable: Support.contacts,
      builder: (context, c, _) {
        final body = Padding(
          key: const Key('support-card'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.support_agent_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('Aide Mara'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('Une question, un souci ? Nous répondons {hours}.',
                    {'hours': Support.hoursText(context, c.hours)}),
                key: const Key('support-hours'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (c.whatsapp != null)
                    FilledButton.icon(
                      key: const Key('support-whatsapp'),
                      onPressed: () => Support.openWhatsApp(context),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: Text(context.tr('WhatsApp')),
                    ),
                  OutlinedButton.icon(
                    key: const Key('support-email'),
                    onPressed: () => Support.openEmail(context),
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: Text(context.tr('E-mail')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(c.email,
                  key: const Key('support-address'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        );
        return widget.framed ? KajCard(margin: EdgeInsets.zero, child: body) : body;
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/store_rules.dart';
import '../../core/auth/models.dart';
import '../../core/db/local_db.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../account/support.dart';
import 'help_words.dart';

/// Writing to Mara from a business (143), the same for a shop, a farm and
/// an association:
///
///   * Pro: WhatsApp at once, the message saying « [PRO] » and who writes;
///   * Basic: once a day on this device, a word first — « Obtenez une
///     réponse plus rapide et un meilleur accompagnement avec Mara Pro »,
///     « Passer à Pro » (the comparison page) and a small « Continuer » that
///     opens WhatsApp; for someone who cannot buy Pro (an employee), « Demandez
///     au propriétaire de passer à Pro » and « Continuer » alone. The other
///     taps of the day go straight to WhatsApp.
///
/// Never an invitation to Pro where this build sells none (the iPhone app
/// before the App Store sells it, [sellsProInApp]): straight to WhatsApp.
///
/// A browser opens a chat only straight from a tap, never after a wait:
/// whether the word was said today is read ahead ([warm], when a help page
/// opens), so the tap decides at once; « Continuer » is a tap of its own.
class HelpContact {
  HelpContact._();

  /// The day the word was last said, as read from the device.
  static String? _shownOn;
  static bool _read = false;

  @visibleForTesting
  static HelpPrefStore? debugStore;

  @visibleForTesting
  static DateTime Function()? debugNow;

  @visibleForTesting
  static void reset() {
    _shownOn = null;
    _read = false;
    _memory.clear();
  }

  static final _memory = <String, String>{};

  static const _nudgeKey = 'help_pro_nudge_day';

  static String today() {
    final n = (debugNow ?? DateTime.now)();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static HelpPrefStore _store(BuildContext context) =>
      debugStore ?? _DbPrefs(AppScope.maybeOf(context)?.db);

  /// A pref of the help, or null: the device's, the memory's when the
  /// device's store cannot be read (a private window, blocked storage).
  static Future<String?> readPref(HelpPrefStore store, String key) async {
    try {
      final v = await store.read(key);
      if (v != null) return v;
    } catch (_) {}
    return _memory[key];
  }

  static Future<void> writePref(
    HelpPrefStore store,
    String key,
    String? value,
  ) async {
    if (value == null) {
      _memory.remove(key);
    } else {
      _memory[key] = value;
    }
    try {
      await store.write(key, value);
    } catch (_) {}
  }

  /// Reads ahead whether the word was said today (a help page opening).
  static Future<void> warm(BuildContext context) async {
    final store = _store(context);
    _shownOn = await readPref(store, _nudgeKey);
    _read = true;
  }

  /// Whether a Basic tap says the word first now.
  static bool nudgeDue() => sellsProInApp && (!_read || _shownOn != today());

  /// « WhatsApp » from a business. [pro]: the business is on Mara Pro.
  /// [canUpgrade]: the person may buy it (the owner or an admin) — null
  /// asks the business's roles. [page]: where they came from.
  static Future<void> whatsApp(
    BuildContext context,
    OrgSummary org, {
    required bool pro,
    bool? canUpgrade,
    String? page,
    String? ref,
  }) async {
    final text = helpWhatsAppText(context, org, pro: pro, page: page, ref: ref);
    if (pro || !nudgeDue()) {
      await Support.openWhatsApp(context, text: text);
      return;
    }
    final day = today();
    _shownOn = day;
    _read = true;
    // Said once today on this device, whatever is tapped next.
    final store = _store(context);
    await writePref(store, _nudgeKey, day);
    if (!context.mounted) return;
    final owner = canUpgrade ?? org.isAdmin;
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => HelpProNudge(owner: owner, whatsAppText: text),
    );
    if (choice == 'pro' && context.mounted) {
      await context.push(Routes.inside(org.id, 'kaj-pro'));
    }
  }

  /// « E-mail » from a business: its name and reference in the subject.
  static Future<void> email(
    BuildContext context,
    OrgSummary org, {
    required bool pro,
    String? ref,
  }) => Support.openEmail(
    context,
    subject: helpEmailSubject(context, org, pro: pro, ref: ref),
  );
}

/// Where the help keeps its two small prefs (the word of the day, the FAQ
/// banner closed).
abstract class HelpPrefStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class _DbPrefs implements HelpPrefStore {
  _DbPrefs(this._db);
  final LocalDb? _db;

  @override
  Future<String?> read(String key) async => _db?.readPref(key);

  @override
  Future<void> write(String key, String? value) async =>
      _db?.writePref(key, value);
}

/// For tests: prefs in memory.
class MemoryHelpPrefs implements HelpPrefStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// The Basic pop-up (143): Pro's promise and « Passer à Pro » for the
/// owner, « Demandez au propriétaire » for anybody else, and « Continuer »
/// to WhatsApp — itself a tap, so a browser opens the chat.
class HelpProNudge extends StatelessWidget {
  const HelpProNudge({
    super.key,
    required this.owner,
    required this.whatsAppText,
  });

  final bool owner;
  final String whatsAppText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('help-nudge'),
      scrollable: true,
      icon: const Icon(Icons.support, color: maraCaramel, size: 32),
      title: Text(
        owner
            ? context.tr(
                'Obtenez une réponse plus rapide et un meilleur accompagnement avec Marakaj Pro',
              )
            : context.tr('Demandez au propriétaire de passer à Pro'),
        key: const Key('help-nudge-title'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      // The owner's words alone for the owner; for anybody else, why the
      // owner would (never « 24/7 » on Basic, not even as a promise).
      content: owner
          ? null
          : Text(
              context.tr(
                'Obtenez une réponse plus rapide et un meilleur accompagnement avec Marakaj Pro',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        if (owner)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('help-nudge-pro'),
              style: FilledButton.styleFrom(
                backgroundColor: maraCaramel,
                foregroundColor: helpCaramelInk,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.of(context).pop('pro'),
              child: Text(
                context.tr('Passer à Pro'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        Center(
          child: TextButton(
            key: const Key('help-nudge-continue'),
            // The chat first, from the tap itself (a browser opens it only
            // so), then the dialog goes.
            onPressed: () {
              Support.openWhatsApp(context, text: whatsAppText);
              Navigator.of(context).pop('continue');
            },
            child: Text(context.tr('Continuer')),
          ),
        ),
      ],
    );
  }
}

/// At the top of « Questions fréquentes » for a Basic business (143):
/// « Une aide plus rapide, un formateur, avec Mara Pro » and « Passer à
/// Pro » — for an employee, « Demandez au propriétaire de passer à Pro ».
/// Closed with its cross, it comes back the next day. Never for a Pro
/// business, nobody without a business, nor where this build sells no Pro.
class FaqProBanner extends StatefulWidget {
  const FaqProBanner({super.key, required this.org, this.canUpgrade});

  final OrgSummary org;
  final bool? canUpgrade;

  static bool shownFor(OrgSummary? org) =>
      org != null && !org.isPro && !org.isObserverOnly && sellsProInApp;

  @override
  State<FaqProBanner> createState() => _FaqProBannerState();
}

class _FaqProBannerState extends State<FaqProBanner> {
  bool? _closedToday;

  String get _key => 'faq_pro_banner_closed:${widget.org.id}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_closedToday != null) return;
    final store = HelpContact._store(context);
    HelpContact.readPref(store, _key).then((v) {
      if (mounted) setState(() => _closedToday = v == HelpContact.today());
    });
  }

  Future<void> _close() async {
    setState(() => _closedToday = true);
    await HelpContact.writePref(
      HelpContact._store(context),
      _key,
      HelpContact.today(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!FaqProBanner.shownFor(widget.org) || _closedToday != false) {
      return const SizedBox.shrink();
    }
    final owner = widget.canUpgrade ?? widget.org.isAdmin;
    return Container(
      key: const Key('faq-pro-banner'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
      decoration: BoxDecoration(
        color: maraDeep,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.support, color: maraCaramel),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  owner
                      ? context.tr(
                          'Une aide plus rapide, un formateur, avec Marakaj Pro',
                        )
                      : context.tr('Demandez au propriétaire de passer à Pro'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                key: const Key('faq-pro-banner-close'),
                tooltip: context.tr('Fermer'),
                visualDensity: VisualDensity.compact,
                onPressed: _close,
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
          if (!owner)
            Padding(
              padding: const EdgeInsets.only(left: 34, right: 12, top: 2),
              child: Text(
                context.tr('Une aide plus rapide, un formateur, avec Marakaj Pro'),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          if (owner) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                key: const Key('faq-pro-banner-go'),
                style: FilledButton.styleFrom(
                  backgroundColor: maraCaramel,
                  foregroundColor: helpCaramelInk,
                ),
                onPressed: () =>
                    context.push(Routes.inside(widget.org.id, 'kaj-pro')),
                child: Text(
                  context.tr('Passer à Pro'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

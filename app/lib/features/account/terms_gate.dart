import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../../core/errors.dart';
import '../../core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/terms/terms.dart';
import '../../core/theme/mara_mark.dart';
import '../courier/courier_words.dart' show courierCharter;
import 'legal_screens.dart';

/// « Conditions d'utilisation » before anything else (142, batch 147).
///
/// When the owner asked — « make people accept them just after they sign
/// in for the first time … I need to protect my business » — the moments
/// chosen are:
///
///  * everyone, at the first sign-in or opening of the app after 142 (and
///    at the first sign-in of a new account): this page, full screen, over
///    whatever the app would show. A short summary, links to the whole
///    texts, one box « J'ai lu et j'accepte … », « Continuer ». Nothing
///    else is reachable; the only other way out is « Se déconnecter ».
///    Shoppers, business people, couriers and trainers alike. The street
///    stays open signed out: a visitor is asked when they sign in to order;
///  * someone who owns a business is asked the seller's commitments here
///    too (an existing business; a new one is asked at its creation);
///  * an approved courier, the courier's charter when its version changes
///    (112's applicants accept it in their dossier);
///  * a new version of any of them (the command center's « Nouvelle
///    version »): asked again here, with « Ce qui change ».
///
/// The server refuses an order, a creation and an application without
/// them (142): this page comes first, the server is the wall. Before 142,
/// or with no signal, nothing is asked and nothing blocked
/// (TermsController fails open).
class TermsGate extends StatelessWidget {
  const TermsGate({
    super.key,
    required this.controller,
    required this.onSignOut,
    required this.child,
    this.navigatorKey,
  });

  final TermsController controller;
  final Future<void> Function() onSignOut;
  final Widget child;

  /// The gate's own navigator (the whole texts read from it): main.dart's
  /// back button closes those first, and never reaches the app's router
  /// hidden under the gate ([handleBack]).
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Android's back while the gate is up (main.dart, through BackFirst,
  /// which hears it before the router): a text read from the gate is
  /// closed; on the gate itself the phone leaves the app, as from any first
  /// page. Null when no gate is shown — the back is the app's as before.
  /// Never the router's: popping a page or asking « Quitter Mara ? » under
  /// the gate, unseen, is what this prevents.
  static Future<bool?> handleBack(TermsController controller, GlobalKey<NavigatorState> key) async {
    if (controller.gate.isEmpty) return null;
    final nav = key.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    // Not awaited: the phone's answer is not the back's to wait for.
    unawaited(SystemNavigator.pop());
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final gate = controller.gate;
        // The first answer about this person not in yet (a few seconds at
        // most, TermsController.holdFor): a plain loading page rather than
        // the business screens flashing before the gate.
        final holding = gate.isEmpty && controller.holding;
        final covered = gate.isNotEmpty || holding;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Kept mounted (its place, its pages), out of reach.
            ExcludeFocus(
              excluding: covered,
              child: ExcludeSemantics(excluding: covered, child: child),
            ),
            if (holding)
              Positioned.fill(
                child: ColoredBox(
                  key: const Key('terms-hold'),
                  color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 1),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
            if (gate.isNotEmpty)
              Positioned.fill(
                child: _GateNavigator(
                  key: ValueKey('terms-gate-${controller.userId}'),
                  controller: controller,
                  onSignOut: onSignOut,
                  navigatorKey: navigatorKey,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Its own pages: the gate, and the whole texts read from it.
class _GateNavigator extends StatelessWidget {
  const _GateNavigator({super.key, required this.controller, required this.onSignOut, this.navigatorKey});

  final TermsController controller;
  final Future<void> Function() onSignOut;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 1),
      // Its own Navigator, above the app's router: the app's
      // HeroController is the router's alone.
      child: HeroControllerScope.none(
        child: Navigator(
          key: navigatorKey,
          onGenerateInitialRoutes: (_, _) => [
            MaterialPageRoute<void>(
              builder: (_) => TermsGatePage(controller: controller, onSignOut: onSignOut),
            ),
          ],
        ),
      ),
    );
  }
}

/// The key points of the terms, said at the gate (5–7 lines).
List<String> termsSummary(BuildContext context) => [
      context.tr('Marakaj est une plateforme exploitée par KAJ Consulting LLC : chaque entreprise vend elle-même et répond de ses articles, de ses prix et de ses livraisons.'),
      context.tr('Un compte par personne, avec des informations vraies. Gardez secrets votre mot de passe et vos codes : Marakaj ne les demande jamais.'),
      context.tr('Interdits : la fraude, les fausses commandes, les articles illégaux, contrefaits ou volés, et se faire passer pour quelqu\'un d\'autre.'),
      context.tr('Payez une commande seulement par les moyens convenus dans Marakaj, et ne donnez le code de livraison qu\'à la remise.'),
      context.tr('Les cauris n\'ont pas de valeur en argent ; ceux gagnés par la fraude sont annulés.'),
      context.tr('Marakaj peut vérifier une identité, retirer un contenu et suspendre un compte en cas de fraude ou de plainte.'),
    ];

/// « Engagements du vendeur » (142's seller, version 1): accepted before a
/// business is created — a shop, a farm or an association — and by the
/// owners already here, at the gate.
List<String> sellerCommitments(BuildContext context) => [
      context.tr('Mon activité existe vraiment et elle est légale.'),
      context.tr('Je ne vends rien d\'interdit : ni armes, ni drogues, ni médicaments sans autorisation, ni contrefaçons, ni objets volés.'),
      context.tr('Mes photos, mes prix et mes stocks sont vrais et à jour.'),
      context.tr('J\'honore les commandes que j\'accepte, et je préviens le client en cas de problème.'),
      context.tr('Je ne demande jamais de payer en dehors des moyens convenus dans la commande.'),
      context.tr('Marakaj peut vérifier mon identité et me demander des pièces ; en cas de fraude, mon activité peut être fermée.'),
    ];

/// A titled list of lines with its box to tick: the seller's commitments,
/// the courier's charter, the terms' summary.
class CommitmentsCard extends StatelessWidget {
  const CommitmentsCard({
    super.key,
    required this.title,
    required this.lines,
    required this.checkLabel,
    required this.checked,
    required this.onChanged,
    this.intro,
    this.checkKey,
  });

  final String title;
  final String? intro;
  final List<String> lines;
  final String checkLabel;
  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Key? checkKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (intro != null) ...[
          const SizedBox(height: 4),
          Text(intro!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          decoration: BoxDecoration(
            color: maraPaper,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: maraCaramel.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: 10),
                        child: SizedBox(
                          width: 6,
                          height: 6,
                          child: DecoratedBox(
                              decoration: BoxDecoration(color: maraCaramel, shape: BoxShape.circle)),
                        ),
                      ),
                      Expanded(
                        child: Text(line,
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35, color: maraBlack)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          key: checkKey,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: checked,
          onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
          title: Text(checkLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// The seller's commitments as the creation of a business shows them.
class SellerCommitmentsCard extends StatelessWidget {
  const SellerCommitmentsCard({super.key, required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CommitmentsCard(
        key: const Key('seller-commitments'),
        checkKey: const Key('seller-accept'),
        title: context.tr('Engagements du vendeur'),
        intro: context.tr('Avant de créer votre activité, vous vous engagez à ceci :'),
        lines: sellerCommitments(context),
        checkLabel: context.tr('J\'accepte les engagements du vendeur'),
        checked: checked,
        onChanged: onChanged,
      );
}

/// The gate's page.
class TermsGatePage extends StatefulWidget {
  const TermsGatePage({super.key, required this.controller, required this.onSignOut});

  final TermsController controller;
  final Future<void> Function() onSignOut;

  @override
  State<TermsGatePage> createState() => _TermsGatePageState();
}

class _TermsGatePageState extends State<TermsGatePage> {
  bool _terms = false;
  bool _seller = false;
  bool _courier = false;
  bool _busy = false;
  String? _error;

  List<String> get _gate => widget.controller.gate;
  bool get _asksTerms => _gate.contains(TermsDoc.terms) || _gate.contains(TermsDoc.privacy);
  bool get _asksSeller => _gate.contains(TermsDoc.seller);
  bool get _asksCourier => _gate.contains(TermsDoc.courier);

  bool get _ready =>
      !_busy && (!_asksTerms || _terms) && (!_asksSeller || _seller) && (!_asksCourier || _courier);

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.accept(List.of(_gate));
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _read(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// « 14 octobre 2026 » / « 14 October 2026 », from « 2026-10-14 ».
  String? _date(BuildContext context, String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return null;
    const fr = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
      'septembre', 'octobre', 'novembre', 'décembre'];
    const en = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'];
    final months = context.trLanguage == 'en' ? en : fr;
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.controller.state;
    // « What changed »: the terms asked again after an earlier version — or,
    // when only the seller's commitments or the courier's charter are
    // asked (a new version of those alone), one of them accepted before.
    final changed = _asksTerms
        ? (state?.changed ?? false)
        : _gate.any((d) => (state?.documents[d]?.accepted ?? 0) > 0);
    final changes = changed ? state?.changesIn(context.trLanguage) : null;
    final date = _date(context, state?.date);
    final title = _asksTerms
        ? context.tr('Conditions d\'utilisation')
        : _asksSeller
            ? context.tr('Engagements du vendeur')
            : context.tr('La charte du livreur');
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('terms-gate'),
        appBar: AppBar(automaticallyImplyLeading: false, actions: const [bellRoom], title: Text(title)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      children: [
                        Text(
                          changed
                              ? context.tr('Nos conditions ont changé')
                              : context.tr('Avant de continuer'),
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          changed
                              ? context.tr('Lisez ce qui change, puis acceptez la nouvelle version pour continuer à utiliser Marakaj.')
                              : context.tr('Marakaj protège ses clients et ses entreprises contre la fraude. Lisez l\'essentiel, puis acceptez pour continuer.'),
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (changes != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            key: const Key('terms-changes'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: maraCaramel.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              context.tr('Ce qui change : {changes}', {'changes': changes}),
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: maraBlack),
                            ),
                          ),
                        ],
                        if (_asksTerms) ...[
                          const SizedBox(height: 18),
                          CommitmentsCard(
                            key: const Key('terms-summary'),
                            checkKey: const Key('terms-accept'),
                            title: context.tr('L\'essentiel'),
                            lines: termsSummary(context),
                            checkLabel: context.tr('J\'ai lu et j\'accepte les Conditions d\'utilisation et la Politique de confidentialité'),
                            checked: _terms,
                            onChanged: _busy ? null : (v) => setState(() => _terms = v),
                          ),
                          Wrap(
                            spacing: 4,
                            children: [
                              TextButton.icon(
                                key: const Key('terms-read'),
                                onPressed: () => _read(const TermsScreen()),
                                icon: const Icon(Icons.description_outlined, size: 18),
                                label: Text(context.tr('Lire les Conditions d\'utilisation')),
                              ),
                              TextButton.icon(
                                key: const Key('terms-read-privacy'),
                                onPressed: () => _read(const PrivacyScreen()),
                                icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                                label: Text(context.tr('Lire la Politique de confidentialité')),
                              ),
                            ],
                          ),
                        ],
                        if (_asksSeller) ...[
                          const SizedBox(height: 18),
                          CommitmentsCard(
                            key: const Key('terms-seller'),
                            checkKey: const Key('terms-seller-accept'),
                            title: context.tr('Engagements du vendeur'),
                            intro: context.tr('Vous tenez une activité sur Marakaj : vous vous engagez à ceci.'),
                            lines: sellerCommitments(context),
                            checkLabel: context.tr('J\'accepte les engagements du vendeur'),
                            checked: _seller,
                            onChanged: _busy ? null : (v) => setState(() => _seller = v),
                          ),
                        ],
                        if (_asksCourier) ...[
                          const SizedBox(height: 18),
                          CommitmentsCard(
                            key: const Key('terms-courier'),
                            checkKey: const Key('terms-courier-accept'),
                            title: context.tr('La charte du livreur'),
                            intro: context.tr('Vous livrez avec Marakaj : la charte a changé.'),
                            lines: courierCharter(context),
                            checkLabel: context.tr('J\'ai lu et j\'accepte la charte du livreur'),
                            checked: _courier,
                            onChanged: _busy ? null : (v) => setState(() => _courier = v),
                          ),
                        ],
                        if (date != null && _asksTerms)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              context.tr('Version {n} du {date}',
                                  {'n': state!.version(TermsDoc.terms), 'date': date}),
                              key: const Key('terms-version'),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(_error!,
                      key: const Key('terms-error'), style: TextStyle(color: theme.colorScheme.error)),
                ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        key: const Key('terms-continue'),
                        style: FilledButton.styleFrom(backgroundColor: maraDeep, foregroundColor: maraPaper),
                        onPressed: _ready ? _continue : null,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: maraPaper))
                            : Text(context.tr('Continuer'), style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                  ),
                ),
              ),
              TextButton(
                key: const Key('terms-signout'),
                onPressed: _busy ? null : _signOut,
                child: Text(context.tr('Se déconnecter')),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

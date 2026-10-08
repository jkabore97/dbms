import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/l10n/tr.dart';
import '../../core/phone/country_codes.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/storefront/storefront_repository.dart' show whatsappShareUrl;
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import '../admin/admin_pill.dart';
import '../common/phone_field.dart';
import 'setup_screen.dart';

/// What an association's first setup writes (102), apart so a test can
/// stand in for it.
abstract class AssociationSetupActions {
  Future<void> identify(String orgId,
      {required String name, required String currency, required String kind, required String about});
  Future<void> addMember(String orgId, {required String name, required String phone});
  Future<void> addService(String orgId, {required String name, required double price});
  Future<void> saveVitrine(String orgId,
      {required bool open, required String about, required String phone, required String address});
  Future<void> finish(String orgId);
}

class SupabaseAssociationSetupActions implements AssociationSetupActions {
  SupabaseAssociationSetupActions(this.admin, this.retail, this.invoicing);

  final AdminRepository admin;
  final RetailRepository retail;
  final InvoicingRepository invoicing;

  @override
  Future<void> identify(String orgId,
      {required String name, required String currency, required String kind, required String about}) async {
    await admin.updateOrg(orgId: orgId, name: name, currency: currency);
    await admin.setAssociationKind(orgId, kind: kind, about: about);
  }

  @override
  Future<void> addMember(String orgId, {required String name, required String phone}) =>
      admin.addAssociationMember(orgId, name: name, phone: phone);

  @override
  Future<void> addService(String orgId, {required String name, required double price}) async {
    final id = await retail.ensureProduct(
        orgId: orgId, name: name, salePrice: price, isService: true);
    await retail.updateProduct(id, isPublished: true, isService: true);
  }

  @override
  Future<void> saveVitrine(String orgId,
      {required bool open, required String about, required String phone, required String address}) async {
    // The shop's own (091): the switch and the sentence, and the phone and
    // address on the invoice header, the rest of it kept.
    await SupabaseSetupActions(admin, retail, invoicing).saveVitrine(orgId,
        open: open, blurb: about, phone: phone, address: address);
  }

  @override
  Future<void> finish(String orgId) => admin.finishSetup(orgId);
}

/// One kind of association: its key (orgs.association_kind), its picture,
/// its word and its line.
typedef AssociationKind = ({String key, IconData icon, String name, String line});

List<AssociationKind> associationKinds(BuildContext context) => [
      (
        key: 'tontine',
        icon: Icons.savings_outlined,
        name: context.tr('Tontine'),
        line: context.tr('On cotise, chacun reçoit à son tour.'),
      ),
      (
        key: 'eglise',
        icon: Icons.church_outlined,
        name: context.tr('Église'),
        line: context.tr('Offrandes, dîmes et dons des fidèles.'),
      ),
      (
        key: 'groupement',
        icon: Icons.diversity_3_outlined,
        name: context.tr('Groupement'),
        line: context.tr('On produit et on vend ensemble.'),
      ),
      (
        key: 'culturelle',
        icon: Icons.theater_comedy_outlined,
        name: context.tr('Culturelle'),
        line: context.tr('Danse, musique, fêtes du quartier.'),
      ),
      (
        key: 'sportive',
        icon: Icons.sports_soccer_outlined,
        name: context.tr('Sportive'),
        line: context.tr('Un club, une équipe, ses cotisations.'),
      ),
      (
        key: 'autre',
        icon: Icons.more_horiz,
        name: context.tr('Autre'),
        line: context.tr('Une autre association.'),
      ),
    ];

/// A new association's first minutes (102), drawn as a shop's (091):
/// three steps, each a big picture, a few words and the real form.
///
///  1. Its name, what it is (six kinds, each with its line), a sentence.
///  2. Its first three members — records with a name and a phone, not
///     accounts — and/or a WhatsApp message inviting them. Skippable.
///  3. Optionally, one service on the vitrine, its phone and its area.
///
/// Then « C'est prêt ! »; finishing sets the setup mark, which opens the
/// one free worker (100). No currency question: the business keeps the
/// one it was created with (the country's).
///
/// Mara may turn the optional steps off for every association (107):
/// « members » and « vitrine ». The name and the kind always stay.
class AssociationSetupScreen extends StatefulWidget {
  const AssociationSetupScreen({
    super.key,
    required this.org,
    required this.actions,
    required this.onDone,
    this.stepsOff,
  });

  final OrgSummary org;
  final AssociationSetupActions actions;
  final VoidCallback onDone;

  /// The optional steps turned off for associations, read once as the
  /// setup opens (setup_steps_off, 107). Null or a failure: every step.
  final Future<Set<String>> Function()? stepsOff;

  /// Every step, in order; only 'members' and 'vitrine' can be left out.
  static const steps = ['identity', 'members', 'vitrine'];

  @override
  State<AssociationSetupScreen> createState() => _AssociationSetupScreenState();
}

/// One member's two fields.
class _MemberFields {
  final name = TextEditingController();
  final phone = TextEditingController();
  CountryCode country = defaultCountry;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _AssociationSetupScreenState extends State<AssociationSetupScreen> {
  /// What Mara turned off for associations; nothing until the server says.
  Set<String> _off = const {};

  /// The steps this walkthrough shows, in order.
  List<String> get _keys => [
        for (final k in AssociationSetupScreen.steps)
          if (k == 'identity' || !_off.contains(k)) k,
      ];

  int get _count => _keys.length;

  @override
  void initState() {
    super.initState();
    widget.stepsOff?.call().then((off) {
      // Read while still on the first page: the steps never move under
      // somebody already past it.
      if (mounted && _at == 0 && off.isNotEmpty) setState(() => _off = off);
    });
  }

  final _pages = PageController();
  int _at = 0;
  bool _busy = false;
  String? _error;
  bool _done = false;

  late final _name = TextEditingController(text: widget.org.name);
  String? _kind;
  final _about = TextEditingController();

  final _members = List.generate(3, (_) => _MemberFields());

  /// Members already written, so « Continuer » tapped again adds nobody
  /// twice (the server would merge the same phone anyway).
  int _saved = 0;

  bool _open = true;
  final _service = TextEditingController();
  final _price = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  CountryCode _country = defaultCountry;

  @override
  void dispose() {
    for (final c in [_name, _about, _service, _price, _phone, _address]) {
      c.dispose();
    }
    for (final m in _members) {
      m.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() act, {bool advance = true}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await act();
      if (!mounted) return;
      if (advance) _go(_at + 1);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _go(int page) {
    if (page >= _count) {
      _finish();
      return;
    }
    _pages.animateToPage(page, duration: KajMotion.page, curve: KajMotion.ease);
  }

  Future<void> _finish() => _run(() async {
        await widget.actions.finish(widget.org.id);
        if (mounted) setState(() => _done = true);
      }, advance: false);

  // ---- the three steps' own acts ----

  Future<void> _saveIdentity() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.tr('Le nom, s\'il vous plaît.'));
      return;
    }
    final kind = _kind;
    if (kind == null) {
      setState(() => _error = context.tr('Choisissez ce qu\'elle est.'));
      return;
    }
    await _run(() => widget.actions.identify(widget.org.id,
        name: name, currency: widget.org.currency, kind: kind, about: _about.text.trim()));
  }

  Future<void> _saveMembers() async {
    // Every row typed: a name, and a phone of the right length when there
    // is one. Empty rows are skipped.
    final rows = <({String name, String phone})>[];
    for (final m in _members) {
      final name = m.name.text.trim();
      final typed = m.phone.text.trim();
      if (name.isEmpty && typed.isEmpty) continue;
      if (name.isEmpty) {
        setState(() => _error = context.tr('Le nom du membre, s\'il vous plaît.'));
        return;
      }
      final length = typed.isEmpty ? null : m.country.lengthProblem(typed);
      if (length != null) {
        setState(() => _error = length);
        return;
      }
      rows.add((name: name, phone: typed.isEmpty ? '' : m.country.toE164(typed)));
    }
    await _run(() async {
      for (final r in rows.skip(_saved)) {
        await widget.actions.addMember(widget.org.id, name: r.name, phone: r.phone);
        _saved++;
      }
    });
  }

  /// The WhatsApp message: who invites, to what, and what to send back.
  Future<void> _invite() async {
    final name = _name.text.trim().isEmpty ? widget.org.name : _name.text.trim();
    final text = context.tr(
        'Bonjour ! Je vous inscris comme membre de *{name}* sur Mara. Envoyez-moi votre nom et votre numéro de téléphone.',
        {'name': name});
    try {
      await launchUrl(Uri.parse(whatsappShareUrl(text)),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('WhatsApp ne s\'est pas ouvert.'));
    }
  }

  Future<void> _saveVitrine() async {
    final service = _service.text.trim();
    final price = double.tryParse(
        _price.text.trim().replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.'));
    if (service.isNotEmpty && (price == null || price <= 0)) {
      setState(() => _error = context.tr('Un nom et un prix, s\'il vous plaît.'));
      return;
    }
    final typed = _phone.text.trim();
    final length = typed.isEmpty ? null : _country.lengthProblem(typed);
    if (length != null) {
      setState(() => _error = length);
      return;
    }
    await _run(() async {
      if (service.isNotEmpty) {
        await widget.actions.addService(widget.org.id, name: service, price: price!);
      }
      await widget.actions.saveVitrine(widget.org.id,
          open: _open,
          about: _about.text.trim(),
          phone: typed.isEmpty ? '' : _country.toE164(typed),
          address: _address.text.trim());
      await widget.actions.finish(widget.org.id);
      if (mounted) setState(() => _done = true);
    }, advance: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return SetupReady(org: widget.org, onDone: widget.onDone, association: true);
    }
    final theme = Theme.of(context);
    final all = [
      (
        icon: Icons.volunteer_activism,
        title: context.tr('Votre association'),
        line: context.tr('Son nom, et ce qu\'elle est.'),
        body: _identity(theme),
      ),
      (
        icon: Icons.groups_2_outlined,
        title: context.tr('Vos premiers membres'),
        line: context.tr('Trois pour commencer : un nom, un téléphone.'),
        body: _membersStep(theme),
      ),
      (
        icon: Icons.storefront_outlined,
        title: context.tr('Votre vitrine'),
        line: context.tr('Un service, votre téléphone, votre quartier.'),
        body: _vitrineStep(theme),
      ),
    ];
    final steps = [
      for (final (i, k) in AssociationSetupScreen.steps.indexed)
        if (_keys.contains(k)) all[i],
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const MaraMark(size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tr('Mise en route'),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Text('${_at + 1} / $_count',
                      key: const Key('asetup-count'),
                      style: theme.textTheme.labelLarge),
                  // « Admin » (104): the platform's way to its center, here too
                  // — drawn for a platform admin only.
                  const AdminPill(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  for (var i = 0; i < _count; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: KajMotion.quick,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 6,
                        decoration: BoxDecoration(
                          color: i <= _at ? maraCaramel : maraDeep.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                key: const Key('asetup-pages'),
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() {
                  _at = i;
                  _error = null;
                }),
                children: [
                  for (final (i, s) in steps.indexed)
                    ListView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                      children: [
                        Center(child: SetupPicture(icon: s.icon, key: ValueKey('asetup-pic-$i'))),
                        const SizedBox(height: 16),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(s.line, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 22),
                        ...s.body,
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              key: const Key('asetup-error'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.error)),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primary(String label, VoidCallback? onPressed,
          {Key? key, IconData icon = Icons.arrow_forward}) =>
      SizedBox(
        height: 56,
        child: FilledButton.icon(
          key: key,
          onPressed: _busy ? null : onPressed,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 17)),
        ),
      );

  List<Widget> _identity(ThemeData theme) => [
        TextField(
          key: const Key('asetup-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: context.tr('Nom de l\'association'),
            prefixIcon: const Icon(Icons.badge_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        for (final k in associationKinds(context))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _KindTile(
              kind: k,
              selected: _kind == k.key,
              onTap: () => setState(() {
                _kind = k.key;
                _error = null;
              }),
            ),
          ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('asetup-about'),
          controller: _about,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: context.tr('En une phrase (facultatif)'),
            hintText: context.tr('Ex. : L\'entraide des femmes de Gounghin'),
            prefixIcon: const Icon(Icons.short_text),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _primary(context.tr('Continuer'), _saveIdentity, key: const Key('asetup-next-0')),
      ];

  List<Widget> _membersStep(ThemeData theme) => [
        for (final (i, m) in _members.indexed) ...[
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: maraCaramel,
                child: Text('${i + 1}',
                    style: const TextStyle(color: maraDeep, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: Key('asetup-member-$i'),
                  controller: m.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('Nom'),
                    prefixIcon: const Icon(Icons.person_outline),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: PhoneField(
              key: Key('asetup-member-phone-$i'),
              controller: m.phone,
              country: m.country,
              onCountry: (c) => setState(() => m.country = c),
              labelText: context.tr('Téléphone'),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(context.tr('Des membres, pas des comptes : gratuits, sans Pro.'),
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const Key('asetup-whatsapp'),
          onPressed: _busy ? null : _invite,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: maraGreen,
            side: const BorderSide(color: maraGreen),
          ),
          icon: const Icon(Icons.chat_outlined),
          label: Text(context.tr('Inviter sur WhatsApp')),
        ),
        const SizedBox(height: 12),
        _primary(context.tr('Continuer'), _saveMembers, key: const Key('asetup-next-1')),
        TextButton(
          key: const Key('asetup-skip-1'),
          onPressed: _busy ? null : () => _go(_at + 1),
          child: Text(context.tr('Passer')),
        ),
      ];

  List<Widget> _vitrineStep(ThemeData theme) => [
        SwitchListTile(
          key: const Key('asetup-open'),
          value: _open,
          onChanged: (v) => setState(() => _open = v),
          secondary: const Icon(Icons.storefront),
          title: Text(context.tr('Ouvrir ma vitrine')),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('asetup-service'),
          controller: _service,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.tr('Un service (facultatif)'),
            hintText: context.tr('Ex. : Location de la salle'),
            prefixIcon: const Icon(Icons.handshake_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('asetup-price'),
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.tr('Prix (F)'),
            prefixIcon: const Icon(Icons.sell_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        PhoneField(
          key: const Key('asetup-phone'),
          controller: _phone,
          country: _country,
          onCountry: (c) => setState(() => _country = c),
          labelText: context.tr('Téléphone de l\'association'),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('asetup-address'),
          controller: _address,
          decoration: InputDecoration(
            labelText: context.tr('Quartier, repère'),
            prefixIcon: const Icon(Icons.home_work_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        _primary(context.tr('Terminer'), _saveVitrine,
            key: const Key('asetup-next-2'), icon: Icons.check),
        TextButton(
          key: const Key('asetup-later'),
          onPressed: _busy ? null : _finish,
          child: Text(context.tr('Plus tard')),
        ),
      ];
}

/// One kind: a big picture, its word and its line; caramel when chosen.
class _KindTile extends StatelessWidget {
  const _KindTile({required this.kind, required this.selected, required this.onTap});

  final AssociationKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? maraDeep : maraPaper,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('asetup-kind-${kind.key}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? maraCaramel : maraDeep.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(kind.icon, color: maraDeep, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: selected ? maraPaper : maraDeep)),
                    Text(kind.line,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: selected ? maraPaper.withValues(alpha: 0.85) : null)),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: maraCaramel),
            ],
          ),
        ),
      ),
    );
  }
}

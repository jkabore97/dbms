import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/admin/admin_repository.dart';
import '../../core/admin/setup_steps.dart';
import '../../core/auth/models.dart';
import '../../core/errors.dart';
import '../../core/invoicing/invoicing_repository.dart';
import '../../core/nav/app_scope.dart';
import '../../core/phone/country_codes.dart';
import '../../core/retail/retail_repository.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import '../admin/admin_pill.dart';
import '../admin/pin_preview.dart';
import '../common/phone_field.dart';
import '../notify/push_prompt.dart' show PushPromptQuiet;
import 'package:kaj_app/core/l10n/tr.dart';
import 'association_setup_screen.dart';

/// What the first setup writes (091), apart so a test can stand in for it.
abstract class SetupActions {
  Future<void> rename(String orgId, String name, String currency);
  Future<void> addArticle(String orgId,
      {required String name, required double price, required double quantity});
  Future<void> saveVitrine(String orgId,
      {required bool open, required String blurb, required String phone, required String address});
  Future<void> savePosition(String orgId, double lat, double lng);
  Future<void> finish(String orgId);
}

class SupabaseSetupActions implements SetupActions {
  SupabaseSetupActions(this.admin, this.retail, this.invoicing);

  final AdminRepository admin;
  final RetailRepository retail;
  final InvoicingRepository invoicing;

  @override
  Future<void> rename(String orgId, String name, String currency) =>
      admin.updateOrg(orgId: orgId, name: name, currency: currency);

  @override
  Future<void> addArticle(String orgId,
      {required String name, required double price, required double quantity}) async {
    final id = await retail.ensureProduct(orgId: orgId, name: name, salePrice: price);
    if (quantity > 0) {
      await retail.receive(orgId: orgId, productId: id, quantity: quantity);
    }
    await retail.updateProduct(id, isPublished: true);
  }

  @override
  Future<void> saveVitrine(String orgId,
      {required bool open, required String blurb, required String phone, required String address}) async {
    await admin.setStorefront(orgId, enabled: open, blurb: blurb);
    // The invoice header carries the same phone and address; what was
    // there is kept, only these two lines are set.
    final b = await invoicing.billingDetails(orgId);
    await invoicing.saveBillingDetails(
      orgId: orgId,
      address: address,
      phone: phone,
      email: b.email,
      taxId: b.taxId,
      taxLabel: b.taxLabel,
      footer: b.footer,
    );
  }

  @override
  Future<void> savePosition(String orgId, double lat, double lng) =>
      admin.setStorefrontLocation(orgId, lat: lat, lng: lng);

  @override
  Future<void> finish(String orgId) => admin.finishSetup(orgId);
}

/// One step of the first setup: its picture, its name, one line.
typedef _Step = ({IconData icon, String title, String line});

/// A new shop's or farm's first minutes (091): four steps, each a big
/// picture, a few words and the real form — the business is set up for
/// real while its owner learns where everything is. The store opens once
/// it has its first article; the position may wait (« Plus tard »), and
/// earns no cauris until it is set.
///
/// Mara may turn the optional steps off for every shop or every farm
/// (107): « vitrine » and « position ». The name and the first article
/// always stay.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.org,
    required this.actions,
    required this.onDone,
    this.stepsOff,
    this.known,
  });

  final OrgSummary org;
  final SetupActions actions;
  final VoidCallback onDone;

  /// The optional steps turned off for this kind, read once as the setup
  /// opens (setup_steps_off, 107). Null or a failure: every step.
  final Future<Set<String>> Function()? stepsOff;

  /// What the business already says — its phone, area and sentence, given
  /// when it was created (111) — read once: the vitrine step starts from it
  /// rather than empty (an empty line would clear it on saving).
  final Future<SetupKnown?> Function()? known;

  /// Every step, in order; only 'vitrine' and 'position' can be left out.
  static const steps = ['identity', 'article', 'vitrine', 'position'];

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pages = PageController();
  int _at = 0;
  bool _busy = false;
  String? _error;

  late final _name = TextEditingController(text: widget.org.name);
  final _article = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  int _articles = 0;
  bool _open = true;
  final _blurb = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  CountryCode _country = defaultCountry;
  (double, double)? _pin;
  bool _done = false;

  /// What Mara turned off for this kind; nothing until the server says.
  Set<String> _off = const {};

  @override
  void initState() {
    super.initState();
    widget.stepsOff?.call().then((off) {
      // Read while still on the first page: the steps never move under
      // somebody already past it.
      if (mounted && _at == 0 && off.isNotEmpty) setState(() => _off = off);
    });
    widget.known?.call().then((k) {
      // Only into what is still empty: nothing typed is written over.
      if (!mounted || k == null) return;
      setState(() {
        if (_blurb.text.isEmpty) _blurb.text = k.about ?? '';
        if (_address.text.isEmpty) _address.text = k.address ?? '';
        final phone = k.phone;
        if (_phone.text.isEmpty && phone != null) {
          _country = countryOfNumber(phone) ?? _country;
          _phone.text = _country.localPart(phone);
        }
      });
    });
  }

  /// The steps this walkthrough shows, in order.
  List<String> get _keys => [
        for (final k in SetupScreen.steps)
          if (k == 'identity' || k == 'article' || !_off.contains(k)) k,
      ];

  bool get _farm => widget.org.profile == 'farm';

  List<_Step> get _steps => [for (final k in _keys) _stepOf(k)];

  _Step _stepOf(String key) => switch (key) {
        'identity' => (
          icon: _farm ? Icons.agriculture : Icons.storefront,
          title: _farm ? context.tr('Votre ferme') : context.tr('Votre boutique'),
          line: context.tr('Son nom, tel que vos clients le connaissent.'),
        ),
        'article' => (
          icon: Icons.inventory_2,
          title: _farm ? context.tr('Ce que vous vendez') : context.tr('Votre premier article'),
          line: context.tr('Un nom, un prix, combien vous en avez.'),
        ),
        'vitrine' => (
          icon: Icons.storefront_outlined,
          title: context.tr('Votre vitrine'),
          line: context.tr('Votre page, à partager sur WhatsApp.'),
        ),
        // The business's own place, said as the owner says it (108).
        _ => (
          icon: Icons.place,
          title: _farm
              ? context.tr('La position de ma ferme')
              : context.tr('La position de ma boutique'),
          line: context.tr('Vos clients vous voient sur la carte.'),
        ),
      };

  @override
  void dispose() {
    for (final c in [_name, _article, _price, _quantity, _blurb, _phone, _address]) {
      c.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.'));

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
    if (page >= _steps.length) {
      _finish();
      return;
    }
    _pages.animateToPage(page, duration: KajMotion.page, curve: KajMotion.ease);
  }

  Future<void> _finish() async {
    await _run(() async {
      await widget.actions.finish(widget.org.id);
      if (mounted) setState(() => _done = true);
    }, advance: false);
  }

  // ---- the four steps' own acts ----

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.tr('Le nom, s\'il vous plaît.'));
      return;
    }
    await _run(() => widget.actions.rename(widget.org.id, name, widget.org.currency));
  }

  Future<void> _addArticle() async {
    final name = _article.text.trim();
    final price = _num(_price);
    final qty = _num(_quantity) ?? 0;
    if (name.isEmpty || price == null || price <= 0) {
      setState(() => _error = context.tr('Un nom et un prix.'));
      return;
    }
    await _run(() async {
      await widget.actions.addArticle(widget.org.id,
          name: name, price: price, quantity: qty);
      if (!mounted) return;
      setState(() {
        _articles++;
        _article.clear();
        _price.clear();
        _quantity.clear();
      });
    }, advance: false);
  }

  Future<void> _saveVitrine() async {
    final typed = _phone.text.trim();
    final length = typed.isEmpty ? null : _country.lengthProblem(typed);
    if (length != null) {
      setState(() => _error = length);
      return;
    }
    await _run(() => widget.actions.saveVitrine(widget.org.id,
        open: _open,
        blurb: _blurb.text.trim(),
        phone: typed.isEmpty ? '' : _country.toE164(typed),
        address: _address.text.trim()));
  }

  Future<void> _locate() async {
    await _run(() async {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Autorisez la position, ou choisissez « Plus tard ».';
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) setState(() => _pin = (p.latitude, p.longitude));
    }, advance: false);
  }

  Future<void> _savePosition() async {
    final pin = _pin;
    if (pin == null) return;
    await _run(() => widget.actions.savePosition(widget.org.id, pin.$1, pin.$2));
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return SetupReady(org: widget.org, onDone: widget.onDone);
    final theme = Theme.of(context);
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
                  Text('${_at + 1} / ${_steps.length}',
                      key: const Key('setup-count'),
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
                  for (var i = 0; i < _steps.length; i++)
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
                key: const Key('setup-pages'),
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() {
                  _at = i;
                  _error = null;
                }),
                children: [
                  for (final (i, k) in _keys.indexed)
                    _page(i, switch (k) {
                      'identity' => _identity(theme),
                      'article' => _articleStep(theme),
                      'vitrine' => _vitrineStep(theme),
                      _ => _positionStep(theme),
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(int i, List<Widget> body) {
    final theme = Theme.of(context);
    final s = _steps[i];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Center(child: SetupPicture(icon: s.icon, key: ValueKey('setup-pic-$i'))),
        const SizedBox(height: 16),
        Text(s.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(s.line, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 22),
        ...body,
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              key: const Key('setup-error'),
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  Widget _primary(String label, VoidCallback? onPressed, {Key? key, IconData icon = Icons.arrow_forward}) =>
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
          key: const Key('setup-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: _farm ? context.tr('Nom de la ferme') : context.tr('Nom de la boutique'),
            prefixIcon: const Icon(Icons.badge_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        _primary(context.tr('Continuer'), _saveName, key: const Key('setup-next-0')),
      ];

  List<Widget> _articleStep(ThemeData theme) => [
        // How it is done, before doing it: the three things an article
        // needs, lit one after the other.
        const _HowTo(items: [
          (Icons.label_outline, 'Nom'),
          (Icons.sell_outlined, 'Prix'),
          (Icons.inventory_outlined, 'Stock'),
        ]),
        const SizedBox(height: 18),
        TextField(
          key: const Key('setup-article'),
          controller: _article,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: _farm ? context.tr('Ex. : Plateau d\'œufs') : context.tr('Ex. : Sac de riz 25 kg'),
            prefixIcon: const Icon(Icons.label_outline),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('setup-price'),
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('Prix (F)'),
                  prefixIcon: const Icon(Icons.sell_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const Key('setup-quantity'),
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('En stock'),
                  prefixIcon: const Icon(Icons.inventory_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_articles == 0)
          _primary(context.tr('Ajouter'), _addArticle, key: const Key('setup-add'), icon: Icons.add)
        else
          OutlinedButton.icon(
            key: const Key('setup-add'),
            onPressed: _busy ? null : _addArticle,
            icon: const Icon(Icons.add),
            label: Text(context.tr('Ajouter encore')),
          ),
        if (_articles > 0) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: maraGreen),
              const SizedBox(width: 6),
              Text('$_articles article${_articles > 1 ? 's' : ''} sur la vitrine',
                  key: const Key('setup-articles'),
                  style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(context.tr('Plus tard : Stock › « + ».'),
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          _primary(context.tr('Continuer'), () => _go(_at + 1), key: const Key('setup-next-1')),
        ],
      ];

  List<Widget> _vitrineStep(ThemeData theme) => [
        SwitchListTile(
          key: const Key('setup-open'),
          value: _open,
          onChanged: (v) => setState(() => _open = v),
          secondary: const Icon(Icons.storefront),
          title: Text(context.tr('Ouvrir ma vitrine')),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('setup-blurb'),
          controller: _blurb,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: context.tr('En une phrase'),
            hintText: context.tr('Ex. : Le riz et l\'huile du quartier'),
            prefixIcon: const Icon(Icons.short_text),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        PhoneField(
          key: const Key('setup-phone'),
          controller: _phone,
          country: _country,
          onCountry: (c) => setState(() => _country = c),
          labelText: context.tr('Téléphone des clients'),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('setup-address'),
          controller: _address,
          decoration: InputDecoration(
            labelText: context.tr('Quartier, repère'),
            prefixIcon: const Icon(Icons.home_work_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        _primary(context.tr('Continuer'), _saveVitrine, key: const Key('setup-next-2')),
      ];

  List<Widget> _positionStep(ThemeData theme) => [
        if (_pin == null)
          OutlinedButton.icon(
            key: const Key('setup-locate'),
            onPressed: _busy ? null : _locate,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.my_location),
            label: Text(context.tr('Utiliser ma position')),
          )
        else ...[
          PinPreview(
            lat: _pin!.$1,
            lng: _pin!.$2,
            currency: widget.org.currency,
            onMove: (lat, lng) => setState(() => _pin = (lat, lng)),
          ),
          const SizedBox(height: 16),
          _primary(context.tr('Terminer'), _savePosition,
              key: const Key('setup-next-3'), icon: Icons.check),
        ],
        const SizedBox(height: 12),
        TextButton(
          key: const Key('setup-later'),
          onPressed: _busy ? null : _finish,
          child: Text(context.tr('Plus tard')),
        ),
        Text(context.tr('Sans position, pas de cauris de vitrine complète.'),
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ];
}

/// The step's picture: a big tile that grows in.
class SetupPicture extends StatelessWidget {
  const SetupPicture({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final reduced = KajMotion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0.6, end: 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: maraDeep,
          borderRadius: BorderRadius.circular(36),
        ),
        child: Icon(icon, size: 64, color: maraCaramel),
      ),
    );
  }
}

/// « How it is done »: a row of pictures lit one after another, on a loop.
class _HowTo extends StatefulWidget {
  const _HowTo({required this.items});

  final List<(IconData, String)> items;

  @override
  State<_HowTo> createState() => _HowToState();
}

class _HowToState extends State<_HowTo> with SingleTickerProviderStateMixin {
  late final _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KajMotion.reduced(context)) {
      _loop.value = 1;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.items.length;
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final lit = (_loop.value * (n + 1)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0)
                Icon(Icons.arrow_forward,
                    size: 18, color: i <= lit ? maraDeep : maraDeep.withValues(alpha: 0.2)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: KajMotion.quick,
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: i < lit ? maraCaramel : maraDeep.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(widget.items[i].$1,
                          color: i < lit ? maraDeep : maraDeep.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.items[i].$2, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// « C'est prêt ! »: the business opens — the shop, the farm, or the
/// association (102), each said in its own word (120: a farm finishing its
/// setup was told « Ouvrir ma boutique »).
class SetupReady extends StatelessWidget {
  const SetupReady({super.key, required this.org, required this.onDone});

  final OrgSummary org;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (ready, open, icon) = org.isAssociation
        ? (context.tr('Votre association est prête'), context.tr('Ouvrir mon association'), Icons.volunteer_activism)
        : org.profile == 'farm'
            ? (context.tr('Votre ferme est prête'), context.tr('Ouvrir ma ferme'), Icons.agriculture)
            : (context.tr('Votre boutique est prête'), context.tr('Ouvrir ma boutique'), Icons.storefront);
    return Scaffold(
      backgroundColor: maraDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SetupPicture(icon: Icons.celebration)),
              const SizedBox(height: 20),
              Text(context.tr('C\'est prêt !'),
                  key: const Key('setup-ready'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(color: maraPaper, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(ready,
                  key: const Key('setup-ready-kind'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: maraPaper)),
              const SizedBox(height: 4),
              Text(org.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: maraCaramel)),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  key: const Key('setup-enter'),
                  style: FilledButton.styleFrom(
                      backgroundColor: maraCaramel, foregroundColor: maraDeep),
                  onPressed: onDone,
                  icon: Icon(icon),
                  label: Text(open, style: const TextStyle(fontSize: 17)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Holds the home back until the first setup is done (091, and 102 for an
/// association): the business's admins see the setup; an employee, or a
/// business already set up, the home. Until the server has answered, the
/// home shows — the app never blocks on a slow network.
///
/// An association is held only when its team says so too: before 102 the
/// server called every association set up there (100's org_setup_done)
/// while 'setup_done' read the bare column, so an association created
/// after 091 would otherwise be walked through against a database that
/// cannot take its answers.
class SetupGate extends StatelessWidget {
  const SetupGate({super.key, required this.org, required this.child});

  final OrgSummary org;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    if (scope == null || !org.isAdmin) return child;
    return ListenableBuilder(
      listenable: scope.session,
      builder: (context, _) {
        final f = scope.session.featuresFor(org.id);
        if (f == null || f.setupDone) return child;
        if (org.isAssociation) {
          if (f.team == null || f.team!.setupDone) return child;
          // A first setup is never interrupted by « Activer les
          // notifications ? » (120): asked once it is done.
          return PushPromptQuiet(child: AssociationSetupScreen(
            org: org,
            actions: SupabaseAssociationSetupActions(scope.admin, scope.retail, scope.invoicing),
            onDone: () => scope.session.reloadFeatures(org.id),
            stepsOff: () => setupStepsOff(scope.auth.client, org.id),
            known: () => setupKnown(scope.auth.client, org.id),
          ));
        }
        return PushPromptQuiet(child: SetupScreen(
          org: org,
          actions: SupabaseSetupActions(scope.admin, scope.retail, scope.invoicing),
          onDone: () => scope.session.reloadFeatures(org.id),
          stepsOff: () => setupStepsOff(scope.auth.client, org.id),
          known: () => setupKnown(scope.auth.client, org.id),
        ));
      },
    );
  }
}

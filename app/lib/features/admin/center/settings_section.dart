import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/console/command_center.dart';
import '../../../core/errors.dart';
import '../../../core/format/money.dart' show parseAmount;
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../../core/nav/router.dart';
import '../../notify/push_check.dart';
import '../../../core/theme/kaj_card.dart';
import '../../../core/theme/mara_mark.dart';
import 'todo_section.dart' show featureName;
import '../../../core/notify/bell_room.dart';

/// How a setting is typed in.
enum SettingType {
  /// An amount of money (a whole number, but see [decimalSettings]).
  money,

  /// A whole number of things, days or minutes.
  count,

  /// A distance in km.
  km,

  /// A percentage, 0 to 100.
  pct,

  /// Oui / non.
  flag,

  /// Oui / non kept as 1 / 0.
  flag01,

  /// A few words.
  text,

  /// A currency's three letters.
  currency,

  /// A list of words from [SettingDef.options].
  list,
}

class SettingDef {
  const SettingDef(this.key, this.group, this.type, {this.options = const []});

  final String key;
  final String group;
  final SettingType type;
  final List<String> options;
}

/// Réglages: the platform settings the app uses, each with its name. The
/// server checks every value (105's platform_set_setting); test_batch105's
/// TEST 7 proves each of these keys is read by the server, and
/// test/command_center_test.dart that the two lists are the same. Three
/// settings nothing reads since 097 (progress_tools_pct, progress_orders,
/// progress_trial_days) are left out on purpose.
const platformSettingDefs = <SettingDef>[
  SettingDef('pro_price_month', 'pro', SettingType.money),
  SettingDef('pro_price_year', 'pro', SettingType.money),
  SettingDef('pro_currency', 'pro', SettingType.currency),
  SettingDef('platform_wave', 'pro', SettingType.text),
  SettingDef('platform_wave_name', 'pro', SettingType.text),
  SettingDef('stripe_on', 'pro', SettingType.flag),
  SettingDef('pro_features', 'pro', SettingType.list, options: [
    'payroll', 'team_access', 'analytics', 'accounting', 'currencies', 'tontines',
    'vitrine_plus', 'delivery', 'online_payment',
  ]),
  SettingDef('free_max_staff', 'free', SettingType.count),
  SettingDef('free_max_invoices_month', 'free', SettingType.count),
  SettingDef('free_max_photos', 'free', SettingType.count),
  SettingDef('free_photo_items', 'free', SettingType.count),
  SettingDef('free_history_months', 'free', SettingType.count),
  SettingDef('vitrine_free_basics', 'free', SettingType.flag01),
  SettingDef('vitrine_min_items', 'street', SettingType.count),
  SettingDef('vitrine_min_items_association', 'street', SettingType.count),
  SettingDef('progress_street_pct', 'street', SettingType.pct),
  SettingDef('spots_max_live', 'street', SettingType.count),
  SettingDef('pro_free_spots_month', 'street', SettingType.count),
  SettingDef('spot_price_article_7', 'street', SettingType.money),
  SettingDef('spot_price_article_30', 'street', SettingType.money),
  SettingDef('spot_price_shop_7', 'street', SettingType.money),
  SettingDef('spot_price_shop_30', 'street', SettingType.money),
  SettingDef('delivery_base', 'delivery', SettingType.money),
  SettingDef('delivery_per_km', 'delivery', SettingType.money),
  SettingDef('delivery_currency', 'delivery', SettingType.currency),
  SettingDef('delivery_max_km', 'delivery', SettingType.km),
  SettingDef('delivery_included_km', 'delivery', SettingType.km),
  SettingDef('delivery_share_pct', 'delivery', SettingType.pct),
  SettingDef('own_courier_minutes', 'delivery', SettingType.count),
  SettingDef('stuck_ready_minutes', 'delivery', SettingType.count),
  // 112: what a courier's dossier asks — the licence for a moto or a car,
  // and a number proved on WhatsApp (off until 109's code is set up).
  SettingDef('courier_licence_required', 'delivery', SettingType.flag),
  SettingDef('courier_phone_verified', 'delivery', SettingType.flag),
  SettingDef('wave_checkout', 'wave', SettingType.flag),
  SettingDef('wave_card', 'wave', SettingType.flag),
  SettingDef('wave_commission_pct', 'wave', SettingType.pct),
  SettingDef('cauris_order_min', 'cauris', SettingType.money),
  SettingDef('cauris_orders_per_customer', 'cauris', SettingType.count),
  SettingDef('cauris_quick_minutes', 'cauris', SettingType.count),
  SettingDef('cauris_expire_days', 'cauris', SettingType.count),
  SettingDef('cauris_unlock_days', 'cauris', SettingType.count),
  SettingDef('cauris_prize_1', 'cauris', SettingType.count),
  SettingDef('cauris_prize_2', 'cauris', SettingType.count),
  SettingDef('cauris_prize_3', 'cauris', SettingType.count),
  SettingDef('league_small_max', 'cauris', SettingType.count),
  SettingDef('league_medium_max', 'cauris', SettingType.count),
  SettingDef('path_league_min', 'cauris', SettingType.count),
  SettingDef('progress_credit_orders', 'cauris', SettingType.count),
  SettingDef('path_gates_open', 'cauris', SettingType.flag01),
  // Shown, and changed where it always was: Compte › Sécurité (078).
  SettingDef('admin_two_step', 'security', SettingType.flag),
  // 109: a number proved on WhatsApp before an order — off until the
  // WhatsApp code Worker and Supabase's hook are set up.
  SettingDef('order_phone_verified', 'orders', SettingType.flag),
  // 111: a number proved on WhatsApp before a business is created — off,
  // as 109's, until the same Worker and hook are set up.
  SettingDef('create_phone_verified', 'creation', SettingType.flag),
  // 113: the help number of the shopper's « Écrire à Mara sur WhatsApp »;
  // empty, the row is not drawn.
  SettingDef('support_whatsapp', 'help', SettingType.text),
];

String settingGroupLabel(BuildContext context, String group) => switch (group) {
      'pro' => context.tr('Mara Pro'),
      'free' => context.tr('Sans Pro'),
      'street' => context.tr('Vitrines et rue'),
      'delivery' => context.tr('Livraison'),
      'wave' => context.tr('Paiements Wave'),
      'cauris' => context.tr('Cauris, ligues et Chemin'),
      'security' => context.tr('Sécurité de la plateforme'),
      'orders' => context.tr('Commandes de la rue'),
      'creation' => context.tr('Création d\'activité'),
      'help' => context.tr('Aide aux clients'),
      _ => group,
    };

String settingLabel(BuildContext context, String key) => switch (key) {
      'pro_price_month' => context.tr('Prix de Mara Pro, par mois'),
      'pro_price_year' => context.tr('Prix de Mara Pro, par an'),
      'pro_currency' => context.tr('Monnaie des prix de Mara Pro'),
      'platform_wave' => context.tr('Numéro Wave qui reçoit les paiements Pro'),
      'platform_wave_name' => context.tr('Nom du compte Wave de Mara'),
      'stripe_on' => context.tr('Abonnement par carte (Stripe)'),
      'pro_features' => context.tr('Outils réservés à Mara Pro'),
      'free_max_staff' => context.tr('Personnes dans l\'équipe'),
      'free_max_invoices_month' => context.tr('Factures par mois'),
      'free_max_photos' => context.tr('Photos en tout'),
      'free_photo_items' => context.tr('Articles avec photo'),
      'free_history_months' => context.tr('Mois d\'historique'),
      'vitrine_free_basics' => context.tr('Habillage de base de la vitrine pour tous'),
      'vitrine_min_items' => context.tr('Articles pour paraître dans la rue (boutique, ferme)'),
      'vitrine_min_items_association' =>
        context.tr('Articles ou services pour paraître dans la rue (association)'),
      'progress_street_pct' => context.tr('Vitrine remplie à … % pour paraître dans la rue'),
      'spots_max_live' => context.tr('Mises en avant en même temps'),
      'pro_free_spots_month' => context.tr('Mises en avant offertes chaque mois avec Pro'),
      'spot_price_article_7' => context.tr('Un article à la une, 7 jours'),
      'spot_price_article_30' => context.tr('Un article à la une, 30 jours'),
      'spot_price_shop_7' => context.tr('La boutique à la une, 7 jours'),
      'spot_price_shop_30' => context.tr('La boutique à la une, 30 jours'),
      'delivery_base' => context.tr('Livraison : prise en charge'),
      'delivery_per_km' => context.tr('Livraison : par kilomètre'),
      'delivery_currency' => context.tr('Monnaie des prix de livraison'),
      'delivery_max_km' => context.tr('Distance de livraison la plus longue (km)'),
      'delivery_included_km' => context.tr('Kilomètres offerts avec Pro'),
      'delivery_share_pct' => context.tr('Part de Mara sur chaque livraison (%)'),
      'own_courier_minutes' => context.tr('Minutes réservées aux livreurs de la boutique'),
      'stuck_ready_minutes' => context.tr('Minutes avant de signaler une commande prête'),
      'courier_licence_required' => context.tr('Permis de conduire obligatoire pour livrer à moto ou en voiture'),
      'courier_phone_verified' => context.tr('Numéro WhatsApp vérifié pour devenir livreur'),
      'wave_checkout' => context.tr('Payer en ligne par Wave'),
      'wave_card' => context.tr('Carte bancaire sur la page Wave'),
      'wave_commission_pct' => context.tr('Commission de Mara sur une commande payée en ligne (%)'),
      'cauris_order_min' => context.tr('Commande la plus petite qui rapporte des cauris'),
      'cauris_orders_per_customer' => context.tr('Commandes par client et par jour qui comptent'),
      'cauris_quick_minutes' => context.tr('Minutes pour une commande acceptée vite'),
      'cauris_expire_days' => context.tr('Jours sans mouvement avant que les cauris expirent'),
      'cauris_unlock_days' => context.tr('Jours d\'ouverture d\'un outil acheté en cauris'),
      'cauris_prize_1' => context.tr('Cauris pour la 1re place de la semaine'),
      'cauris_prize_2' => context.tr('Cauris pour la 2e place'),
      'cauris_prize_3' => context.tr('Cauris pour la 3e place'),
      'league_small_max' => context.tr('Petite ligue : moins de … commandes en 30 jours'),
      'league_medium_max' => context.tr('Ligue moyenne : moins de … commandes en 30 jours'),
      'path_league_min' => context.tr('Entreprises dans une ligue avant le classement'),
      'progress_credit_orders' => context.tr('Commandes terminées pour ouvrir le carnet de crédit'),
      'path_gates_open' => context.tr('Ouvrir tous les outils du Chemin à tout le monde'),
      'admin_two_step' => context.tr('Validation en deux étapes du compte de la plateforme'),
      'order_phone_verified' => context.tr('Numéro WhatsApp vérifié avant de commander'),
      'create_phone_verified' => context.tr('Numéro WhatsApp vérifié avant de créer une activité'),
      'support_whatsapp' => context.tr('Numéro WhatsApp de l\'aide Mara (vide : caché)'),
      _ => key,
    };

/// The only numbers that take a decimal: every reader of these takes it
/// as numeric (the delivery fee and reach, the Wave commission). Every
/// other number is read as an integer by the server, which refuses
/// « 12.5 » there (105's platform_set_setting) — said here first.
const decimalSettings = {
  'delivery_base',
  'delivery_per_km',
  'delivery_max_km',
  'delivery_included_km',
  'wave_commission_pct',
};

/// The largest number any setting takes (105's platform_set_setting).
const settingMax = 1000000000;

/// The value as a person reads it.
String settingValueText(BuildContext context, SettingDef def, Object? v) {
  num? n = v is num ? v : num.tryParse('${v ?? ''}');
  final f = NumberFormat.decimalPattern('fr_FR');
  return switch (def.type) {
    SettingType.flag => v == true ? context.tr('Oui') : context.tr('Non'),
    SettingType.flag01 => (n ?? 0) > 0 ? context.tr('Oui') : context.tr('Non'),
    SettingType.pct => n == null ? '—' : '${f.format(n)} %',
    SettingType.km => n == null ? '—' : '${f.format(n)} km',
    SettingType.money || SettingType.count => n == null ? '—' : f.format(n),
    SettingType.list => v is List
        ? (v.isEmpty ? '—' : v.map((e) => featureName(context, '$e')).join(', '))
        : '—',
    SettingType.text || SettingType.currency =>
      (v == null || '$v'.trim().isEmpty) ? context.tr('(vide)') : '$v',
  };
}

/// Réglages (105): every setting, by group, with who changed it last.
/// A change is journaled with its « Annuler ». The two-step switch is
/// shown here and changed in Sécurité, where its explanation is.
class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key, required this.center});

  final CommandCenterRepository center;

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  Map<String, SettingValue>? _values;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await widget.center.settings();
      if (!mounted) return;
      setState(() {
        _values = v;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _save(SettingDef def, Object value) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('{name} : enregistré.', {'name': settingLabel(context, def.key)});
    final undoLabel = context.tr('Annuler');
    setState(() => _busy = def.key);
    try {
      final id = await widget.center.setSetting(def.key, value);
      await _load();
      messenger.showSnackBar(SnackBar(
        content: Text(saved),
        action: id == null
            ? null
            : SnackBarAction(
                label: undoLabel,
                onPressed: () async {
                  try {
                    await widget.center.undo(id);
                    await _load();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
                  }
                },
              ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _edit(SettingDef def, Object? current) async {
    final value = await showDialog<Object>(
      context: context,
      builder: (_) => _EditDialog(def: def, current: current),
    );
    if (value != null && mounted) await _save(def, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = _values;
    final groups = <String>[];
    for (final d in platformSettingDefs) {
      if (!groups.contains(d.group)) groups.add(d.group);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Réglages')),
        actions: [
          IconButton(
            tooltip: context.tr('Actualiser'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          bellRoom,
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            )
          : values == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      context.tr('Les nombres de toute la plateforme. Chaque changement est écrit dans le Journal, où « Annuler » le reprend.'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    // The bell with the app closed, checked end to end (115).
                    if (AppScope.maybeOf(context)?.notify case final notify?) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                        child: Text(context.tr('Notifications'),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      PushCheck(notify: notify),
                    ],
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                        child: Text(settingGroupLabel(context, g),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      KajCard(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final d in platformSettingDefs)
                              if (d.group == g && values.containsKey(d.key))
                                _row(context, d, values[d.key]!),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _row(BuildContext context, SettingDef d, SettingValue v) {
    final theme = Theme.of(context);
    final busy = _busy == d.key;
    final who = v.changedBy == null || v.updatedAt == null
        ? null
        : context.tr('Changé par {who} le {date}', {
            'who': v.changedBy,
            'date': DateFormat('dd/MM/yyyy').format(v.updatedAt!),
          });
    if (d.key == 'admin_two_step') {
      return ListTile(
        key: const Key('setting-admin_two_step'),
        minVerticalPadding: 12,
        leading: const Icon(Icons.verified_user_outlined),
        title: Text(settingLabel(context, d.key)),
        subtitle: Text(v.value == true
            ? context.tr('Activée — changée dans Compte › Sécurité.')
            : context.tr('Désactivée — changée dans Compte › Sécurité.')),
        trailing: TextButton(
          onPressed: () async {
            await context.push(Routes.security);
            if (mounted) await _load();
          },
          child: Text(context.tr('Ouvrir')),
        ),
      );
    }
    if (d.type == SettingType.flag || d.type == SettingType.flag01) {
      final on = d.type == SettingType.flag
          ? v.value == true
          : ((v.value is num ? v.value as num : 0) > 0);
      // What must be set up before the switch is turned (109): a code that
      // cannot leave would stop every order.
      final before = d.key == 'order_phone_verified' || d.key == 'courier_phone_verified' ||
              d.key == 'create_phone_verified'
          ? context.tr('À n\'activer qu\'une fois le Worker whatsapp-otp déployé, le modèle WhatsApp « authentication » approuvé et le hook « Send SMS » de Supabase branché (BUILD_PLAN.md, « Numéros vérifiés par WhatsApp »).')
          : null;
      return SwitchListTile(
        key: Key('setting-${d.key}'),
        title: Text(settingLabel(context, d.key)),
        subtitle: before == null && who == null
            ? null
            : Text([?before, ?who].join('\n')),
        value: on,
        onChanged: busy
            ? null
            : (next) => _save(d, d.type == SettingType.flag ? next : (next ? 1 : 0)),
      );
    }
    return ListTile(
      key: Key('setting-${d.key}'),
      minVerticalPadding: 10,
      title: Text(settingLabel(context, d.key)),
      subtitle: who == null ? null : Text(who),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              settingValueText(context, d, v.value),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: 4),
          if (busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            const Icon(Icons.edit_outlined, size: 20, color: maraBrown),
        ],
      ),
      onTap: busy ? null : () => _edit(d, v.value),
    );
  }
}

/// One setting, typed in its own way.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.def, required this.current});

  final SettingDef def;
  final Object? current;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _text = TextEditingController(
      text: widget.current is List ? '' : '${widget.current ?? ''}');
  late final Set<String> _picked = {
    if (widget.current is List) for (final e in widget.current as List) '$e',
  };
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _ok() {
    final def = widget.def;
    final raw = _text.text.trim();
    Object? value;
    String? problem;
    final decimals = decimalSettings.contains(def.key);
    switch (def.type) {
      case SettingType.money:
      case SettingType.count:
      case SettingType.km:
        final n = parseAmount(raw);
        if (n == null || n < 0 || (!decimals && n != n.roundToDouble())) {
          problem = decimals
              ? context.tr('Un nombre, zéro ou plus.')
              : context.tr('Un nombre entier, zéro ou plus.');
        } else if (n > settingMax) {
          problem = context.tr('Un nombre d\'un milliard au plus.');
        } else {
          value = n == n.roundToDouble() ? n.round() : n;
        }
      case SettingType.pct:
        final n = parseAmount(raw);
        if (n == null || n < 0 || n > 100 || (!decimals && n != n.roundToDouble())) {
          problem = decimals
              ? context.tr('Un pourcentage de 0 à 100.')
              : context.tr('Un pourcentage entier, de 0 à 100.');
        } else {
          value = n == n.roundToDouble() ? n.round() : n;
        }
      case SettingType.currency:
        if (!RegExp(r'^[A-Za-z]{3}$').hasMatch(raw)) {
          problem = context.tr('Trois lettres, comme XOF.');
        } else {
          value = raw.toUpperCase();
        }
      case SettingType.text:
        if (raw.length > 200) {
          problem = context.tr('200 caractères au plus.');
        } else {
          value = raw;
        }
      case SettingType.list:
        value = [for (final o in def.options) if (_picked.contains(o)) o];
      case SettingType.flag:
      case SettingType.flag01:
        value = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final numeric = def.type == SettingType.money ||
        def.type == SettingType.count ||
        def.type == SettingType.km ||
        def.type == SettingType.pct;
    return AlertDialog(
      // The keyboard up on a small phone: the dialog scrolls (A6).
      scrollable: true,
      title: Text(settingLabel(context, def.key)),
      content: SizedBox(
        width: 420,
        child: def.type == SettingType.list
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in def.options)
                    FilterChip(
                      label: Text(featureName(context, o)),
                      selected: _picked.contains(o),
                      onSelected: (on) => setState(() => on ? _picked.add(o) : _picked.remove(o)),
                    ),
                ],
              )
            : TextField(
                key: const Key('setting-field'),
                controller: _text,
                autofocus: true,
                keyboardType: numeric
                    ? TextInputType.numberWithOptions(
                        decimal: decimalSettings.contains(def.key))
                    : TextInputType.text,
                onSubmitted: (_) => _ok(),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  suffixText: def.type == SettingType.pct
                      ? '%'
                      : def.type == SettingType.km
                          ? 'km'
                          : null,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          key: const Key('setting-save'),
          onPressed: _ok,
          child: Text(context.tr('Enregistrer')),
        ),
      ],
    );
  }
}

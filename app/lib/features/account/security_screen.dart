import 'package:flutter/material.dart';
import '../../core/theme/kaj_card.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/auth/two_step.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/security/security_repository.dart';
import '../../core/security/security_settings.dart';
import 'package:kaj_app/core/l10n/tr.dart';
import '../../core/notify/bell_room.dart';
import '../../core/nav/parent_route.dart';
import '../../core/theme/scroll_hint.dart';

/// Compte › Sécurité.
///
/// Four short groups, in the order a shopkeeper needs them: the phone's lock
/// (the code after a few minutes away, the fingerprint), discretion (the
/// day's money hidden at the counter), the password and the places the
/// account is signed in, and the account's recent security history.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({
    super.key,
    this.settings,
    this.api,
    this.twoStep,
    this.platformAdmin,
  });

  /// Taken from the app scope when not given (tests give them).
  final SecuritySettings? settings;
  final SecurityRepository? api;
  final TwoStep? twoStep;
  final bool? platformAdmin;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late final SecuritySettings? _settings =
      widget.settings ?? AppScope.read(context)?.security;
  late final SecurityRepository? _api =
      widget.api ?? AppScope.read(context)?.securityApi;
  late final TwoStep? _twoStep =
      widget.twoStep ?? AppScope.read(context)?.session.twoStep;
  late final bool _platformAdmin =
      widget.platformAdmin ??
      (AppScope.read(context)?.session.isPlatformAdmin ?? false);

  /// The platform's second-step switch (078); null until read, and for
  /// anybody who is not the platform admin.
  bool? _twoStepOn;

  List<SignInSession> _sessions = const [];
  List<SecurityEvent> _events = const [];
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _settings?.addListener(_changed);
    _settings?.refreshBiometric();
    _load();
  }

  @override
  void dispose() {
    _settings?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final step = _twoStep;
    if (_platformAdmin && step != null) {
      step.status().then((s) {
        if (mounted) setState(() => _twoStepOn = s.on);
      }, onError: (_) {});
    }
    final api = _api;
    if (api == null || !api.isConfigured) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([api.sessions(), api.events()]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<SignInSession>;
        _events = results[1] as List<SecurityEvent>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _setLock(int? minutes) async {
    final settings = _settings;
    if (settings == null || !settings.allows(minutes)) return;
    await settings.setLockAfter(minutes);
    await _api?.log('lock_changed', detail: SecuritySettings.label(minutes));
  }

  /// On: the system prompt, once — the person's authorization. Off: no
  /// prompt, the code alone.
  Future<void> _setBiometric(bool on) async {
    final settings = _settings;
    if (settings == null) return;
    if (!on) {
      await settings.setBiometric(false);
      return;
    }
    setState(() => _busy = 'bio');
    final outcome = await settings.turnOnBiometric();
    if (!mounted) return;
    setState(() => _busy = null);
    switch (outcome) {
      case BiometricOutcome.on:
        break;
      case BiometricOutcome.refused:
        await settings.setBiometric(false);
      case BiometricOutcome.notEnrolled:
        await settings.setBiometric(false);
        if (mounted) {
          _say(context.tr('Aucune empreinte ni visage n\'est enregistré sur ce téléphone. Ajoutez-en un dans les réglages du téléphone (Sécurité), puis revenez ici.'));
        }
      case BiometricOutcome.failed:
        await settings.setBiometric(false);
        if (mounted) {
          _say(context.tr('Le téléphone n\'a pas pu vérifier l\'empreinte. Réessayez, ou gardez le code.'));
        }
    }
  }

  Future<void> _changeCode() async {
    final scope = AppScope.read(context);
    if (scope == null) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeCodeDialog(
        change: (current, next) => scope.session.changePin(current, next),
      ),
    );
    if (done == true) {
      await _api?.log('pin_changed');
      _say(translate(trCurrent, 'Code changé.'));
      await _load();
    }
  }

  Future<void> _changePassword() async {
    final api = _api;
    if (api == null) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(api: api),
    );
    if (done == true) {
      _say(translate(trCurrent, 'Mot de passe changé.'));
      await _load();
    }
  }

  /// Switching the platform's second step on or off. On, Kaj goes
  /// straight to adding the authenticator app: from then on the server
  /// refuses this account anything without the code.
  Future<void> _setTwoStep(bool on) async {
    final step = _twoStep;
    if (step == null) return;
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Activer la validation en deux étapes ?')),
          content: Text(
            context.tr('Le compte de la plateforme demandera, à chaque connexion, un code à 6 chiffres de Google Authenticator ou Microsoft Authenticator. Mara vous montre tout de suite comment l\'ajouter. Les comptes des boutiques ne changent pas : mot de passe, puis le code de l\'appareil.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr('Annuler')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.tr('Activer')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final session = AppScope.read(context)?.session;
    setState(() => _busy = 'two-step');
    try {
      await step.setRequired(on);
      if (!mounted) return;
      setState(() => _twoStepOn = on);
      if (on) {
        // The resolve now stops at the code screen, which enrols.
        await session?.resolveOrgs();
      } else {
        _say(context.tr('Validation en deux étapes désactivée.'));
      }
    } catch (e) {
      _say(describeError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _closeOne(SignInSession s) async {
    setState(() => _busy = s.id);
    try {
      await _api!.closeSession(s.id);
      await _load();
    } catch (e) {
      _say(describeError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _closeOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Déconnecter les autres appareils ?')),
        content: Text(
          context.tr('Ce téléphone reste connecté. Les autres devront se reconnecter avec le mot de passe.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('Déconnecter')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = 'others');
    try {
      final n = await _api!.closeOtherSessions();
      if (!mounted) return;
      _say(
        n == 0
            ? context.tr('Aucun autre appareil n\'était connecté.')
            : context.tr('{n} appareil(s) déconnecté(s).', {'n': n}),
      );
      await _load();
    } catch (e) {
      _say(describeError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    final when = DateFormat('d MMM, HH:mm', intlLocale());
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final others = _sessions.where((s) => !s.current).length;

    return ScrollHint(child: Scaffold(
      appBar: AppBar(leading: parentBack(context), actions: const [bellRoom], title: Text(context.tr('Sécurité'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (settings != null) ...[
            _Group(
              title: context.tr('Verrouillage du téléphone'),
              note: settings.policy == null
                  ? context.tr('Après ce délai hors de l\'application, Mara redemande le code de l\'appareil.')
                  : context.tr('Votre entreprise demande le code après {delay} au plus.',
                      {'delay': context.tr(SecuritySettings.label(settings.policy))}),
              children: [
                RadioGroup<int?>(
                  groupValue: settings.effectiveLock,
                  onChanged: (v) => _setLock(v),
                  child: Column(
                    children: [
                      for (final m in SecuritySettings.choices)
                        RadioListTile<int?>(
                          value: m,
                          enabled: settings.allows(m),
                          title: Text(
                            m == null
                                ? context.tr('Jamais')
                                : context.tr('Après {delay}', {'delay': context.tr(SecuritySettings.label(m))}),
                          ),
                          subtitle: m == SecuritySettings.defaultLock
                              ? Text(context.tr('Conseillé'))
                              : (!settings.allows(m)
                                    ? Text(
                                        context.tr('Non permis par votre entreprise'),
                                      )
                                    : null),
                        ),
                    ],
                  ),
                ),
                if (settings.biometricHardware)
                  SwitchListTile(
                    value: settings.biometric && settings.biometricReady,
                    onChanged: settings.biometricReady && _busy != 'bio'
                        ? _setBiometric
                        : null,
                    secondary: const Icon(Icons.fingerprint),
                    title: Text(
                      context.tr('Déverrouiller avec l\'empreinte / Face ID'),
                    ),
                    subtitle: Text(
                      settings.biometricReady
                          ? context.tr('Le code reste toujours possible.')
                          : context.tr('Aucune empreinte ni visage n\'est enregistré sur ce téléphone. Ajoutez-en un dans les réglages du téléphone (Sécurité), puis revenez ici.'),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: Text(context.tr('Changer le code')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changeCode,
                ),
              ],
            ),
            _Group(
              title: context.tr('Discrétion'),
              children: [
                SwitchListTile(
                  value: settings.hideAmounts,
                  onChanged: settings.setHideAmounts,
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: Text(context.tr('Cacher les montants à l\'accueil')),
                  subtitle: Text(
                    context.tr('Le total du jour s\'affiche d\'un toucher, pas devant les clients.'),
                  ),
                ),
              ],
            ),
          ],
          _Group(
            title: context.tr('Mot de passe et appareils'),
            note: others == 0
                ? null
                : context.tr('Les noms d\'appareils viennent du navigateur ou du téléphone : ils sont approximatifs. Un appareil fermé garde l\'accès au plus une heure, le temps que sa clé expire.'),
            children: [
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: Text(context.tr('Changer le mot de passe')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePassword,
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                for (final s in _sessions)
                  ListTile(
                    leading: Icon(
                      s.label.startsWith('Android') ||
                              s.label.startsWith('iPhone')
                          ? Icons.smartphone
                          : Icons.computer,
                    ),
                    title: Text(s.label),
                    subtitle: Text(
                      [
                        if (s.current) context.tr('Cet appareil'),
                        if (!s.current && s.lastUsed != null)
                          context.tr('utilisé le {date}', {'date': when.format(s.lastUsed!)}),
                        if ((s.ip ?? '').isNotEmpty) s.ip!,
                      ].join(' · '),
                    ),
                    trailing: s.current
                        ? null
                        : IconButton(
                            tooltip: context.tr('Déconnecter cet appareil'),
                            icon: const Icon(Icons.logout),
                            onPressed: _busy != null
                                ? null
                                : () => _closeOne(s),
                          ),
                  ),
              if (others > 0)
                ListTile(
                  leading: Icon(
                    Icons.phonelink_erase_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    context.tr('Déconnecter les autres appareils'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: _busy != null ? null : _closeOthers,
                ),
            ],
          ),
          if (_platformAdmin && _twoStep != null && _twoStepOn != null)
            _Group(
              title: context.tr('Plateforme'),
              children: [
                SwitchListTile(
                  key: const Key('two-step-switch'),
                  value: _twoStepOn!,
                  onChanged: _busy != null ? null : _setTwoStep,
                  secondary: const Icon(Icons.verified_user_outlined),
                  title: Text(context.tr('Validation en deux étapes')),
                  subtitle: Text(
                    _twoStepOn!
                        ? context.tr('Activée : un code de votre application d\'authentification est demandé à chaque connexion du compte de la plateforme.')
                        : context.tr('Désactivée : le compte de la plateforme s\'ouvre avec le mot de passe, puis le code de l\'appareil.'),
                  ),
                ),
              ],
            ),
          _Group(
            title: context.tr('Activité du compte'),
            children: [
              if (!_loading && _events.isEmpty)
                ListTile(title: Text(context.tr('Rien pour l\'instant.'), style: muted)),
              for (final e in _events.take(20))
                ListTile(
                  dense: true,
                  leading: Icon(_iconFor(e.kind), size: 20),
                  title: Text(e.label),
                  subtitle: Text(when.format(e.at)),
                ),
            ],
          ),
        ],
      ),
    ));
  }

  static IconData _iconFor(String kind) => switch (kind) {
    'new_device' => Icons.devices_other_outlined,
    'password_changed' => Icons.password_outlined,
    'pin_changed' => Icons.pin_outlined,
    'two_step_enabled' => Icons.verified_user_outlined,
    'lock_changed' => Icons.lock_clock_outlined,
    'signed_out_by_admin' => Icons.admin_panel_settings_outlined,
    _ => Icons.logout,
  };
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          KajCard(
            elevation: 0,
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerHighest,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  children[i],
                ],
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChangeCodeDialog extends StatefulWidget {
  const _ChangeCodeDialog({required this.change});

  final Future<String?> Function(String current, String next) change;

  @override
  State<_ChangeCodeDialog> createState() => _ChangeCodeDialogState();
}

class _ChangeCodeDialogState extends State<_ChangeCodeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_next.text != _again.text) {
      setState(() => _error = context.tr('Les deux nouveaux codes ne sont pas pareils.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await widget.change(_current.text, _next.text);
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = problem;
      });
    }
  }

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      enabled: !_busy,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // The keyboard up on a small phone: the dialog scrolls (A6).
      scrollable: true,
      title: Text(context.tr('Changer le code')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_current, 'Code actuel'),
          _field(_next, 'Nouveau code'),
          _field(_again, 'Nouveau code, encore'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          onPressed: _busy ? null : _go,
          child: Text(context.tr('Changer')),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.api});

  final SecurityRepository api;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_next.text.length < 8) {
      setState(() => _error = context.tr('Au moins 8 caractères.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.changePassword(current: _current.text, next: _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // The keyboard up on a small phone: the dialog scrolls (A6).
      scrollable: true,
      title: Text(context.tr('Changer le mot de passe')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.tr('Mot de passe actuel'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _next,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.tr('Nouveau mot de passe'),
              helperText: context.tr('Au moins 8 caractères'),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('Annuler')),
        ),
        FilledButton(
          onPressed: _busy ? null : _go,
          child: Text(context.tr('Changer')),
        ),
      ],
    );
  }
}

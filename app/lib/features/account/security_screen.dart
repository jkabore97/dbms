import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/security/security_repository.dart';
import '../../core/security/security_settings.dart';

/// Compte › Sécurité.
///
/// Four short groups, in the order a shopkeeper needs them: the phone's lock
/// (the code after a few minutes away, the fingerprint), discretion (the
/// day's money hidden at the counter), the password and the places the
/// account is signed in, and the account's recent security history.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, this.settings, this.api});

  /// Taken from the app scope when not given (tests give them).
  final SecuritySettings? settings;
  final SecurityRepository? api;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late final SecuritySettings? _settings =
      widget.settings ?? AppScope.read(context)?.security;
  late final SecurityRepository? _api =
      widget.api ?? AppScope.read(context)?.securityApi;

  List<SignInSession> _sessions = const [];
  List<SecurityEvent> _events = const [];
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _settings?.addListener(_changed);
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
      _say('Code changé.');
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
      _say('Mot de passe changé.');
      await _load();
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
        title: const Text('Déconnecter les autres appareils ?'),
        content: const Text(
          'Ce téléphone reste connecté. Les autres devront se reconnecter '
          'avec le mot de passe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = 'others');
    try {
      final n = await _api!.closeOtherSessions();
      _say(
        n == 0
            ? 'Aucun autre appareil n\'était connecté.'
            : '$n appareil${n > 1 ? 's' : ''} déconnecté${n > 1 ? 's' : ''}.',
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
    final when = DateFormat('d MMM, HH:mm', 'fr_FR');
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final others = _sessions.where((s) => !s.current).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (settings != null) ...[
            _Group(
              title: 'Verrouillage du téléphone',
              note: settings.policy == null
                  ? 'Après ce délai hors de l\'application, Kaj redemande '
                        'le code de l\'appareil.'
                  : 'Votre entreprise demande le code après '
                        '${SecuritySettings.label(settings.policy)} au plus.',
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
                                ? 'Jamais'
                                : 'Après ${SecuritySettings.label(m)}',
                          ),
                          subtitle: m == SecuritySettings.defaultLock
                              ? const Text('Conseillé')
                              : (!settings.allows(m)
                                    ? const Text(
                                        'Non permis par votre entreprise',
                                      )
                                    : null),
                        ),
                    ],
                  ),
                ),
                if (settings.biometricReady)
                  SwitchListTile(
                    value: settings.biometric,
                    onChanged: settings.setBiometric,
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Déverrouiller avec l\'empreinte'),
                    subtitle: const Text('Le code reste toujours possible.'),
                  ),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('Changer le code'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changeCode,
                ),
              ],
            ),
            _Group(
              title: 'Discrétion',
              children: [
                SwitchListTile(
                  value: settings.hideAmounts,
                  onChanged: settings.setHideAmounts,
                  secondary: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Cacher les montants à l\'accueil'),
                  subtitle: const Text(
                    'Le total du jour s\'affiche d\'un toucher, pas devant '
                    'les clients.',
                  ),
                ),
              ],
            ),
          ],
          _Group(
            title: 'Mot de passe et appareils',
            note: others == 0
                ? null
                : 'Les noms d\'appareils viennent du navigateur ou du '
                      'téléphone : ils sont approximatifs. Un appareil fermé '
                      'garde l\'accès au plus une heure, le temps que sa clé '
                      'expire.',
            children: [
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Changer le mot de passe'),
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
                        if (s.current) 'Cet appareil',
                        if (!s.current && s.lastUsed != null)
                          'utilisé le ${when.format(s.lastUsed!)}',
                        if ((s.ip ?? '').isNotEmpty) s.ip!,
                      ].join(' · '),
                    ),
                    trailing: s.current
                        ? null
                        : IconButton(
                            tooltip: 'Déconnecter cet appareil',
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
                    'Déconnecter les autres appareils',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: _busy != null ? null : _closeOthers,
                ),
            ],
          ),
          _Group(
            title: 'Activité du compte',
            children: [
              if (!_loading && _events.isEmpty)
                ListTile(title: Text('Rien pour l\'instant.', style: muted)),
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
    );
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
          Card(
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
      setState(() => _error = 'Les deux nouveaux codes ne sont pas pareils.');
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
      title: const Text('Changer le code'),
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
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _go,
          child: const Text('Changer'),
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
      setState(() => _error = 'Au moins 8 caractères.');
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
      title: const Text('Changer le mot de passe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            enabled: !_busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mot de passe actuel',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _next,
            enabled: !_busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nouveau mot de passe',
              helperText: 'Au moins 8 caractères',
              border: OutlineInputBorder(),
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
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _busy ? null : _go,
          child: const Text('Changer'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/l10n/tr.dart';
import '../../core/notify/notifications_repository.dart';
import '../../core/notify/push_client.dart';
import '../../core/notify/push_setup.dart';

/// « Diagnostic de cet appareil » (120): every step between THIS device and
/// a ring with the app closed, each with a yes or a no — so « je ne vois
/// rien » becomes the one step that is missing. Under « Tester la
/// notification » (Réglages of the command center) and in Compte ›
/// Notifications.
///
/// Opened, it only looks — nothing is asked. « Réessayer l'enregistrement »
/// is the person's tap: it starts again what failed, asks the device if it
/// may still be asked, and writes the address.
class PushDiagnosticsPanel extends StatefulWidget {
  const PushDiagnosticsPanel({super.key, required this.notify, this.look});

  final NotificationsRepository notify;

  /// What is shown; the device's own diagnosis when not given (a test
  /// gives its own).
  final Future<PushDiagnosis> Function()? look;

  @override
  State<PushDiagnosticsPanel> createState() => _PushDiagnosticsPanelState();
}

class _PushDiagnosticsPanelState extends State<PushDiagnosticsPanel> {
  PushDiagnosis? _d;
  bool _busy = false;
  bool? _retried;

  Future<PushDiagnosis> _diagnose() =>
      (widget.look ?? () => PushSetup.diagnose(widget.notify))();

  Future<void> _load() async {
    final d = await _diagnose();
    if (mounted) setState(() => _d = d);
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _retried = null;
    });
    final on = await PushSetup.retry(widget.notify);
    final d = await _diagnose();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _retried = on;
      _d = d;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('push-diagnostics'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: const Icon(Icons.troubleshoot_outlined),
      title: Text(context.tr('Diagnostic de cet appareil')),
      onExpansionChanged: (open) {
        if (open && _d == null) _load();
      },
      children: [
        if (_d == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ..._rows(context, _d!),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('push-diagnostics-retry'),
            onPressed: _busy || _d == null ? null : _retry,
            icon: const Icon(Icons.refresh),
            label: Text(context.tr('Réessayer l\'enregistrement')),
          ),
        ),
        if (_retried != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _retried!
                  ? context.tr('Cet appareil est inscrit : il sonnera même l\'application fermée.')
                  : context.tr('L\'enregistrement n\'a pas abouti : voyez la ligne marquée « non » ci-dessus.'),
              key: const Key('push-diagnostics-said'),
            ),
          ),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, PushDiagnosis d) {
    final f = d.facts;
    final web = f.platform == 'Web';
    final android = f.platform == 'Android';
    String permission() => switch (d.permission) {
          PushPermission.granted => context.tr('autorisées'),
          PushPermission.prompt => context.tr('pas encore demandées ou refusées une fois'),
          PushPermission.blocked => context.tr('bloquées (seuls les réglages peuvent les ouvrir)'),
          PushPermission.unsupported => context.tr('non disponibles ici'),
        };
    return [
      _Row(label: context.tr('Plateforme'), value: f.platform),
      _Row(label: context.tr('Connecté'), ok: d.signedIn),
      if (web)
        _Row(
          label: context.tr('Adresse du Worker push dans cette version'),
          ok: d.buildHasWorker,
        ),
      if (android || f.firebaseReady != null)
        _Row(
          key: const Key('diag-firebase'),
          label: context.tr('Firebase démarré'),
          ok: f.firebaseReady ?? false,
          detail: f.firebaseReady == false
              ? (f.firebaseError ?? context.tr('Cette version a été construite sans google-services.json.'))
              : null,
        ),
      _Row(
        key: const Key('diag-permission'),
        label: context.tr('Autorisation de l\'appareil'),
        value: permission(),
        ok: d.permission == PushPermission.granted,
      ),
      if (web)
        _Row(label: context.tr('Service worker actif'), ok: f.workerActive ?? false),
      _Row(
        key: const Key('diag-address'),
        label: web
            ? context.tr('Abonnement du navigateur')
            : context.tr('Jeton de l\'appareil obtenu'),
        ok: d.address != null,
      ),
      _Row(
        key: const Key('diag-saved'),
        label: context.tr('Enregistré sur le serveur'),
        ok: d.saved ?? false,
      ),
      if (d.error != null)
        _Row(label: context.tr('Erreur'), value: d.error),
    ];
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.label, this.ok, this.value, this.detail});

  final String label;
  final bool? ok;
  final String? value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final answer = value ?? (ok! ? context.tr('oui') : context.tr('non'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok == null
                ? Icons.info_outline
                : ok!
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
            size: 20,
            color: ok == null ? colors.onSurfaceVariant : ok! ? colors.primary : colors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$label : $answer'),
                if (detail != null)
                  Text(detail!,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

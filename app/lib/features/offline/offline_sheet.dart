import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/offline/offline_app.dart';
import '../../core/offline/offline_prep.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// Asks a business's admin, once per device, whether to use Mara without a
/// connection — the first time the business's home opens (after the first
/// setup). Only with a live session: a shopper never reaches a home, and a
/// test without a server is never interrupted.
class OfflineOffer extends StatefulWidget {
  const OfflineOffer({super.key, required this.org, required this.child});

  final OrgSummary org;
  final Widget child;

  @override
  State<OfflineOffer> createState() => _OfflineOfferState();
}

class _OfflineOfferState extends State<OfflineOffer> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final scope = AppScope.maybeOf(context);
    if (scope == null || !scope.auth.hasLiveSession) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask(scope));
  }

  Future<void> _ask(AppScope scope) async {
    final prep = offlinePrepOf(scope);
    if (!await prep.shouldAsk(widget.org) || !mounted) return;
    await prep.markAsked(widget.org);
    if (!mounted) return;
    await OfflineSheet.open(context, org: widget.org, prep: prep);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

OfflinePrep offlinePrepOf(AppScope scope) => OfflinePrep(
      db: scope.db,
      farm: scope.farm,
      cacheChart: scope.session.cacheChart,
    );

/// « Utiliser Mara sans connexion ? » then « Télécharger pour hors ligne »:
/// the question first, and only on « Oui » the button that downloads, with
/// each step ticked as it is done.
class OfflineSheet extends StatefulWidget {
  const OfflineSheet({
    super.key,
    required this.org,
    required this.prep,
    this.askFirst = true,
  });

  final OrgSummary org;
  final OfflinePrep prep;

  /// From Compte the person already chose: straight to the button.
  final bool askFirst;

  static Future<void> open(BuildContext context,
          {required OrgSummary org,
          required OfflinePrep prep,
          bool askFirst = true}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            OfflineSheet(org: org, prep: prep, askFirst: askFirst),
      );

  @override
  State<OfflineSheet> createState() => _OfflineSheetState();
}

enum _Phase { ask, ready, working, done }

class _OfflineSheetState extends State<OfflineSheet> {
  late _Phase _phase = widget.askFirst ? _Phase.ask : _Phase.ready;
  final _done = <OfflineStep>{};
  OfflineStep? _current;
  List<OfflineStep> _failed = const [];
  (int, int)? _files;

  Future<void> _download() async {
    setState(() => _phase = _Phase.working);
    final failed = await widget.prep.prepare(
      widget.org,
      onStep: (step, done) {
        if (!mounted) return;
        setState(() {
          if (done) {
            _done.add(step);
            _current = null;
          } else {
            _current = step;
          }
        });
      },
      onProgress: (done, total) {
        if (mounted) setState(() => _files = (done, total));
      },
    );
    if (!mounted) return;
    setState(() {
      _failed = failed;
      _phase = _Phase.done;
    });
  }

  String _label(BuildContext context, OfflineStep step) => switch (step) {
        OfflineStep.app => context.tr('L\'application sur ce téléphone'),
        OfflineStep.accounts => context.tr('Vos catégories et vos comptes'),
        OfflineStep.farm => context.tr('Votre stock et vos bandes'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final steps = widget.prep.stepsFor(widget.org);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              _phase == _Phase.done && _failed.isEmpty
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _phase == _Phase.done
                  ? (_failed.isEmpty
                      ? context.tr('Prêt : Mara fonctionne sans connexion')
                      : context.tr('Presque prêt'))
                  : context.tr('Utiliser Mara sans connexion ?'),
              key: const Key('offline-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _phase == _Phase.done
                  ? (_failed.isEmpty
                      ? context.tr('Sans réseau, vos écritures restent sur ce téléphone et partent dès que la connexion revient.')
                      : context.tr('Certaines parties n\'ont pas pu être téléchargées. Réessayez avec une meilleure connexion.'))
                  : context.tr('Mara peut garder sur ce téléphone de quoi travailler sans réseau. Les clients de votre vitrine, eux, n\'en ont pas besoin.'),
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 18),
            if (_phase != _Phase.ask)
              for (final step in steps)
                ListTile(
                  key: Key('offline-step-${step.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _done.contains(step)
                      ? Icon(
                          _failed.contains(step)
                              ? Icons.error_outline
                              : Icons.check_circle,
                          color: _failed.contains(step)
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary)
                      : _current == step
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2))
                          : const Icon(Icons.radio_button_unchecked),
                  title: Text(_label(context, step)),
                  subtitle: step == OfflineStep.app &&
                          _current == step &&
                          _files != null
                      ? Text(context.tr('{done} fichiers sur {total}',
                          {'done': _files!.$1, 'total': _files!.$2}))
                      : null,
                ),
            const SizedBox(height: 12),
            switch (_phase) {
              _Phase.ask => Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('offline-later'),
                        onPressed: () => Navigator.pop(context),
                        child: Text(context.tr('Plus tard')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('offline-yes'),
                        onPressed: () =>
                            setState(() => _phase = _Phase.ready),
                        child: Text(context.tr('Oui')),
                      ),
                    ),
                  ],
                ),
              _Phase.ready => FilledButton.icon(
                  key: const Key('offline-download'),
                  onPressed: _download,
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(context.tr('Télécharger pour hors ligne')),
                ),
              _Phase.working => FilledButton.icon(
                  onPressed: null,
                  icon: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  label: Text(context.tr('Téléchargement…')),
                ),
              _Phase.done => _failed.isEmpty
                  ? FilledButton(
                      key: const Key('offline-close'),
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.tr('Terminé')),
                    )
                  : FilledButton(
                      key: const Key('offline-retry'),
                      onPressed: _download,
                      child: Text(context.tr('Réessayer')),
                    ),
            },
            if (_phase == _Phase.ask) ...[
              const SizedBox(height: 10),
              Text(
                context.tr('Vous pourrez le faire plus tard dans Compte › Hors ligne.'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compte › Préférences: whether this device is ready, and the button.
class OfflineTile extends StatefulWidget {
  const OfflineTile({super.key, required this.org});

  final OrgSummary org;

  @override
  State<OfflineTile> createState() => _OfflineTileState();
}

class _OfflineTileState extends State<OfflineTile> {
  DateTime? _ready;
  bool _kept = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _read();
  }

  Future<void> _read() async {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return;
    final ready = await offlinePrepOf(scope).readyAt();
    final kept = await OfflineApp.kept;
    if (mounted) {
      setState(() {
        _ready = ready;
        _kept = kept;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    final on = _ready != null && (!OfflineApp.needsCopy || _kept);
    return ListTile(
      key: const Key('compte-offline'),
      leading: Icon(on ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
      title: Text(context.tr('Hors ligne')),
      subtitle: Text(on
          ? context.tr('Prêt sur ce téléphone')
          : context.tr('Pas encore préparé')),
      trailing: const Icon(Icons.chevron_right),
      onTap: scope == null
          ? null
          : () async {
              await OfflineSheet.open(context,
                  org: widget.org,
                  prep: offlinePrepOf(scope),
                  askFirst: false);
              await _read();
            },
    );
  }
}

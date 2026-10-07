import 'package:flutter/material.dart';

import '../../core/auth/models.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/look_only.dart';
import '../../core/theme/mara_mark.dart';
import '../../core/theme/motion.dart';
import 'package:kaj_app/core/l10n/tr.dart';

/// « Factures débloquées ! » (096): the first time an admin opens the home
/// after a tool on the path opened, the tool says so — its picture, a
/// check, a few words — once. The bell (and the push) said it already; this
/// is the moment the owner sees the door is open, where the tools are.
class UnlockCelebration extends StatefulWidget {
  const UnlockCelebration({super.key, required this.org, required this.child});

  final OrgSummary org;
  final Widget child;

  @override
  State<UnlockCelebration> createState() => _UnlockCelebrationState();
}

class _UnlockCelebrationState extends State<UnlockCelebration> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    final scope = AppScope.maybeOf(context);
    // The moment is the owner's: Mara opening the business (or seeing it
    // as its owner, 106) must not spend it — it is marked seen on the
    // server for everybody.
    if (scope == null ||
        !scope.auth.hasLiveSession ||
        !widget.org.isAdmin ||
        scope.session.isPlatformAdmin ||
        LookOnly.of(context)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(scope));
  }

  Future<void> _check(AppScope scope) async {
    final unseen = await scope.admin.unseenUnlocks(widget.org.id);
    if (unseen.isEmpty || !mounted) return;
    // A tool Mara's switchboard hid here (104) opens on the path all the
    // same, but is not celebrated: there is no door to show.
    final access = scope.session.accessFor(widget.org.id);
    final steps = [
      for (final s in unseen)
        if (!access.isHidden(s)) s,
    ];
    if (steps.isEmpty) {
      await scope.admin.markUnlocksSeen(widget.org.id);
      return;
    }
    // Another sheet first (the offline offer): wait for it to close rather
    // than stacking two.
    for (var i = 0; i < 20; i++) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? true) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    await scope.admin.markUnlocksSeen(widget.org.id);
    // The badges and the gates follow at once.
    await scope.session.reloadFeatures(widget.org.id);
    if (!mounted) return;
    await UnlockDialog.show(context, steps);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The picture and the words for each step.
({IconData icon, String title, String line}) unlockInfo(String step) =>
    switch (step) {
      'invoices' => (
          icon: Icons.receipt_long,
          title: 'Factures débloquées',
          line: 'Vos articles sont en vente et en photo : faites vos factures.',
        ),
      'production' => (
          icon: Icons.precision_manufacturing,
          title: 'Production débloquée',
          line: 'Étape Remplir terminée : suivez ce que vous fabriquez.',
        ),
      'credits' => (
          icon: Icons.handshake,
          title: 'Carnet de crédit débloqué',
          line: 'Trois commandes terminées : notez ce que vos clients vous doivent.',
        ),
      _ => (icon: Icons.lock_open, title: 'Outil débloqué', line: ''),
    };

class UnlockDialog extends StatelessWidget {
  const UnlockDialog({super.key, required this.steps});

  final List<String> steps;

  static Future<void> show(BuildContext context, List<String> steps) =>
      showDialog<void>(
        context: context,
        builder: (_) => UnlockDialog(steps: steps),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = KajMotion.reduced(context);
    final first = unlockInfo(steps.first);
    return Dialog(
      key: const Key('unlock-dialog'),
      backgroundColor: maraDeep,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? 1 : 0.6, end: 1),
                duration: reduced ? Duration.zero : const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Wrap(
                  spacing: 12,
                  children: [
                    for (final s in steps)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: maraCaramel,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Icon(unlockInfo(s).icon,
                                size: 40, color: maraDeep),
                          ),
                          const Positioned(
                            right: -6,
                            bottom: -6,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: maraGreen,
                              child: Icon(Icons.lock_open,
                                  size: 17, color: maraPaper),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              steps.length == 1
                  ? '${context.tr(first.title)} !'
                  : context.tr('{n} outils débloqués !', {'n': steps.length}),
              key: const Key('unlock-title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: maraPaper, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final s in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  steps.length == 1
                      ? context.tr(unlockInfo(s).line)
                      : '${context.tr(unlockInfo(s).title)} — ${context.tr(unlockInfo(s).line)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: maraPaper.withValues(alpha: 0.8)),
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('unlock-ok'),
              style: FilledButton.styleFrom(
                  backgroundColor: maraCaramel, foregroundColor: maraDeep),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('Super !')),
            ),
          ],
        ),
      ),
    );
  }
}

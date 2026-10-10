import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/store_rules.dart';
import '../../core/auth/models.dart';
import '../../core/l10n/tr.dart';
import '../../core/nav/app_scope.dart';
import '../../core/nav/router.dart';
import '../../core/theme/mara_mark.dart';
import '../auth/org_picker_screen.dart'
    show iconForProfile, kindColour, kindInk, kindSingular, labelForRole;

/// What « Changer d'activité » does for this person (122).
///
/// - [picker]: several activities — the picker, as before, whose
///   « + Nouvelle activité » sits under the list.
/// - [create]: one activity, which they own or run, and nothing holds a
///   second (Mara Pro, or nothing owned yet) — a sheet with it and
///   « + Créer une nouvelle activité ».
/// - [pro]: one activity they own or run, and a second needs Mara Pro —
///   the same sheet saying so, with « Passer à Pro ».
/// - [none]: one activity they only work in — nothing to switch to and
///   nothing for them to open: no button.
enum ActivitySwitchMode { none, picker, create, pro }

class ActivitySwitch {
  const ActivitySwitch._();

  /// The rule, for every kind of business alike. [secondLocked] is the
  /// server's own answer (099's second_business_locked, through
  /// org_progress); unknown — nothing read yet — no button at all for one
  /// activity, rather than a « Mara Pro » the server may not say (it comes
  /// with the server's answer, a moment later).
  static ActivitySwitchMode modeFor({
    required int activities,
    OrgSummary? org,
    bool platformAdmin = false,
    bool? secondLocked,
  }) {
    if (activities >= 2) return ActivitySwitchMode.picker;
    if (org == null || platformAdmin || !org.isAdmin) {
      return ActivitySwitchMode.none;
    }
    if (secondLocked == null) return ActivitySwitchMode.none;
    return secondLocked ? ActivitySwitchMode.pro : ActivitySwitchMode.create;
  }

  /// The mode for the signed-in person in [org], read off the app's session.
  static ActivitySwitchMode of(BuildContext context, OrgSummary org) {
    final session = AppScope.maybeOf(context)?.session;
    if (session == null) return ActivitySwitchMode.none;
    return modeFor(
      activities: session.orgs.length,
      org: org,
      platformAdmin: session.isPlatformAdmin,
      secondLocked:
          session.featuresFor(org.id)?.progress.serverLocks?['second_business'],
    );
  }

  /// Does what [mode] says: the picker, or the sheet.
  static Future<void> open(
      BuildContext context, OrgSummary? org, ActivitySwitchMode mode) async {
    switch (mode) {
      case ActivitySwitchMode.none:
        return;
      case ActivitySwitchMode.picker:
        context.go(Routes.picker);
        return;
      case ActivitySwitchMode.create:
      case ActivitySwitchMode.pro:
        if (org == null) return;
        final go = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => ActivitySwitchSheet(org: org, mode: mode),
        );
        if (go != null && context.mounted) context.push(go);
    }
  }
}

/// The sheet for somebody with one activity (122): that activity, ticked,
/// and either « + Créer une nouvelle activité » or why a second needs Mara
/// Pro with « Passer à Pro ». Closes with the address to open, if any.
///
/// Plain Cards, not KajCard: a sheet rises without scrolling, so a card
/// waiting for a scroll to reveal it would stay invisible.
class ActivitySwitchSheet extends StatelessWidget {
  const ActivitySwitchSheet({super.key, required this.org, required this.mode});

  final OrgSummary org;
  final ActivitySwitchMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = mode == ActivitySwitchMode.pro;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          key: const Key('activity-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Vos activités'),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _Current(org: org),
            const SizedBox(height: 16),
            if (!locked)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  key: const Key('activity-create'),
                  onPressed: () =>
                      Navigator.of(context).pop(Routes.createBusiness),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('Créer une nouvelle activité'),
                      style: const TextStyle(fontSize: 16)),
                ),
              )
            else ...[
              Card(
                key: const Key('activity-needs-pro'),
                elevation: 0,
                margin: EdgeInsets.zero,
                color: maraCaramel.withValues(alpha: 0.18),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.workspace_premium_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.tr('Une deuxième activité demande Mara Pro'),
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              context.tr('Avec Mara Pro, vous gérez plusieurs activités depuis le même compte et passez de l\'une à l\'autre ici.'),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The way to Pro — not in the iPhone app, which sells no
              // Pro (125): the card above says what a second needs.
              if (sellsDigitalInApp) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('activity-go-pro'),
                    style: FilledButton.styleFrom(
                        backgroundColor: maraCaramel, foregroundColor: maraDeep),
                    onPressed: () => Navigator.of(context)
                        .pop(Routes.inside(org.id, 'kaj-pro')),
                    icon: const Icon(Icons.workspace_premium),
                    label: Text(context.tr('Passer à Pro'),
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The one activity, as the picker draws it, ticked: you are in it.
class _Current extends StatelessWidget {
  const _Current({required this.org});

  final OrgSummary org;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('activity-current-${org.id}'),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kindColour(org.profile),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(iconForProfile(org.profile),
              color: kindInk(org.profile)),
        ),
        title: Text(org.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          kindSingular(context, org.profile),
          if (org.roles.isNotEmpty) context.tr(labelForRole(org.roles.first)),
        ].join(' · ')),
        trailing: Tooltip(
          message: context.tr('Ouverte'),
          child: const Icon(Icons.check_circle, color: maraGreen),
        ),
      ),
    );
  }
}

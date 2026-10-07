import 'package:flutter/material.dart';

import '../../../core/auth/models.dart';
import '../../../core/console/command_center.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/nav/app_scope.dart';
import '../../console/activity_log_tab.dart';
import '../center/journal_section.dart';
import 'fiche_widgets.dart';

/// Journal: what Mara did to this business (the command center's own
/// Journal, 104–105, for this one business), each line with « Annuler »
/// while it can be taken back — and, beside it, the business's own log
/// (103's audit_log_page, which the platform reads as the owner does).
class FicheJournalTab extends StatefulWidget {
  const FicheJournalTab({
    super.key,
    required this.org,
    required this.center,
    required this.onChanged,
  });

  final OrgSummary org;
  final CommandCenterRepository center;
  final VoidCallback onChanged;

  @override
  State<FicheJournalTab> createState() => _FicheJournalTabState();
}

class _FicheJournalTabState extends State<FicheJournalTab> {
  String _part = 'mara';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: FicheWidth(
            max: 860,
            child: SegmentedButton<String>(
              key: const Key('journal-part'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: 'mara',
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: Text(context.tr('Actions de Mara'))),
                ButtonSegment(
                    value: 'org',
                    icon: const Icon(Icons.history),
                    label: Text(context.tr('Journal de l\'activité'))),
              ],
              selected: {_part},
              onSelectionChanged: (s) => setState(() => _part = s.first),
            ),
          ),
        ),
        Expanded(
          child: _part == 'mara' || scope == null
              ? FicheWidth(
                  max: 860,
                  child: JournalSection(
                    center: widget.center,
                    orgId: widget.org.id,
                    embedded: true,
                    onUndone: widget.onChanged,
                  ),
                )
              : FicheWidth(
                  max: 860,
                  child: ActivityLogTab(console: scope.console, org: widget.org),
                ),
        ),
      ],
    );
  }
}

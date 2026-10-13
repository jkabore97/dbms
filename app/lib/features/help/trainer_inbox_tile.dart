import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/help/help_repository.dart';
import '../../core/nav/app_scope.dart';

/// A row that exists only for Mara's trainers (136): it asks help_inbox()
/// once and draws [builder] with how many requests wait — nothing for
/// anybody else, nothing on a database without 133, nothing offline.
class TrainerInboxTile extends StatefulWidget {
  const TrainerInboxTile({super.key, required this.builder, this.help});

  final Widget Function(int waiting) builder;
  final HelpRepository? help;

  @override
  State<TrainerInboxTile> createState() => _TrainerInboxTileState();
}

class _TrainerInboxTileState extends State<TrainerInboxTile> {
  HelpInbox? _inbox;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    final repo =
        widget.help ?? HelpRepository(AppScope.maybeOf(context)?.auth.client);
    if (!repo.isConfigured) return;
    unawaited(() async {
      try {
        final i = await repo.inbox();
        if (mounted) setState(() => _inbox = i);
      } catch (_) {}
    }());
  }

  @override
  Widget build(BuildContext context) {
    final i = _inbox;
    if (i == null || !i.trainer) return const SizedBox.shrink();
    return widget.builder(i.waiting);
  }
}

import 'package:flutter/material.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/console/console_repository.dart';
import '../../core/console/models.dart';

/// The activity log across every business (048) — the platform admin's
/// oversight view. Newest first, keyset-paged, filterable to the actions a
/// moderator watches for (a deletion above all). Each row names the business,
/// so an event is legible without opening it.
class PlatformAuditScreen extends StatefulWidget {
  const PlatformAuditScreen({super.key, required this.console});

  final ConsoleRepository console;

  @override
  State<PlatformAuditScreen> createState() => _PlatformAuditScreenState();
}

class _PlatformAuditScreenState extends State<PlatformAuditScreen> {
  static const _pageSize = 50;

  /// null = every action; otherwise 'update' or 'delete'.
  String? _action;

  List<PlatformAuditEvent> _events = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _atEnd = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.console
          .platformAudit(limit: _pageSize, action: _action);
      if (!mounted) return;
      setState(() {
        _events = page;
        _atEnd = page.length < _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _atEnd || _events.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.console.platformAudit(
        limit: _pageSize,
        action: _action,
        before: _events.last.id,
      );
      if (!mounted) return;
      setState(() {
        _events = [..._events, ...page];
        _atEnd = page.length < _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _setAction(String? action) {
    if (_action == action) return;
    setState(() => _action = action);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Activité de la plateforme')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'all', label: Text('Tout')),
                ButtonSegment(value: 'update', label: Text('Modifications')),
                ButtonSegment(value: 'delete', label: Text('Suppressions')),
              ],
              selected: {_action ?? 'all'},
              onSelectionChanged: (s) =>
                  _setAction(s.first == 'all' ? null : s.first),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    ])
                  : (_events.isEmpty && !_loading)
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: Text('Aucune activité.')),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _events.length + 1,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            if (i == _events.length) return _footer(theme);
                            return _tile(theme, _events[i]);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    if (_atEnd || _events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('— fin —')),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: _loadingMore
            ? const CircularProgressIndicator()
            : OutlinedButton(
                onPressed: _more, child: const Text('Charger plus')),
      ),
    );
  }

  Widget _tile(ThemeData theme, PlatformAuditEvent e) {
    final (icon, colour) = switch (e.action) {
      'insert' => (Icons.add_circle_outline, Colors.green.shade800),
      'delete' => (Icons.remove_circle_outline, theme.colorScheme.error),
      _ => (Icons.edit_outlined, theme.colorScheme.onSurfaceVariant),
    };
    final who = (e.actorLabel != null && e.actorLabel!.isNotEmpty)
        ? e.actorLabel!
        : 'Système';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: colour),
      title: Text(e.summary?.isNotEmpty == true
          ? e.summary!
          : '${_actionWord(e.action)} · ${e.tableName}'),
      subtitle: Text('${e.orgName} · $who · ${_stamp(e.at)}'),
      isThreeLine: false,
    );
  }

  static String _actionWord(String a) => switch (a) {
        'insert' => 'Ajout',
        'delete' => 'Suppression',
        _ => 'Modification',
      };

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}

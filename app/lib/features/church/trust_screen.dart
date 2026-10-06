import 'package:flutter/material.dart';

import '../../core/association/trust_repository.dart';
import '../../core/errors.dart';
import '../../core/nav/app_scope.dart';
import '../../core/theme/kaj_card.dart';
import '../../core/theme/kaj_theme.dart';
import '../../core/theme/mara_mark.dart';

/// The association's trust level on its home (088): the level as four
/// steps, tapped open for the five pillars. Drawn only inside the app's
/// scope and once the server answers — an offline or older database simply
/// shows nothing, never a wrong level.
class TrustCard extends StatefulWidget {
  const TrustCard({super.key, required this.orgId, this.repository});

  final String orgId;

  /// For tests; the app builds one from the scope's client.
  final TrustRepository? repository;

  @override
  State<TrustCard> createState() => _TrustCardState();
}

class _TrustCardState extends State<TrustCard> {
  TrustRepository? _repo;
  TrustLevel? _t;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.read(context);
    _repo = widget.repository ??
        (scope == null ? null : TrustRepository(scope.auth.client));
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await _repo?.trust(widget.orgId);
      if (mounted) setState(() => _t = t);
    } catch (_) {
      // Offline: the card waits for the next refresh.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: KajCard(
        key: const Key('trust-card'),
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TrustScreen(orgId: widget.orgId, repository: _repo!),
            ));
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _Seal(level: t, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NIVEAU DE CONFIANCE',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(letterSpacing: 1.2, color: kMist)),
                      const SizedBox(height: 2),
                      Text(t.level,
                          key: const Key('trust-level'),
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      _Steps(step: t.step),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: kMist),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The five pillars, each said in a line with what to do; and, for Mara's
/// own admins, the verification switch.
class TrustScreen extends StatefulWidget {
  const TrustScreen({
    super.key,
    required this.orgId,
    required this.repository,
    this.platformAdmin,
  });

  final String orgId;
  final TrustRepository repository;

  /// For tests; otherwise read from the session.
  final bool? platformAdmin;

  @override
  State<TrustScreen> createState() => _TrustScreenState();
}

class _TrustScreenState extends State<TrustScreen> {
  TrustLevel? _t;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.repository.trust(widget.orgId);
      if (mounted) setState(() => _t = t);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  Future<void> _verify(bool v) async {
    setState(() => _busy = true);
    try {
      await widget.repository.setVerified(widget.orgId, v);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _t;
    final admin = widget.platformAdmin ??
        (AppScope.maybeOf(context)?.session.isPlatformAdmin ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Niveau de confiance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (t == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (t != null) ...[
            Center(child: _Seal(level: t, size: 96)),
            const SizedBox(height: 12),
            Text(t.level,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Center(child: _Steps(step: t.step, wide: true)),
            const SizedBox(height: 12),
            Text(
              'La confiance ne s\'achète pas et ne se compare pas : elle se lit '
              'dans vos comptes. Tenez-les chaque semaine et justifiez chaque '
              'dépense : c\'est ce qu\'un donateur regarde.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: kMist),
            ),
            const SizedBox(height: 20),
            for (final p in t.pillars)
              KajCard(
                key: Key('pillar-${p.key}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                    p.met ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: p.met ? maraGreen : kMist,
                  ),
                  title: Text(p.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(p.line),
                ),
              ),
            if (admin) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                key: const Key('trust-verify'),
                value: t.verified,
                onChanged: _busy ? null : _verify,
                title: const Text('Vérifiée par Mara'),
                subtitle: const Text(
                    'Réservé à Mara : après avoir vu le récépissé et les responsables.'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Four little bars, the reached ones gold.
class _Steps extends StatelessWidget {
  const _Steps({required this.step, this.wide = false});

  final int step;
  final bool wide;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < TrustLevel.levels.length; i++)
            Container(
              margin: const EdgeInsets.only(right: 4),
              width: wide ? 40 : 26,
              height: 6,
              decoration: BoxDecoration(
                color: i <= step ? maraGold : maraIndigo.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
        ],
      );
}

/// A round seal, indigo, its shield gold once verified.
class _Seal extends StatelessWidget {
  const _Seal({required this.level, required this.size});

  final TrustLevel level;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: maraIndigo, shape: BoxShape.circle),
        child: Icon(
          level.verified ? Icons.verified_user : Icons.shield_outlined,
          color: level.verified ? maraGold : maraCream,
          size: size * 0.55,
        ),
      );
}

import 'dart:ui' as ui;
import '../../../core/format/money.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/reports/models.dart';
import '../../../core/reports/reports_repository.dart';

/// A member's giving for a year, for them to keep.
///
/// Pick a person, pick a year, share the result. It shares as an image for the
/// same reason the weekly summary does: the recipient is on WhatsApp and does
/// not have this app, and very often does not have an email address either.
///
/// This screen is not offered to observers at all. A statement names one
/// person and says what they gave; an investor granted read access to the
/// books has no business with it. See ReportsHubScreen, which decides.
class GivingStatementScreen extends StatefulWidget {
  const GivingStatementScreen({
    super.key,
    required this.reports,
    required this.orgId,
    required this.orgName,
    this.currency = 'XOF',
  });

  final ReportsRepository reports;
  final String orgId;
  final String orgName;
  final String currency;

  @override
  State<GivingStatementScreen> createState() => _GivingStatementScreenState();
}

class _GivingStatementScreenState extends State<GivingStatementScreen> {
  final _cardKey = GlobalKey();

  List<ChurchMember> _members = const [];
  ChurchMember? _member;
  int _year = DateTime.now().year;

  List<GivingLine>? _lines;
  bool _loadingMembers = true;
  bool _loadingLines = false;
  bool _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loadingMembers = true;
      _error = null;
    });
    try {
      final members = await widget.reports.members(widget.orgId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loadingMembers = false;
      });
    }
  }

  Future<void> _loadStatement() async {
    final member = _member;
    if (member == null) return;

    setState(() {
      _loadingLines = true;
      _error = null;
    });
    try {
      final lines =
          await widget.reports.givingStatement(member.id, year: _year);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loadingLines = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = AuthRepository.describeError(error);
        _loadingLines = false;
      });
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError("Le relevé n'est pas prêt.");

      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError("L'image n'a pas pu être créée.");

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'releve-${_member!.fullName}-$_year.png',
            ),
          ],
          text: '${widget.orgName} — relevé $_year',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le partage a échoué sur cet appareil. '
            "Faites une capture d'écran en attendant.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _lines;
    final thisYear = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(title: const Text('Relevé de dons')),
      body: _loadingMembers
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('Membre', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                if (_members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucun membre enregistré. Les relevés sont établis pour '
                      'les personnes inscrites au registre de l\'association.',
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _member?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Choisir une personne',
                    ),
                    items: [
                      for (final m in _members)
                        DropdownMenuItem(value: m.id, child: Text(m.fullName)),
                    ],
                    onChanged: (id) {
                      setState(() {
                        _member = _members.firstWhere((m) => m.id == id);
                        _lines = null;
                      });
                      _loadStatement();
                    },
                  ),
                const SizedBox(height: 16),
                Text('Année', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    for (var y = thisYear - 2; y <= thisYear; y++)
                      ButtonSegment(value: y, label: Text('$y')),
                  ],
                  selected: {_year},
                  onSelectionChanged: (s) {
                    setState(() {
                      _year = s.first;
                      _lines = null;
                    });
                    _loadStatement();
                  },
                ),
                const SizedBox(height: 24),
                if (_loadingLines)
                  const Center(child: CircularProgressIndicator())
                else if (lines != null && _member != null) ...[
                  Center(
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: _StatementCard(
                        lines: lines,
                        member: _member!,
                        year: _year,
                        orgName: widget.orgName,
                        currency: widget.currency,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _sharing || lines.isEmpty ? null : _share,
                      icon: const Icon(Icons.share),
                      label: const Text(
                        'Partager le relevé',
                        style: TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({
    required this.lines,
    required this.member,
    required this.year,
    required this.orgName,
    required this.currency,
  });

  final List<GivingLine> lines;
  final ChurchMember member;
  final int year;
  final String orgName;
  final String currency;

  static const _ink = Color(0xFF1B2B24);
  static const _muted = Color(0xFF5F6F68);
  static const _green = Color(0xFF2E5E4E);

  @override
  Widget build(BuildContext context) {
    final money = moneyFormat(currency);
    final date = DateFormat('d MMM', 'fr_FR');
    final total = lines.fold<double>(0, (sum, l) => sum + l.amount);

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            orgName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Relevé de dons · $year',
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 16),
          Text(
            member.fullName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFE8EEEB)),
          const SizedBox(height: 12),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Aucun don enregistré pour cette année.',
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            )
          else
            ...lines.map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        date.format(l.date),
                        style: const TextStyle(fontSize: 13, color: _muted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l.displayKind,
                        style: const TextStyle(fontSize: 14, color: _ink),
                      ),
                    ),
                    Text(
                      money.format(l.amount),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0xFFE8EEEB)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              Text(
                money.format(total),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Établi le '
            '${DateFormat('d MMMM yyyy', 'fr_FR').format(DateTime.now())}',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }
}

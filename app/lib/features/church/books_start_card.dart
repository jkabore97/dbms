import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/association/books_start.dart';
import '../../core/errors.dart';
import '../../core/format/money.dart';
import '../../core/l10n/tr.dart';
import '../../core/theme/mara_mark.dart' show maraCaramel, maraDeep, maraPaper;
import '../../core/theme/mara_sheet.dart';

/// « Indiquez votre caisse de départ » (134, batch 138): on the home of an
/// association that started before the walkthrough asked, once — for an
/// administrator, while its books have no movement and no opening, until
/// it is put away (« Plus tard », for the business) or answered.
///
/// The server decides (books_start's can_set and dismissed); [hasLocalMoves]
/// hides it at once when this phone holds entries the server has not seen
/// yet. Nothing is drawn on a database without 134 (books_start null).
class BooksStartCard extends StatefulWidget {
  const BooksStartCard({
    super.key,
    required this.orgId,
    required this.books,
    this.currency = 'XOF',
    this.hasLocalMoves = false,
  });

  final String orgId;
  final BooksStartApi? books;
  final String currency;
  final bool hasLocalMoves;

  @override
  State<BooksStartCard> createState() => _BooksStartCardState();
}

class _BooksStartCardState extends State<BooksStartCard> {
  BooksStart? _start;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final books = widget.books;
    if (books == null) return;
    try {
      final s = await books.booksStart(widget.orgId);
      if (mounted) setState(() => _start = s);
    } catch (_) {
      // No signal: no card.
    }
  }

  Future<void> _later() async {
    setState(() => _gone = true);
    try {
      await widget.books?.dismissBooksStart(widget.orgId);
    } catch (_) {
      // Shown again next time; nothing was written.
    }
  }

  Future<void> _answer() async {
    final done = await showMaraSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BooksStartSheet(
        orgId: widget.orgId,
        books: widget.books!,
        currency: widget.currency,
        usual: _start?.contribution,
      ),
    );
    if (done == true && mounted) setState(() => _gone = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = _start;
    if (_gone || widget.hasLocalMoves || s == null || !s.offersCard || widget.books == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    // 320 px at text × 1.3 (or 360 px at × 1.3): the words take the icon's
    // place, as the help pills do (136).
    final narrow = MediaQuery.sizeOf(context).width / MediaQuery.textScalerOf(context).scale(1) < 300;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        key: const Key('books-start-card'),
        color: maraPaper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: maraDeep.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!narrow) ...[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: maraCaramel,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: maraDeep, size: 28),
                  ),
                  const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('Indiquez votre caisse de départ'),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: maraDeep, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                            context.tr('Ce qu\'il y avait dans la caisse avant Marakaj : vos comptes partiront juste.'),
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('books-start-close'),
                    tooltip: context.tr('Plus tard'),
                    onPressed: _later,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const Key('books-start-answer'),
                    onPressed: _answer,
                    child: Text(context.tr('Indiquer')),
                  ),
                  TextButton(
                    key: const Key('books-start-later'),
                    onPressed: _later,
                    child: Text(context.tr('Plus tard')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's two questions, as the walkthrough's step asks them.
class BooksStartSheet extends StatefulWidget {
  const BooksStartSheet({
    super.key,
    required this.orgId,
    required this.books,
    this.currency = 'XOF',
    this.usual,
  });

  final String orgId;
  final BooksStartApi books;
  final String currency;
  final ContributionDefault? usual;

  @override
  State<BooksStartSheet> createState() => _BooksStartSheetState();
}

class _BooksStartSheetState extends State<BooksStartSheet> {
  final _caisse = TextEditingController();
  final _cotisation = TextEditingController();
  late ContributionPeriod _period = widget.usual?.period ?? ContributionPeriod.month;
  final _uuid = const Uuid().v4();
  bool _busy = false;
  bool _openingSaved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final u = widget.usual;
    if (u != null) {
      _cotisation.text =
          u.amount == u.amount.roundToDouble() ? u.amount.toInt().toString() : u.amount.toString();
    }
  }

  @override
  void dispose() {
    _caisse.dispose();
    _cotisation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final caisse = parseAmount(_caisse.text.trim(), currency: widget.currency);
    final cotisationText = _cotisation.text.trim();
    final cotisation = cotisationText.isEmpty ? null : parseAmount(cotisationText, currency: widget.currency);
    if (caisse == null || caisse < 0) {
      setState(() => _error = context.tr('Un montant de 0 ou plus, s\'il vous plaît.'));
      return;
    }
    if (cotisationText.isNotEmpty && (cotisation == null || cotisation <= 0)) {
      setState(() => _error = context.tr('Une cotisation de plus de zéro, s\'il vous plaît.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_openingSaved) {
        await widget.books.setOpeningBalance(widget.orgId, caisse, clientUuid: _uuid);
        _openingSaved = true;
      }
      if (cotisation != null) {
        await widget.books.setContributionDefault(widget.orgId, cotisation, _period);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _periodLabel(ContributionPeriod p) => switch (p) {
        ContributionPeriod.week => context.tr('par semaine'),
        ContributionPeriod.month => context.tr('par mois'),
        ContributionPeriod.year => context.tr('par an'),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suffix = currencySymbol(widget.currency);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('La caisse et la cotisation'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text(context.tr('Combien y a-t-il dans la caisse aujourd\'hui ?'),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('books-start-caisse'),
              controller: _caisse,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('Montant en caisse'),
                suffixText: suffix,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Text(context.tr('0 si elle est vide. Il devient le solde de départ de vos comptes ; il ne s\'indique qu\'une fois.'),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 18),
            Text(context.tr('La cotisation habituelle'),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              key: const Key('books-start-cotisation'),
              controller: _cotisation,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('Montant'),
                suffixText: suffix,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in ContributionPeriod.values)
                  ChoiceChip(
                    key: Key('books-start-period-${p.name}'),
                    label: Text(_periodLabel(p)),
                    selected: _period == p,
                    onSelected: (_) => setState(() => _period = p),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(context.tr('Facultative. Proposée à chaque cotisation enregistrée ; vous pourrez la changer.'),
                style: theme.textTheme.bodySmall),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  key: const Key('books-start-error'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 18),
            // At least 52, taller with large text (a fixed 52 cut the « g »
            // of « Enregistrer » at × 1.3).
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: FilledButton(
                key: const Key('books-start-save'),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr('Enregistrer')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import '../../core/accounting/models.dart';
import '../../core/association/association_analytics.dart';
import '../../core/association/members.dart';
import '../../core/auth/models.dart';
import '../../core/export/report_export.dart';
import '../../core/l10n/tr.dart';
import '../../core/reports/models.dart' show accountLabel;

/// What each accounting report downloads (153): built from exactly what its
/// screen was given, for the period on screen. A summary observer was given
/// totals only by the server (006), so that is all their file holds — and
/// it says so.
///
/// The same for a shop, a farm and an association: the books are one
/// chart and one ledger whatever the business sells or collects.

String _t(String fr, [Map<String, Object?> a = const {}]) => translate(trCurrent, fr, a);

bool _summary(OrgSummary org) => org.visibility == 'summary';

String? _notice(OrgSummary org) => _summary(org)
    ? _t('Votre accès porte sur les totaux. Le détail par compte ne vous est pas communiqué.')
    : null;

double _total(List<StatementLine> lines, String name) {
  for (final l in lines) {
    if (l.isTotal && l.name == name) return l.amount;
  }
  return 0;
}

/// « Compte de résultat »: income and expenses by account, then the three
/// totals.
ReportExport incomeStatementExport(OrgSummary org, List<StatementLine> lines,
    {DateTime? from, DateTime? to, DateTime? now}) {
  final income = [for (final l in lines) if (l.section == 'income') l];
  final expense = [for (final l in lines) if (l.section == 'expense') l];
  final earned = _total(lines, 'Produits');
  final spent = _total(lines, 'Charges');
  final result = _total(lines, 'Résultat');
  final cols = [ExportColumn(_t('Code')), ExportColumn(_t('Compte')), ExportColumn(_t('Montant'), money: true)];
  return ReportExport(
    title: _t('Compte de résultat'),
    fileStem: 'compte-de-resultat',
    orgName: org.name,
    currency: org.currency,
    from: from,
    to: to,
    generatedAt: now,
    notice: income.isEmpty && expense.isEmpty ? _notice(org) : null,
    sections: [
      if (income.isNotEmpty)
        ExportSection(
          title: _t('Recettes'),
          columns: cols,
          rows: [for (final l in income) [l.code, l.label, l.amount]],
          totals: [['', _t('Total des recettes'), earned]],
        ),
      if (expense.isNotEmpty)
        ExportSection(
          title: _t('Dépenses'),
          columns: cols,
          rows: [for (final l in expense) [l.code, l.label, l.amount]],
          totals: [['', _t('Total des dépenses'), spent]],
        ),
      ExportSection(
        title: _t('Résultat'),
        columns: [ExportColumn(_t('Ligne')), ExportColumn(_t('Montant'), money: true)],
        rows: [
          [_t('Reçu'), earned],
          [_t('Dépensé'), spent],
        ],
        totals: [[result < 0 ? _t('Perte') : _t('Bénéfice'), result]],
      ),
    ],
  );
}

/// « Bilan », at a date: what the business has, what it owes, its capital.
ReportExport balanceSheetExport(OrgSummary org, List<StatementLine> lines, {DateTime? now}) {
  final cols = [ExportColumn(_t('Code')), ExportColumn(_t('Compte')), ExportColumn(_t('Montant'), money: true)];
  ExportSection? part(String section, String title) {
    final rows = [for (final l in lines) if (l.section == section) l];
    if (rows.isEmpty) return null;
    return ExportSection(
        title: title, columns: cols, rows: [for (final l in rows) [l.code, l.label, l.amount]]);
  }

  final parts = [
    part('asset', _t('Ce que possède l\'activité')),
    part('liability', _t('Ce qu\'elle doit')),
    part('equity', _t('Capital')),
  ].whereType<ExportSection>().toList();
  return ReportExport(
    title: _t('Bilan'),
    fileStem: 'bilan',
    orgName: org.name,
    currency: org.currency,
    asOf: true,
    generatedAt: now,
    notice: parts.isEmpty ? _notice(org) : null,
    sections: [
      ...parts,
      ExportSection(
        title: _t('Totaux'),
        columns: [ExportColumn(_t('Ligne')), ExportColumn(_t('Montant'), money: true)],
        totals: [
          for (final l in lines)
            if (l.isTotal) [l.label, l.amount],
        ],
      ),
    ],
  );
}

/// « Balance générale »: every account that moved, debits and credits.
ReportExport trialBalanceExport(OrgSummary org, List<TrialBalanceRow> rows,
    {DateTime? from, DateTime? to, DateTime? now}) {
  var debit = 0.0, credit = 0.0;
  for (final r in rows) {
    debit += r.debit;
    credit += r.credit;
  }
  return ReportExport(
    title: _t('Balance générale'),
    fileStem: 'balance-generale',
    orgName: org.name,
    currency: org.currency,
    from: from,
    to: to,
    generatedAt: now,
    sections: [
      ExportSection(
        columns: [
          ExportColumn(_t('Code')),
          ExportColumn(_t('Compte')),
          ExportColumn(_t('Nature')),
          ExportColumn(_t('Débit'), money: true),
          ExportColumn(_t('Crédit'), money: true),
        ],
        rows: [
          for (final r in rows) [r.code, r.label, _t(accountTypeLabel(r.type)), r.debit, r.credit],
        ],
        totals: [['', _t('Total'), '', debit, credit]],
      ),
    ],
  );
}

String _state(bool reversed, bool isReversal) => isReversal
    ? _t('correction')
    : reversed
        ? _t('corrigé')
        : '';

/// « Journal » (or Argent's « Dépenses »): every entry of the period, both
/// sides named. Nothing for a summary reader — the server sends none.
ReportExport journalExport(OrgSummary org, List<JournalRow> rows,
    {DateTime? from, DateTime? to, DateTime? now, bool expensesOnly = false}) {
  final kept = [for (final r in rows) if (!expensesOnly || r.direction == 'out') r];
  var total = 0.0;
  for (final r in kept) {
    if (!r.reversed && !r.isReversal) total += r.amount;
  }
  String sens(String d) => switch (d) {
        'in' => _t('Entrée'),
        'out' => _t('Sortie'),
        _ => _t('Transfert'),
      };
  return ReportExport(
    title: expensesOnly ? _t('Dépenses') : _t('Journal'),
    fileStem: expensesOnly ? 'depenses' : 'journal',
    orgName: org.name,
    currency: org.currency,
    from: from,
    to: to,
    generatedAt: now,
    notice: _summary(org)
        ? _t('Votre accès porte sur les totaux. Le détail des écritures ne vous est pas communiqué.')
        : null,
    sections: [
      ExportSection(
        columns: [
          ExportColumn(_t('Date'), date: true),
          ExportColumn(_t('Libellé')),
          ExportColumn(_t('Sens')),
          ExportColumn(_t('Vers')),
          ExportColumn(_t('De')),
          ExportColumn(_t('Montant'), money: true),
          ExportColumn(_t('Note')),
          ExportColumn(_t('Enregistré par')),
          ExportColumn(_t('État')),
        ],
        rows: [
          for (final r in kept)
            [
              r.occurredAt,
              r.label,
              sens(r.direction),
              r.debitLabel,
              r.creditLabel,
              r.amount,
              r.memo ?? '',
              r.recordedBy,
              _state(r.reversed, r.isReversal),
            ],
        ],
        totals: kept.isEmpty
            ? const []
            : [
                [null, _t('Total (sans les écritures corrigées)'), '', '', '', total, '', '', ''],
              ],
      ),
    ],
  );
}

/// One account's ledger with the balance after each movement.
ReportExport ledgerExport(OrgSummary org, LedgerAccount account, List<LedgerMovement> moves,
    {DateTime? from, DateTime? to, DateTime? now, bool capped = false}) {
  var debit = 0.0, credit = 0.0;
  for (final m in moves) {
    debit += m.debit;
    credit += m.credit;
  }
  final closing = moves.isEmpty ? 0.0 : moves.first.balance;
  return ReportExport(
    title: '${_t('Grand livre')} — ${account.label}',
    fileStem: 'grand-livre-${account.code}',
    orgName: org.name,
    currency: org.currency,
    from: from,
    to: to,
    generatedAt: now,
    notice: _summary(org)
        ? _t('Votre accès porte sur les totaux. Le détail des mouvements ne vous est pas communiqué.')
        : capped
            ? _t('Les {n} mouvements les plus récents de la période. Choisissez une période plus courte pour le reste.',
                {'n': moves.length})
            : null,
    sections: [
      ExportSection(
        title: '${account.code} · ${account.label} · ${_t(accountTypeLabel(account.type))}',
        columns: [
          ExportColumn(_t('Date'), date: true),
          ExportColumn(_t('Libellé')),
          ExportColumn(_t('Note')),
          ExportColumn(_t('Entré'), money: true),
          ExportColumn(_t('Sorti'), money: true),
          ExportColumn(_t('Solde'), money: true),
          ExportColumn(_t('Enregistré par')),
          ExportColumn(_t('État')),
        ],
        rows: [
          for (final m in moves)
            [m.occurredAt, m.label, m.memo ?? '', m.debit, m.credit, m.balance, m.recordedBy,
              m.reversed ? _t('corrigé') : ''],
        ],
        totals: [
          [null, _t('Total de la période'), '', debit, credit, closing, '', ''],
        ],
      ),
    ],
  );
}

/// « Plan comptable »: every account, its balance and how many lines it
/// carries — as the screen shows it (no period: a balance to date).
ReportExport chartExport(OrgSummary org, List<LedgerAccount> accounts, {DateTime? now}) {
  return ReportExport(
    title: _t('Plan comptable'),
    fileStem: 'plan-comptable',
    orgName: org.name,
    currency: org.currency,
    asOf: true,
    generatedAt: now,
    sections: [
      for (final type in accountTypes.keys)
        if (accounts.any((a) => a.type == type))
          ExportSection(
            title: _t(accountTypes[type]!),
            columns: [
              ExportColumn(_t('Code')),
              ExportColumn(_t('Compte')),
              ExportColumn(_t('Description')),
              ExportColumn(_t('État')),
              ExportColumn(_t('Écritures'), number: true),
              ExportColumn(_t('Solde'), money: true),
            ],
            rows: [
              for (final a in accounts)
                if (a.type == type)
                  [a.code, a.label, a.description ?? '', a.isActive ? '' : _t('retiré'), a.entryCount, a.balance],
            ],
            totals: [
              [
                '',
                _t('Total'),
                '',
                '',
                null,
                accounts.where((a) => a.type == type).fold<double>(0, (s, a) => s + a.balance),
              ],
            ],
          ),
    ],
  );
}

/// An association's « Analyses » (148), for the period on screen: the 12
/// months, income and expenses by category, the members' counts, the top
/// givers. The server already withheld from a summary reader every line
/// (null) and the top givers from anybody but an administrator: what is
/// null is left out of the file.
ReportExport analyticsExport(OrgSummary org, AssociationAnalytics a,
    {DateTime? from, DateTime? to, DateTime? now}) {
  final money = [ExportColumn(_t('Code')), ExportColumn(_t('Catégorie')),
    ExportColumn(_t('Montant'), money: true), ExportColumn(_t('Écritures'), number: true)];
  ExportSection cats(String title, List<CategoryAmount> list, double total) => ExportSection(
        title: title,
        columns: money,
        rows: [for (final c in list) [c.code, accountLabel(c.name), c.amount, c.entries]],
        totals: [['', _t('Total'), total, null]],
      );
  return ReportExport(
    title: _t('Analyses'),
    fileStem: 'analyses',
    orgName: org.name,
    currency: org.currency,
    from: from,
    to: to,
    generatedAt: now,
    notice: a.full ? null : _notice(org) ?? _t('Votre accès porte sur les totaux. Le détail par compte ne vous est pas communiqué.'),
    sections: [
      ExportSection(
        title: _t('Les 12 derniers mois'),
        columns: [
          ExportColumn(_t('Mois'), date: true),
          ExportColumn(_t('Entré'), money: true),
          ExportColumn(_t('Sorti'), money: true),
          ExportColumn(_t('Détenu en fin de mois'), money: true),
        ],
        rows: [for (final m in a.months) [m.month, m.income, m.expenses, m.balance]],
      ),
      if (a.income != null) cats(_t('Recettes par catégorie'), a.income!, a.incomeTotal),
      if (a.expenses != null) cats(_t('Dépenses par catégorie'), a.expenses!, a.expensesTotal),
      ExportSection(
        title: _t('Membres'),
        columns: [ExportColumn(_t('Ligne')), ExportColumn(_t('Nombre'), number: true)],
        rows: [
          [_t('Inscrits'), a.registered],
          if (a.gave != null) [_t('Ont donné sur la période'), a.gave],
          if (a.upToDate != null) [_t('À jour'), a.upToDate],
          if (a.due != null) [_t('À payer'), a.due],
          if (a.late != null) [_t('En retard'), a.late],
        ],
      ),
      if (a.topGivers != null && a.topGivers!.isNotEmpty)
        ExportSection(
          title: _t('Plus gros donateurs'),
          columns: [ExportColumn(_t('Membre')), ExportColumn(_t('Montant'), money: true)],
          rows: [for (final g in a.topGivers!) [g.name, g.amount]],
        ),
    ],
  );
}

/// An association's members (148), as a table: the names, phones, notes
/// and dates every member of the business may read; this year's amounts
/// and where each stands on the cotisation only when the server gave them
/// (full visibility).
ReportExport membersExport(OrgSummary org, MembersList list, {int? year, DateTime? now}) {
  final amounts = list.withAmounts;
  final y = year ?? (now ?? DateTime.now()).year;
  String status(MemberDues? d) => switch (d?.status) {
        DuesStatus.upToDate => _t('À jour'),
        DuesStatus.due => _t('À payer'),
        DuesStatus.late => d!.lateSince == null
            ? _t('En retard')
            : _t('En retard depuis le {date}', {'date': ReportExport.iso(d.lateSince!)}),
        null => '',
      };
  return ReportExport(
    title: _t('Membres'),
    fileStem: 'membres',
    orgName: org.name,
    currency: org.currency,
    asOf: true,
    generatedAt: now,
    notice: amounts ? null : _t('Les montants ne vous sont pas communiqués.'),
    sections: [
      ExportSection(
        columns: [
          ExportColumn(_t('Nom')),
          ExportColumn(_t('Téléphone')),
          ExportColumn(_t('Note')),
          ExportColumn(_t('Membre depuis'), date: true),
          if (amounts) ...[
            ExportColumn(_t('Donné en {year}', {'year': y}), money: true),
            ExportColumn(_t('Cotisations'), money: true),
            ExportColumn(_t('Dons'), money: true),
            ExportColumn(_t('Dernier don'), date: true),
            ExportColumn(_t('Cotisation')),
          ],
        ],
        rows: [
          for (final m in list.members)
            [
              m.fullName,
              m.phone ?? '',
              m.note ?? '',
              m.since,
              if (amounts) ...[m.givenYear, m.cotisationsYear, m.donsYear, m.lastGivenOn, status(m.dues)],
            ],
        ],
      ),
    ],
  );
}

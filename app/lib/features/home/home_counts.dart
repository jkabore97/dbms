import 'package:flutter/widgets.dart';

import '../../core/nav/app_scope.dart';
import '../../core/notify/bell.dart';

/// The bar's numbers on a business home (115): what asks for action —
/// orders to answer, articles at zero or under their alert level, invoices
/// past due, credits past their date, invitations not claimed, a farm's
/// supplies low and its batches with nothing written today. Read by the
/// app's one bell keeper (home_counts on the server) with the bell's own
/// rhythm — live, on return to the app, every minute — and drawn on the
/// home's places, which the business frame keeps on every page.
mixin HomeCounts<T extends StatefulWidget> on State<T> {
  Bell? _countsBell;
  String? _countsOrg;

  /// The business whose numbers this home shows; empty for none yet.
  String get countsOrgId;

  /// Whether this person is shown the numbers at all: an observer only
  /// watches — nothing on the bar asks them to act (batch 115).
  bool get countsShown => true;

  void _countsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notify = AppScope.maybeOf(context)?.notify;
    final bell = notify != null &&
            notify.isConfigured &&
            countsOrgId.isNotEmpty &&
            countsShown
        ? notify.bell
        : null;
    if (identical(bell, _countsBell) && _countsOrg == countsOrgId) return;
    _detachCounts();
    _countsBell = bell;
    _countsOrg = countsOrgId;
    bell
      ?..watchHome(countsOrgId)
      ..addListener(_countsChanged);
  }

  void _detachCounts() {
    final bell = _countsBell;
    if (bell == null) return;
    bell
      ..removeListener(_countsChanged)
      ..unwatchHome(_countsOrg!);
    _countsBell = null;
  }

  @override
  void dispose() {
    _detachCounts();
    super.dispose();
  }

  /// One number ('orders', 'bookings', 'articles', 'invoices', 'credit',
  /// 'invitations', 'supplies', 'livestock'); 0 until read.
  int homeCount(String key) => _countsBell?.homeCount(countsOrgId, key) ?? 0;

  /// Whether the server's numbers arrived (a database before 115 has none).
  bool get homeCountsKnown => _countsBell?.knowsHome(countsOrgId) ?? false;
}

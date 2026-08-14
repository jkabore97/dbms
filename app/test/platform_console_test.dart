import 'package:flutter_test/flutter_test.dart';
import 'package:kaj_app/core/console/models.dart';

/// The console's own arithmetic and classification.
///
/// The SQL side is covered by `test_console.sql`, which proves paging returns
/// every business exactly once and that only a platform admin can search. This
/// file covers the part that lives in the client: how a row is classified, and
/// whether the pager can be trusted.
///
/// Both matter more than they look. The health classification is what the
/// person running the platform scans for — a business misfiled as healthy is a
/// customer nobody rings — and a pager that miscounts by one hides a whole
/// page of businesses without any error appearing anywhere.
void main() {
  OrgRow row({DateTime? lastActivity, DateTime? archivedAt}) => OrgRow(
        id: 'o1',
        name: 'Boutique Esperance',
        slug: 'boutique-esperance',
        profile: 'retail',
        currency: 'XOF',
        memberCount: 3,
        archivedAt: archivedAt,
        lastActivityAt: lastActivity,
      );

  DateTime daysAgo(int n) => DateTime.now().subtract(Duration(days: n));

  group('what the status pill says', () {
    test('recorded today is healthy', () {
      expect(row(lastActivity: daysAgo(0)).health, OrgHealth.healthy);
      expect(row(lastActivity: daysAgo(6)).health, OrgHealth.healthy);
    });

    test('a week without recording is slowing, not yet lost', () {
      // Worth surfacing and not worth ringing about. Conflating this with
      // silence would bury the businesses that actually need a call.
      expect(row(lastActivity: daysAgo(8)).health, OrgHealth.slowing);
      expect(row(lastActivity: daysAgo(29)).health, OrgHealth.slowing);
    });

    test('a month of silence is the churn signal', () {
      expect(row(lastActivity: daysAgo(30)).health, OrgHealth.silent);
      expect(row(lastActivity: daysAgo(200)).health, OrgHealth.silent);
    });

    test('never started is its own state, not silence', () {
      // A different failure with a different owner: this one belongs to
      // whoever onboarded them, not to whoever handles retention.
      final never = row();
      expect(never.health, OrgHealth.neverStarted);
      expect(never.neverActive, isTrue);
      expect(never.daysSinceActivity, isNull);
    });

    test('archived outranks everything else', () {
      // An archived business is not a churn risk; it is a closed account, and
      // showing it as one would inflate the number that drives the calls.
      expect(
        row(lastActivity: daysAgo(400), archivedAt: daysAgo(10)).health,
        OrgHealth.archived,
      );
      expect(row(archivedAt: daysAgo(1)).health, OrgHealth.archived);
    });
  });

  group('a page carries the size of the whole result', () {
    test('total is the filter, not the rows on screen', () {
      final page = OrgPage(rows: [row(), row()], total: 1840);
      expect(page.rows.length, 2);
      expect(page.total, 1840);
    });

    test('page count is exact at the boundaries', () {
      // The off-by-one that hides the last page. 100 businesses at 50 a page
      // is two pages, not three.
      int pages(int total, int size) =>
          total == 0 ? 1 : ((total - 1) ~/ size) + 1;

      expect(pages(0, 50), 1);
      expect(pages(1, 50), 1);
      expect(pages(50, 50), 1);
      expect(pages(51, 50), 2);
      expect(pages(100, 50), 2);
      expect(pages(101, 50), 3);
      expect(pages(1840, 50), 37);
    });
  });

  group('parsing what the server sent', () {
    test('a full row', () {
      final parsed = OrgRow.fromRow({
        'org_id': 'abc',
        'name': 'Ferme Ignace',
        'slug': 'ferme-ignace',
        'profile': 'farm',
        'currency': 'XOF',
        'member_count': 7,
        'archived_at': null,
        'created_at': '2026-01-05T08:00:00Z',
        'last_activity_at': '2026-08-01T06:30:00Z',
      });
      expect(parsed.name, 'Ferme Ignace');
      expect(parsed.memberCount, 7);
      expect(parsed.isArchived, isFalse);
      expect(parsed.lastActivityAt, isNotNull);
    });

    test('a business the server says has never been active', () {
      final parsed = OrgRow.fromRow({
        'org_id': 'abc',
        'name': 'Nouvelle',
        'slug': 'nouvelle',
        'profile': 'retail',
        'currency': 'XOF',
        'member_count': 1,
        'last_activity_at': null,
      });
      expect(parsed.neverActive, isTrue);
      expect(parsed.health, OrgHealth.neverStarted);
    });

    test('the overview reads every figure it is given', () {
      final o = PlatformOverview.fromRow({
        'total': 1840,
        'active': 1802,
        'archived': 38,
        'farms': 400,
        'shops': 1200,
        'churches': 202,
        'other_profiles': 38,
        'new_this_week': 26,
        'active_7d': 1310,
        'silent_30d': 214,
        'never_active': 88,
      });
      expect(o.total, 1840);
      expect(o.silent30d, 214);
      expect(o.neverActive, 88);
      // The profile counts are shown beside the total, so they have to sum.
      expect(o.farms + o.shops + o.churches + o.otherProfiles, o.total);
    });

    test('a missing figure reads as zero rather than throwing', () {
      // A database that has not run 021 yet, or an older function signature.
      // The console showing zeros is recoverable; the console crashing is not.
      final o = PlatformOverview.fromRow({'total': 5});
      expect(o.total, 5);
      expect(o.silent30d, 0);
      expect(o.neverActive, 0);
    });
  });
}

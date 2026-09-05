import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// The analytics of 036, read from the server where the sales live.
///
/// Every function here is gated server-side: the owner ones raise unless the
/// caller has full visibility of that business, the platform ones unless the
/// caller is a platform admin. The client passes an org id and a window; the
/// server decides whether that means anything, so nothing here re-checks a
/// permission it cannot enforce.
///
/// A window is a number of days back from now, or null for all of time. It is
/// turned into a `p_since` timestamp on the client so the server function stays
/// a plain range scan.
class AnalyticsRepository {
  AnalyticsRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  static String? _since(int? days) {
    if (days == null) return null;
    return DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();
  }

  /// Everything the owner analytics screen shows, fetched in one pass.
  Future<OwnerAnalytics> owner(String orgId, {int? days = 30}) async {
    final client = _requireClient();
    final since = _since(days);
    final params = {'p_org_id': orgId, 'p_since': ?since};

    final results = await Future.wait([
      client.rpc('org_sales_headline', params: params),
      client.rpc('org_product_performance', params: params),
      client.rpc('org_sales_by_hour', params: params),
      client.rpc('org_sales_by_weekday', params: params),
      client.rpc('org_sales_daily', params: params),
    ]);

    final headlineRows = results[0] as List<dynamic>;
    return OwnerAnalytics(
      headline: headlineRows.isEmpty
          ? SalesHeadline.empty
          : SalesHeadline.fromRow(
              Map<String, dynamic>.from(headlineRows.first as Map)),
      products: (results[1] as List<dynamic>)
          .map((r) => ProductPerformance.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(),
      byHour: (results[2] as List<dynamic>)
          .map((r) => TimeBucket.fromHour(Map<String, dynamic>.from(r as Map)))
          .toList(),
      byWeekday: (results[3] as List<dynamic>)
          .map((r) => TimeBucket.fromWeekday(Map<String, dynamic>.from(r as Map)))
          .toList(),
      daily: (results[4] as List<dynamic>)
          .map((r) => DayPoint.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList(),
    );
  }

  /// The platform-wide total across every business.
  Future<PlatformHeadline> platformHeadline({int? days = 30}) async {
    final client = _requireClient();
    final since = _since(days);
    final rows = await client.rpc('platform_analytics_headline',
        params: {'p_since': ?since}) as List<dynamic>;
    return rows.isEmpty
        ? PlatformHeadline.empty
        : PlatformHeadline.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Every business, ranked by revenue, for the platform console.
  Future<List<BusinessPerformance>> platformBusinesses({int? days = 30}) async {
    final client = _requireClient();
    final since = _since(days);
    final rows = await client.rpc('platform_business_performance',
        params: {'p_since': ?since}) as List<dynamic>;
    return rows
        .map((r) => BusinessPerformance.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
        "Cette version de l'application a été compilée sans serveur. "
        'Reconstruisez-la avec SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
      );
    }
    return client;
  }
}

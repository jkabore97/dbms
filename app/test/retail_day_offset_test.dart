import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaj_app/core/retail/retail_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The till's home asks for the shop's own day (145, batch 149): the
/// phone's date and its UTC offset, so a shop at UTC+1 sees a sale made at
/// 00:30 today and not on yesterday's figures. A database without 145 yet
/// answers « function not found », and the home falls back to the old
/// two-argument door — the UTC day, as before — rather than going blank.
void main() {
  const row = {
    'sales_total': 6000,
    'returns_total': 0,
    'net_sales': 6000,
    'sale_count': 2,
    'items_sold': 3,
  };

  ({RetailRepository repo, List<Map<String, dynamic>> bodies}) build({required bool has145}) {
    final bodies = <Map<String, dynamic>>[];
    final client = SupabaseClient('https://example.supabase.co', 'anon-key',
        httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      expect(request.url.path, '/rest/v1/rpc/store_day');
      if (body.containsKey('p_utc_offset_minutes') && !has145) {
        return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message': 'Could not find the function public.store_day(p_on, p_org_id, p_utc_offset_minutes) in the schema cache',
            }),
            404,
            headers: {'content-type': 'application/json'}, request: request);
      }
      return http.Response(jsonEncode([row]), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);
    return (repo: RetailRepository(client), bodies: bodies);
  }

  test('the day is asked with the phone\'s own UTC offset', () async {
    final (:repo, :bodies) = build(has145: true);
    final on = DateTime(2026, 10, 15, 0, 30);
    final day = await repo.day('o1', on: on);
    expect(bodies.single, {
      'p_org_id': 'o1',
      'p_on': '2026-10-15',
      'p_utc_offset_minutes': on.timeZoneOffset.inMinutes,
    });
    expect(day.saleCount, 2);
    expect(day.netSales, 6000);
  });

  test('a UTC date says offset 0', () async {
    final (:repo, :bodies) = build(has145: true);
    await repo.day('o1', on: DateTime.utc(2026, 10, 15));
    expect(bodies.single['p_utc_offset_minutes'], 0);
  });

  test('before 145 is live: the old door, and the home still has its figures', () async {
    final (:repo, :bodies) = build(has145: false);
    final day = await repo.day('o1', on: DateTime(2026, 10, 15));
    expect(bodies, hasLength(2));
    expect(bodies.last, {'p_org_id': 'o1', 'p_on': '2026-10-15'});
    expect(day.saleCount, 2);
  });
}

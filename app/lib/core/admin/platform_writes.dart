import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors.dart';

/// The platform's writes, through the command center's journal (105).
///
/// Every change Mara makes from the app — a setting from the Pro console,
/// the Wave console, the couriers' share, the two-step switch, Réglages; a
/// gift of cauris; a tool opened; an archive — goes through these two, so
/// each is a line in the Journal with its « Annuler ». On a database
/// before 105 they fall back to the older doors (061, 100, 014), which do
/// the same thing without the journal: the app is never ahead of its
/// migration by a broken button.

/// One setting, by its key. Returns the journal line's id, or null when
/// nothing changed (or on a database before 105).
Future<String?> writePlatformSetting(
    SupabaseClient client, String key, Object? value) async {
  try {
    final id = await client
        .rpc('platform_set_setting', params: {'p_key': key, 'p_value': value});
    return id is String ? id : null;
  } catch (error) {
    if (!isSchemaOutOfDate(error)) rethrow;
    await client
        .rpc('set_platform_setting', params: {'p_key': key, 'p_value': value});
    return null;
  }
}

/// One act of platform_bulk (105) for one business: 'cauris', 'unlock',
/// 'message', 'archive' or 'restore'. Returns its journal line's id; throws
/// the business's own refusal in French. On a database before 105,
/// [fallback] does the write instead and null is returned.
Future<String?> platformActOn(
  SupabaseClient client,
  String action,
  String orgId,
  Map<String, Object?> args, {
  required Future<void> Function() fallback,
}) async {
  final Object? v;
  try {
    v = await client.rpc('platform_bulk', params: {
      'p_action': action,
      'p_orgs': [orgId],
      'p_args': args,
    });
  } catch (error) {
    if (!isSchemaOutOfDate(error)) rethrow;
    await fallback();
    return null;
  }
  final result = v is Map ? v : const {};
  final failed = result['failed'];
  if (failed is List && failed.isNotEmpty) {
    final first = failed.first;
    throw StateError(first is Map ? '${first['error']}' : '$first');
  }
  final actions = result['actions'];
  return actions is List && actions.isNotEmpty ? '${actions.first}' : null;
}

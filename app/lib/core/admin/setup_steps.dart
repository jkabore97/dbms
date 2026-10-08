import 'package:supabase_flutter/supabase_flutter.dart';

/// The optional steps of the first setup that Mara turned off for this
/// business's kind (107's setup_steps_off): 'vitrine' and 'position' for a
/// shop or a farm, 'members' and 'vitrine' for an association. Never a
/// required one — the server leaves them out.
///
/// Empty on any failure — no server, no signal, a database before 107 —
/// which is today's walkthrough: every step.
Future<Set<String>> setupStepsOff(SupabaseClient? client, String orgId) async {
  if (client == null) return const {};
  try {
    final v = await client.rpc('setup_steps_off', params: {'p_org': orgId});
    return {
      for (final s in (v is List ? v : const [])) '$s',
    };
  } catch (_) {
    return const {};
  }
}

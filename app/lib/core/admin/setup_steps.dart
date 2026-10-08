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

/// What a business already says when its first setup opens: its phone,
/// its area (the invoice header's address), its vitrine sentence and, for
/// an association, its kind (102) — given when it was created (111).
class SetupKnown {
  const SetupKnown({this.phone, this.address, this.about, this.kind});

  final String? phone;
  final String? address;
  final String? about;
  final String? kind;
}

/// Read by the setup screens once, as they open; null on any failure (no
/// server, no signal): the steps then start empty, as before.
Future<SetupKnown?> setupKnown(SupabaseClient? client, String orgId) async {
  if (client == null) return null;
  String? text(Object? v) {
    final t = '${v ?? ''}'.trim();
    return t.isEmpty ? null : t;
  }

  try {
    final row = await client
        .from('orgs')
        .select('phone, address, storefront_blurb, association_kind')
        .eq('id', orgId)
        .maybeSingle();
    if (row == null) return null;
    return SetupKnown(
      phone: text(row['phone']),
      address: text(row['address']),
      about: text(row['storefront_blurb']),
      kind: text(row['association_kind']),
    );
  } catch (_) {
    return null;
  }
}

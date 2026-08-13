import 'package:supabase_flutter/supabase_flutter.dart';

/// The people a business pays, and what it owes them.
///
/// Separate from `RetailRepository` because these are not shop things — a
/// church pays a caretaker and a farm pays a night watchman, and 012 is
/// written for all three. It lives under retail only because M5 is where it
/// was asked for.
///
/// Everything here needs an org admin, enforced by RLS rather than by this
/// class: what a colleague earns is the most sensitive number in a small
/// business, more than the takings, because everyone can see the takings.

/// Somebody on the payroll. Not necessarily somebody with an account — most
/// people who get paid never install the app.
class Employee {
  const Employee({
    required this.id,
    required this.fullName,
    this.kind = 'casual',
    this.hourlyRate = 0,
    this.salary = 0,
    this.roleTitle,
    this.phone,
    this.isActive = true,
  });

  final String id;
  final String fullName;

  /// 'permanent' | 'casual'
  final String kind;
  final double hourlyRate;
  final double salary;
  final String? roleTitle;
  final String? phone;
  final bool isActive;

  bool get isCasual => kind == 'casual';

  factory Employee.fromRow(Map<String, dynamic> row) {
    double parse(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

    return Employee(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      kind: (row['kind'] as String?) ?? 'casual',
      hourlyRate: parse(row['hourly_rate']),
      salary: parse(row['salary']),
      roleTitle: row['role_title'] as String?,
      phone: row['phone'] as String?,
      isActive: row['is_active'] as bool? ?? true,
    );
  }
}

/// Hours somebody has worked that nobody has paid for yet.
class UnpaidWork {
  const UnpaidWork({
    required this.employeeId,
    required this.fullName,
    required this.hours,
    required this.shifts,
    required this.owed,
  });

  final String employeeId;
  final String fullName;
  final double hours;
  final int shifts;
  final double owed;

  factory UnpaidWork.fromRow(Map<String, dynamic> row) {
    double parse(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

    return UnpaidWork(
      employeeId: row['employee_id'] as String,
      fullName: row['full_name'] as String,
      hours: parse(row['hours']),
      shifts: (row['shifts'] as num?)?.toInt() ?? 0,
      owed: parse(row['owed']),
    );
  }
}

class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  String? get currentUserId => _client?.auth.currentUser?.id;

  Future<List<Employee>> employees(String orgId,
      {bool activeOnly = true}) async {
    final client = _requireClient();
    var query = client
        .from('employees')
        .select('id, full_name, kind, hourly_rate, salary, role_title, '
            'phone, is_active')
        .eq('org_id', orgId);
    if (activeOnly) query = query.eq('is_active', true);

    final rows = await query.order('full_name');
    return (rows as List)
        .map((r) => Employee.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<UnpaidWork>> owed(String orgId) async {
    final client = _requireClient();
    final rows = await client.rpc('unpaid_shifts', params: {
      'p_org_id': orgId,
    }) as List<dynamic>;

    return rows
        .map((r) => UnpaidWork.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<String> addEmployee({
    required String orgId,
    required String fullName,
    String kind = 'casual',
    double? hourlyRate,
    double? salary,
    String? phone,
    String? roleTitle,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('add_employee', params: {
      'p_org_id': orgId,
      'p_full_name': fullName,
      'p_kind': kind,
      if (hourlyRate != null) 'p_hourly_rate': hourlyRate,
      if (salary != null) 'p_salary': salary,
      if (phone != null && phone.isNotEmpty) 'p_phone': phone,
      if (roleTitle != null && roleTitle.isNotEmpty) 'p_role_title': roleTitle,
      if (currentUserId != null) 'p_actor': currentUserId,
    });
    return id as String;
  }

  /// A day worked. Idempotent by [clientUuid], so a retry does not pay for the
  /// same afternoon twice.
  Future<String> recordShift({
    required String orgId,
    required String employeeId,
    required double hours,
    DateTime? workedOn,
    String? note,
    String? clientUuid,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('record_shift', params: {
      'p_org_id': orgId,
      'p_employee_id': employeeId,
      'p_hours': hours,
      if (workedOn != null) 'p_worked_on': _date(workedOn),
      if (note != null && note.isNotEmpty) 'p_note': note,
      if (clientUuid != null) 'p_client_uuid': clientUuid,
    });
    return id as String;
  }

  /// Pays somebody. With no [amount] the server works out what is owed — the
  /// unpaid hours for a casual, the salary for permanent staff — and marks the
  /// shifts it covers, so the same hours cannot be paid again.
  Future<String> pay({
    required String orgId,
    required String employeeId,
    double? amount,
    String? label,
    String method = 'cash',
    String? clientUuid,
  }) async {
    final client = _requireClient();
    final id = await client.rpc('pay_employee', params: {
      'p_org_id': orgId,
      'p_employee_id': employeeId,
      if (amount != null) 'p_amount': amount,
      if (label != null && label.isNotEmpty) 'p_label': label,
      'p_method': method,
      if (clientUuid != null) 'p_client_uuid': clientUuid,
    });
    return id as String;
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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

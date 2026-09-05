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

/// One person as the staff screen sees them: the engagement, where they work,
/// and what they are owed right now.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.fullName,
    this.phone,
    this.roleTitle,
    this.employment,
    this.kind = 'casual',
    this.salary = 0,
    this.hourlyRate = 0,
    this.entityName,
    this.departmentName,
    this.startedOn,
    this.endedOn,
    this.endReason,
    this.isActive = true,
    this.userId,
    this.accountName,
    this.unpaidHours = 0,
    this.owed = 0,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? roleTitle;

  /// permanent | fixed_term | daily | apprentice | volunteer. Distinct from
  /// [kind], which is how they are paid rather than what the engagement is.
  final String? employment;
  final String kind;

  final double salary;
  final double hourlyRate;
  final String? entityName;
  final String? departmentName;
  final DateTime? startedOn;
  final DateTime? endedOn;
  final String? endReason;
  final bool isActive;

  /// Set when this person has been matched to an account. Null for most of a
  /// payroll: being paid and being able to open the books are different
  /// things, and linking the two grants nothing either way.
  final String? userId;
  final String? accountName;

  final double unpaidHours;
  final double owed;

  bool get isVolunteer => employment == 'volunteer';

  factory StaffMember.fromRow(Map<String, dynamic> row) {
    double number(Object? v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('\$v') ?? 0);
    DateTime? when(Object? v) => v == null ? null : DateTime.tryParse('\$v');

    return StaffMember(
      id: row['id'] as String,
      fullName: row['full_name'] as String,
      phone: row['phone'] as String?,
      roleTitle: row['role_title'] as String?,
      employment: row['employment'] as String?,
      kind: (row['kind'] as String?) ?? 'casual',
      salary: number(row['salary']),
      hourlyRate: number(row['hourly_rate']),
      entityName: row['entity_name'] as String?,
      departmentName: row['department_name'] as String?,
      startedOn: when(row['started_on']),
      endedOn: when(row['ended_on']),
      endReason: row['end_reason'] as String?,
      isActive: row['is_active'] as bool? ?? true,
      userId: row['user_id'] as String?,
      accountName: row['account_name'] as String?,
      unpaidHours: number(row['unpaid_hours']),
      owed: number(row['owed']),
    );
  }
}

class StaffRepository {
  StaffRepository(this._client);

  final SupabaseClient? _client;

  bool get isConfigured => _client != null;

  String? get currentUserId => _client?.auth.currentUser?.id;

  /// The directory: everyone on the books, where they work, and what they
  /// are owed, in one read. Refused server-side for anyone who is not an org
  /// admin — it raises rather than returning nothing, so somebody not
  /// entitled sees an error and not an empty payroll.
  Future<List<StaffMember>> directory(String orgId,
      {bool includePast = false}) async {
    final client = _requireClient();
    final rows = await client.rpc('staff_directory', params: {
      'p_org_id': orgId,
      'p_include_past': includePast,
    }) as List<dynamic>;

    return rows
        .map((r) => StaffMember.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> updateEmployee({
    required String employeeId,
    String? fullName,
    String? phone,
    String? roleTitle,
    String? employment,
    String? kind,
    double? salary,
    double? hourlyRate,
    String? nationalId,
    String? emergencyContact,
    String? emergencyPhone,
    String? notes,
  }) async {
    final client = _requireClient();
    await client.rpc('update_employee', params: {
      'p_employee_id': employeeId,
      if (fullName != null && fullName.isNotEmpty) 'p_full_name': fullName,
      if (phone != null && phone.isNotEmpty) 'p_phone': phone,
      if (roleTitle != null && roleTitle.isNotEmpty) 'p_role_title': roleTitle,
      if (employment != null && employment.isNotEmpty)
        'p_employment': employment,
      if (kind != null && kind.isNotEmpty) 'p_kind': kind,
      'p_salary': ?salary,
      'p_hourly_rate': ?hourlyRate,
      if (nationalId != null && nationalId.isNotEmpty)
        'p_national_id': nationalId,
      if (emergencyContact != null && emergencyContact.isNotEmpty)
        'p_emergency_contact': emergencyContact,
      if (emergencyPhone != null && emergencyPhone.isNotEmpty)
        'p_emergency_phone': emergencyPhone,
      if (notes != null && notes.isNotEmpty) 'p_notes': notes,
    });
  }

  /// Somebody leaving. Refused by the server while wages are outstanding,
  /// which is the point: unpaid hours that leave the screen are unpaid hours
  /// nobody pays.
  Future<void> endEmployment({
    required String employeeId,
    required String reason,
    DateTime? endedOn,
    String? note,
  }) async {
    final client = _requireClient();
    await client.rpc('end_employment', params: {
      'p_employee_id': employeeId,
      'p_reason': reason,
      if (endedOn != null) 'p_ended_on': _date(endedOn),
      if (note != null && note.isNotEmpty) 'p_note': note,
    });
  }

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
      'p_hourly_rate': ?hourlyRate,
      'p_salary': ?salary,
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
      'p_client_uuid': ?clientUuid,
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
      'p_amount': ?amount,
      if (label != null && label.isNotEmpty) 'p_label': label,
      'p_method': method,
      'p_client_uuid': ?clientUuid,
    });
    return id as String;
  }

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
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

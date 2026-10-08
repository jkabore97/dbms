/// « Signaler un problème » as the platform reads it (113's
/// platform_reports): what it is about, the words, who and how to answer,
/// the vitrine or the order it names.
class ProblemReport {
  const ProblemReport({
    required this.id,
    required this.topic,
    required this.message,
    this.at,
    this.reporter,
    this.contact,
    this.orgId,
    this.orgName,
    this.slug,
    this.orderId,
    this.answer,
    this.handled = false,
  });

  final String id;

  /// 'order', 'vitrine', 'payment', 'delivery', 'app' or 'other'.
  final String topic;
  final String message;
  final DateTime? at;
  final String? reporter;

  /// The proved number, else the profile's, else the e-mail.
  final String? contact;
  final String? orgId;
  final String? orgName;
  final String? slug;
  final String? orderId;
  final String? answer;
  final bool handled;

  factory ProblemReport.fromJson(Map<String, dynamic> j) => ProblemReport(
        id: j['id'] as String,
        topic: (j['topic'] as String?) ?? 'other',
        message: (j['message'] as String?) ?? '',
        at: j['at'] == null ? null : DateTime.tryParse('${j['at']}')?.toLocal(),
        reporter: j['reporter'] as String?,
        contact: j['contact'] as String?,
        orgId: j['org_id'] as String?,
        orgName: j['org_name'] as String?,
        slug: j['slug'] as String?,
        orderId: j['order_id'] as String?,
        answer: j['answer'] as String?,
        handled: j['status'] == 'handled',
      );
}

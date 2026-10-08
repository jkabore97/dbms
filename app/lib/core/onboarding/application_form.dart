/// The business request page as Mara set it (107's
/// platform_settings.application_form): a welcome text, the kinds that may
/// be asked for, and extra questions in order. The name, the address and
/// the kind are always asked; none of that is in here. No form at all is
/// today's page — [ApplicationForm.fromJson] of null is null.
class ApplicationForm {
  const ApplicationForm({
    this.welcome,
    this.kinds,
    this.questions = const [],
  });

  /// A few words at the top of the page.
  final String? welcome;

  /// 'association' | 'farm' | 'retail' that may be asked for; null: all.
  final List<String>? kinds;
  final List<FormQuestion> questions;

  /// The three kinds the page can offer, in the page's order.
  static const allKinds = ['association', 'farm', 'retail'];

  bool offers(String kind) => kinds == null || kinds!.contains(kind);

  /// Nothing set: what the server keeps as no form.
  bool get isEmpty =>
      (welcome == null || welcome!.trim().isEmpty) &&
      (kinds == null || kinds!.length == allKinds.length) &&
      questions.isEmpty;

  static ApplicationForm? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final kinds = j['kinds'];
    final questions = j['questions'];
    final welcome = '${j['welcome'] ?? ''}'.trim();
    return ApplicationForm(
      welcome: welcome.isEmpty ? null : welcome,
      kinds: kinds is List ? [for (final k in kinds) '$k'] : null,
      questions: questions is List
          ? [
              for (final q in questions)
                if (q is Map) FormQuestion.fromJson(Map<String, dynamic>.from(q)),
            ]
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
        if (welcome != null && welcome!.trim().isNotEmpty) 'welcome': welcome!.trim(),
        if (kinds != null) 'kinds': kinds,
        if (questions.isNotEmpty) 'questions': [for (final q in questions) q.toJson()],
      };
}

/// The four kinds of question: a line of text, one choice among a list, a
/// number, yes or no.
enum QuestionType {
  text,
  choice,
  number,
  yesno;

  static QuestionType parse(String? name) => QuestionType.values
      .firstWhere((t) => t.name == name, orElse: () => QuestionType.text);
}

class FormQuestion {
  const FormQuestion({
    this.id,
    required this.label,
    this.help,
    this.required = false,
    this.type = QuestionType.text,
    this.options = const [],
  });

  /// Given by the server on saving; kept, so answers already given still
  /// name their question. Null for a question not saved yet.
  final String? id;
  final String label;
  final String? help;
  final bool required;
  final QuestionType type;

  /// The answers offered, for [QuestionType.choice].
  final List<String> options;

  factory FormQuestion.fromJson(Map<String, dynamic> j) {
    final options = j['options'];
    final help = '${j['help'] ?? ''}'.trim();
    return FormQuestion(
      id: j['id'] as String?,
      label: '${j['label'] ?? ''}',
      help: help.isEmpty ? null : help,
      required: j['required'] == true,
      type: QuestionType.parse(j['type'] as String?),
      options: options is List ? [for (final o in options) '$o'] : const [],
    );
  }

  Map<String, Object?> toJson() => {
        if (id != null) 'id': id,
        'label': label.trim(),
        if (help != null && help!.trim().isNotEmpty) 'help': help!.trim(),
        'required': required,
        'type': type.name,
        if (type == QuestionType.choice) 'options': options,
      };

  FormQuestion copyWith({
    String? label,
    String? help,
    bool? required,
    QuestionType? type,
    List<String>? options,
  }) =>
      FormQuestion(
        id: id,
        label: label ?? this.label,
        help: help ?? this.help,
        required: required ?? this.required,
        type: type ?? this.type,
        options: options ?? this.options,
      );
}

/// One answer as the application keeps it: the question as it was asked
/// (its words then), and what was answered.
class ApplicationAnswer {
  const ApplicationAnswer({
    required this.label,
    required this.type,
    required this.value,
  });

  final String label;
  final QuestionType type;

  /// A string, a number or a boolean, as the server kept it.
  final Object? value;

  factory ApplicationAnswer.fromJson(Map<String, dynamic> j) => ApplicationAnswer(
        label: '${j['label'] ?? ''}',
        type: QuestionType.parse(j['type'] as String?),
        value: j['value'],
      );
}

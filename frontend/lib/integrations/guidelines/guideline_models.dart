/// Authored guidelines (backend/guidelines): "how to play" text attached to
/// tags such as `baroque`, plus measurable rubrics the backend checks on
/// every phrase.
library;

double? _double(Object? value) => (value as num?)?.toDouble();

/// One measurable rule: `metric operator value [valueMax] unit`.
class Rubric {
  final int? id;
  final String label;
  final String sourceText;
  final String metric;
  final String operator;
  final double value;
  final double? valueMax;
  final String unit;
  final String appliesTo;
  final double passRate;
  final String severity;
  final String failMessage;
  final String suggestion;
  final bool enabled;

  const Rubric({
    this.id,
    this.label = '',
    this.sourceText = '',
    required this.metric,
    required this.operator,
    required this.value,
    this.valueMax,
    required this.unit,
    this.appliesTo = 'all',
    this.passRate = 0.8,
    this.severity = 'minor',
    this.failMessage = '',
    this.suggestion = '',
    this.enabled = true,
  });

  factory Rubric.fromJson(Map<String, dynamic> json) => Rubric(
    id: json['id'] as int?,
    label: json['label'] as String? ?? '',
    sourceText: json['source_text'] as String? ?? '',
    metric: json['metric'] as String? ?? '',
    operator: json['operator'] as String? ?? 'gt',
    value: _double(json['value']) ?? 0,
    valueMax: _double(json['value_max']),
    unit: json['unit'] as String? ?? '',
    appliesTo: json['applies_to'] as String? ?? 'all',
    passRate: _double(json['pass_rate']) ?? 0.8,
    severity: json['severity'] as String? ?? 'minor',
    failMessage: json['fail_message'] as String? ?? '',
    suggestion: json['suggestion'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'label': label,
    'source_text': sourceText,
    'metric': metric,
    'operator': operator,
    'value': value,
    'value_max': valueMax,
    'unit': unit,
    'applies_to': appliesTo,
    'pass_rate': passRate,
    'severity': severity,
    'fail_message': failMessage,
    'suggestion': suggestion,
    'enabled': enabled,
  };

  Rubric copyWith({
    String? label,
    String? sourceText,
    String? metric,
    String? operator,
    double? value,
    double? Function()? valueMax,
    String? unit,
    String? appliesTo,
    double? passRate,
    String? severity,
    String? failMessage,
    String? suggestion,
    bool? enabled,
  }) => Rubric(
    id: id,
    label: label ?? this.label,
    sourceText: sourceText ?? this.sourceText,
    metric: metric ?? this.metric,
    operator: operator ?? this.operator,
    value: value ?? this.value,
    valueMax: valueMax != null ? valueMax() : this.valueMax,
    unit: unit ?? this.unit,
    appliesTo: appliesTo ?? this.appliesTo,
    passRate: passRate ?? this.passRate,
    severity: severity ?? this.severity,
    failMessage: failMessage ?? this.failMessage,
    suggestion: suggestion ?? this.suggestion,
    enabled: enabled ?? this.enabled,
  );
}

class Guideline {
  final int? id;
  final String title;
  final String body;
  final List<String> tags;
  final String status; // "draft" | "published"
  final int version;
  final String ownerName;

  /// The server says the signed-in person may change it.
  final bool editable;
  final List<Rubric> rubrics;

  const Guideline({
    this.id,
    required this.title,
    this.body = '',
    this.tags = const [],
    this.status = 'draft',
    this.version = 1,
    this.ownerName = '',
    this.editable = false,
    this.rubrics = const [],
  });

  bool get published => status == 'published';

  factory Guideline.fromJson(Map<String, dynamic> json) => Guideline(
    id: json['id'] as int?,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    tags: [for (final t in json['tags'] as List<dynamic>? ?? const []) '$t'],
    status: json['status'] as String? ?? 'draft',
    version: json['version'] as int? ?? 1,
    ownerName: json['owner_name'] as String? ?? '',
    editable: json['editable'] as bool? ?? false,
    rubrics: [
      for (final r in json['rubrics'] as List<dynamic>? ?? const [])
        Rubric.fromJson(r as Map<String, dynamic>),
    ],
  );

  /// The body the create/update endpoints take.
  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'tags': tags,
    'status': status,
    'rubrics': [for (final r in rubrics) r.toJson()],
  };
}

/// One range of the author's text the parser understood, and as what
/// ("metric", "comparator", "value", "unit", "applies_to").
class ParsedSpan {
  final int start;
  final int end;
  final String role;
  const ParsedSpan(this.start, this.end, this.role);
}

/// What /api/guidelines/rubrics/parse made of a sentence.
class RubricParse {
  /// The structured rule, or null when the text couldn't be turned into one.
  final Map<String, dynamic>? rule;
  final List<ParsedSpan> spans;
  final List<String> missing;
  final List<String> unrecognised;
  final String message;

  const RubricParse({
    this.rule,
    this.spans = const [],
    this.missing = const [],
    this.unrecognised = const [],
    this.message = '',
  });

  factory RubricParse.fromJson(Map<String, dynamic> json) => RubricParse(
    rule: json['rule'] as Map<String, dynamic>?,
    spans: [
      for (final s in json['matched_spans'] as List<dynamic>? ?? const [])
        ParsedSpan(
          (s as Map<String, dynamic>)['start'] as int,
          s['end'] as int,
          s['role'] as String,
        ),
    ],
    missing: [
      for (final m in json['missing'] as List<dynamic>? ?? const []) '$m',
    ],
    unrecognised: [
      for (final u in json['unrecognised'] as List<dynamic>? ?? const []) '$u',
    ],
    message: json['message'] as String? ?? '',
  );

  /// [base] with the parsed rule applied (keeps its messages and pass rate).
  Rubric apply(Rubric base, String text) {
    final rule = this.rule;
    if (rule == null) return base.copyWith(sourceText: text);
    return base.copyWith(
      sourceText: text,
      metric: rule['metric'] as String?,
      operator: rule['operator'] as String?,
      value: _double(rule['value']),
      valueMax: () => _double(rule['value_max']),
      unit: rule['unit'] as String?,
      appliesTo: rule['applies_to'] as String?,
    );
  }
}

class MetricInfo {
  final String name;
  final String label;
  final String description;
  final List<String> units;
  const MetricInfo({
    required this.name,
    required this.label,
    this.description = '',
    required this.units,
  });
}

/// What the editor's dropdowns offer, from /api/guidelines/vocabulary.
class RubricVocabulary {
  final List<MetricInfo> metrics;
  final Map<String, String> unitLabels;
  final List<String> operators;
  final List<String> appliesTo;
  final List<String> severities;

  const RubricVocabulary({
    required this.metrics,
    required this.unitLabels,
    required this.operators,
    required this.appliesTo,
    required this.severities,
  });

  factory RubricVocabulary.fromJson(Map<String, dynamic> json) =>
      RubricVocabulary(
        metrics: [
          for (final m in json['metrics'] as List<dynamic>? ?? const [])
            MetricInfo(
              name: (m as Map<String, dynamic>)['name'] as String,
              label: m['label'] as String? ?? m['name'] as String,
              description: m['description'] as String? ?? '',
              units: [for (final u in m['units'] as List<dynamic>) '$u'],
            ),
        ],
        unitLabels: {
          for (final u in json['units'] as List<dynamic>? ?? const [])
            (u as Map<String, dynamic>)['name'] as String:
                u['label'] as String? ?? u['name'] as String,
        },
        operators: [for (final o in json['operators'] as List<dynamic>) '$o'],
        appliesTo: [for (final a in json['applies_to'] as List<dynamic>) '$a'],
        severities: [for (final s in json['severities'] as List<dynamic>) '$s'],
      );

  MetricInfo? metric(String name) {
    for (final m in metrics) {
      if (m.name == name) return m;
    }
    return null;
  }

  static const operatorLabels = {
    'gt': 'more than',
    'gte': 'at least',
    'lt': 'less than',
    'lte': 'at most',
    'between': 'between',
  };
}

import 'package:hu_accomponist/integrations/auth/auth_user.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_repository.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

/// A verified contributor.
const grace = AuthUser(
  id: 3,
  email: 'grace@example.com',
  name: 'Grace',
  roles: ['contributor'],
);

const testVocabulary = RubricVocabulary(
  metrics: [
    MetricInfo(
      name: 'note_gap',
      label: 'Gap between notes',
      units: ['ms', 'sec', 'pct_of_note', 'pct_of_beat'],
    ),
    MetricInfo(
      name: 'sounding_ratio',
      label: 'Sounding length',
      units: ['pct_of_note', 'ratio'],
    ),
  ],
  unitLabels: {
    'ms': 'ms',
    'sec': 'sec',
    'pct_of_note': '% of the note',
    'pct_of_beat': '% of a beat',
    'ratio': '× written length',
  },
  operators: ['gt', 'gte', 'lt', 'lte', 'between'],
  appliesTo: ['all', 'staccato', 'legato', 'unmarked'],
  severities: ['minor', 'major'],
);

const baroque = Guideline(
  id: 1,
  title: 'Baroque: detached touch',
  body: 'Notes should be highly detached in this era.',
  tags: ['baroque'],
  status: 'published',
  editable: true,
  rubrics: [
    Rubric(id: 4, metric: 'note_gap', operator: 'gt', value: 0.5, unit: 'sec'),
  ],
);

/// Answers like the guidelines API, recording what was asked.
class FakeGuidelineRepository implements GuidelineRepository {
  final List<String> calls = [];
  List<Guideline> stored = [baroque];
  Guideline? saved;
  ApiException? saveError;

  @override
  Future<List<Guideline>> forScore(String scoreId) async {
    calls.add('forScore $scoreId');
    return stored;
  }

  @override
  Future<List<Guideline>> list({String? token, bool mine = false}) async {
    calls.add(
      token == null ? 'list published' : 'list ${mine ? 'mine' : 'all'} $token',
    );
    return stored;
  }

  @override
  Future<List<String>> tags() async => ['baroque', 'bach', 'romantic'];

  @override
  Future<RubricVocabulary> vocabulary() async => testVocabulary;

  @override
  Future<RubricParse> parse({
    required String token,
    required String text,
  }) async {
    calls.add('parse $text');
    return const RubricParse(
      rule: {
        'metric': 'note_gap',
        'operator': 'gt',
        'value': 0.5,
        'value_max': null,
        'unit': 'sec',
        'applies_to': 'all',
      },
      spans: [
        ParsedSpan(0, 4, 'metric'),
        ParsedSpan(26, 35, 'comparator'),
        ParsedSpan(36, 39, 'value'),
        ParsedSpan(40, 43, 'unit'),
      ],
    );
  }

  @override
  Future<Guideline> create({
    required String token,
    required Guideline guideline,
  }) async {
    calls.add('create $token');
    if (saveError != null) throw saveError!;
    return saved = guideline;
  }

  @override
  Future<Guideline> update({
    required String token,
    required int id,
    required Guideline guideline,
  }) async {
    calls.add('update $id');
    if (saveError != null) throw saveError!;
    return saved = guideline;
  }

  @override
  Future<void> delete({required String token, required int id}) async {
    calls.add('delete $id');
  }
}

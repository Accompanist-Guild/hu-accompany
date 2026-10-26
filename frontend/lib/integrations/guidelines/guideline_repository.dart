import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

/// The guidelines API (backend/guidelines/views.py). Reading is open;
/// writing takes the signed-in person's token and only works for admins and
/// verified contributors (the server answers 403 to anyone else). Every
/// failure is an [ApiException] worded for the person.
abstract class GuidelineRepository {
  /// Published guidelines whose tags match the score's.
  Future<List<Guideline>> forScore(String scoreId);

  /// Without a [token]: the published guidelines everyone sees. With an
  /// author's token, [mine] gives only their own (drafts included), else
  /// everything they can see.
  Future<List<Guideline>> list({String? token, bool mine = false});
  Future<List<String>> tags();
  Future<RubricVocabulary> vocabulary();
  Future<RubricParse> parse({required String token, required String text});
  Future<Guideline> create({
    required String token,
    required Guideline guideline,
  });
  Future<Guideline> update({
    required String token,
    required int id,
    required Guideline guideline,
  });
  Future<void> delete({required String token, required int id});
}

class ApiGuidelineRepository implements GuidelineRepository {
  const ApiGuidelineRepository({this.client = const ApiClient()});

  final ApiClient client;

  static Map<String, String> _bearer(String token) => {
    'Authorization': 'Bearer $token',
  };

  static Map<String, dynamic> _decode(http.Response response) =>
      jsonDecode(utf8.decode(ApiClient.ensureOk(response).bodyBytes))
          as Map<String, dynamic>;

  static List<Guideline> _guidelines(Map<String, dynamic> body) => [
    for (final g in body['guidelines'] as List<dynamic>? ?? const [])
      Guideline.fromJson(g as Map<String, dynamic>),
  ];

  @override
  Future<List<Guideline>> forScore(String scoreId) async => _guidelines(
    _decode(
      await client.getJson(
        '/api/guidelines/for-score/${Uri.encodeComponent(scoreId)}',
      ),
    ),
  );

  @override
  Future<List<Guideline>> list({String? token, bool mine = false}) async =>
      _guidelines(
        _decode(
          await client.getJson(
            '/api/guidelines',
            query: token == null ? null : {mine ? 'mine' : 'all': '1'},
            headers: token == null ? null : _bearer(token),
          ),
        ),
      );

  @override
  Future<List<String>> tags() async => [
    for (final t
        in _decode(await client.getJson('/api/guidelines/tags'))['tags']
            as List<dynamic>)
      (t as Map<String, dynamic>)['slug'] as String,
  ];

  @override
  Future<RubricVocabulary> vocabulary() async => RubricVocabulary.fromJson(
    _decode(await client.getJson('/api/guidelines/vocabulary')),
  );

  @override
  Future<RubricParse> parse({
    required String token,
    required String text,
  }) async => RubricParse.fromJson(
    _decode(
      await client.postJson('/api/guidelines/rubrics/parse', {
        'text': text,
      }, headers: _bearer(token)),
    ),
  );

  @override
  Future<Guideline> create({
    required String token,
    required Guideline guideline,
  }) async => Guideline.fromJson(
    _decode(
          await client.postJson(
            '/api/guidelines',
            guideline.toJson(),
            headers: _bearer(token),
          ),
        )['guideline']
        as Map<String, dynamic>,
  );

  @override
  Future<Guideline> update({
    required String token,
    required int id,
    required Guideline guideline,
  }) async => Guideline.fromJson(
    _decode(
          await client.putJson(
            '/api/guidelines/$id',
            guideline.toJson(),
            headers: _bearer(token),
          ),
        )['guideline']
        as Map<String, dynamic>,
  );

  @override
  Future<void> delete({required String token, required int id}) async {
    ApiClient.ensureOk(
      await client.delete('/api/guidelines/$id', headers: _bearer(token)),
    );
  }
}

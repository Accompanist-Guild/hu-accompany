import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/integrations/quiz/Quiz_Generator.dart';
import 'package:hu_accomponist/integrations/scores/score_repository.dart';
import 'package:hu_accomponist/integrations/server/ServerDiscovery.dart';

/// A check of a running server, using the app's own code, with the same build settings a release gets. It skips
/// itself unless a server address is given, so the normal test run is unaffected. Run it against a local copy of
/// the production backend before a release, or against the deployed service after `setup.sh`:
///
///     flutter test test/live_server_smoke_test.dart \
///       --dart-define=SERVER_URL=https://my-service-abc.a.run.app --dart-define=APP_KEY=<the key>
///
/// (http://localhost:PORT works for a copy on this machine. The server must hold at least one score.)
void main() {
  final skip = AppConstants.serverUrl.isEmpty
      ? 'Give --dart-define=SERVER_URL=... to run this against a real server.'
      : null;

  test('the app talks to the configured server and never searches the network', () async {
    expect(ServerDiscovery.isConfigured, isTrue);
    final base = await ServerDiscovery.resolveBaseUrl();
    expect(base, ServerDiscovery.configuredBaseUrl(AppConstants.serverUrl));
  }, skip: skip);

  test('score search and download work through the app code', () async {
    const repo = ScoreRepository();

    final found = await repo.search('a');
    expect(found, isNotEmpty, reason: 'the server holds no scores, or refused the app key');

    final loaded = await repo.load(found.first);
    expect(loaded.musicXml, contains('score-partwise'));
  }, skip: skip);

  test('quiz generation reaches the server and is not refused for the key', () async {
    try {
      final set = await QuizGenerator.generate('The Middle Ages (ad 476 - ad 1450)', length: 5, seed: 1);
      expect(set.isEmpty, isFalse);
    } on Exception catch (e) {
      // A topic the server has no questions for is an answer from the server. The quiz shows the server's own
      // message, so a refused key reads "This app isn't allowed to use the server." (server/middleware.py).
      expect('$e', isNot(contains("isn't allowed to use the server")));
      expect('$e', isNot(contains('unreachable')));
    }
  }, skip: skip);

  test('the server refuses a request that has no app key', () async {
    final base = await ServerDiscovery.resolveBaseUrl();
    final response = await http.get(Uri.parse('$base/api/scores/search?q=a'));
    // Only meaningful when the build has a key, because that means the server has one too.
    expect(response.statusCode, 401);
  }, skip: skip ?? (AppConstants.appKey.isEmpty ? 'Needs --dart-define=APP_KEY=... too.' : null));
}

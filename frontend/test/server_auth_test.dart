import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hu_accomponist/integrations/feedback/Phrase_send2_server.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/integrations/quiz/Quiz_Generator.dart';
import 'package:hu_accomponist/integrations/scores/score_repository.dart';
import 'package:hu_accomponist/integrations/server/ServerDiscovery.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';
import 'package:hu_accomponist/integrations/server/server_auth.dart';

/// The deployed server answers 401 to any request without the app's key. The app reaches the server in several
/// different ways (the shared client, and four places that make their own requests), and one of them forgetting the
/// header would break just that feature in a public build, where nobody is watching the console. So this starts a
/// real server and checks that each way in sends the key.
void main() {
  group('ServerAuth.headers', () {
    tearDown(() => ServerAuth.useKey(''));

    test('sends nothing extra when there is no key (a local server with none set)', () {
      ServerAuth.useKey('');

      expect(ServerAuth.headers(), isEmpty);
      expect(ServerAuth.headers({'Content-Type': 'application/json'}), {
        'Content-Type': 'application/json',
      });
    });

    test('adds the key and keeps the caller\'s own headers', () {
      ServerAuth.useKey('k-123');
      final mine = {'Authorization': 'Bearer t'};

      expect(ServerAuth.headers(mine), {'Authorization': 'Bearer t', 'X-App-Key': 'k-123'});
      expect(mine, {'Authorization': 'Bearer t'}, reason: 'the caller\'s map must not be changed');
    });

    test('a caller cannot replace the key', () {
      ServerAuth.useKey('k-123');

      expect(ServerAuth.headers({'x-app-key': 'other', 'X-App-Key': 'other'})['X-App-Key'], 'k-123');
    });
  });

  group('every request to the server carries the key', () {
    late HttpServer server;
    late List<HttpRequest> seen;
    final keys = <String, String?>{};

    setUp(() async {
      keys.clear();
      seen = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        seen.add(request);
        keys['${request.method} ${request.uri.path}'] = request.headers.value('X-App-Key');
        await request.drain<void>();
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{}');
        await request.response.close();
      });
      ServerDiscovery.useBaseUrl('http://127.0.0.1:${server.port}');
      ServerAuth.useKey('k-123');
    });

    tearDown(() async {
      ServerAuth.useKey('');
      ServerDiscovery.invalidateCache();
      await server.close(force: true);
    });

    /// Runs [call], ignoring what the caller makes of the empty `{}` answer: only the request matters here.
    Future<void> run(Future<Object?> Function() call) async {
      try {
        await call();
      } catch (_) {}
    }

    test('through the shared client', () async {
      final file = File('${Directory.systemTemp.path}/server_auth_test.wav')..writeAsBytesSync([1, 2, 3]);
      addTearDown(file.deleteSync);
      const client = ApiClient();

      await run(() => client.getJson('/get'));
      await run(() => client.postJson('/post', {'a': 1}));
      await run(() => client.delete('/delete'));
      await run(() => client.postFile('/file', field: 'file', filePath: file.path));

      expect(keys, {
        'GET /get': 'k-123',
        'POST /post': 'k-123',
        'DELETE /delete': 'k-123',
        'POST /file': 'k-123',
      });
    });

    test('through the quiz, score, and feedback calls that make their own requests', () async {
      await run(() => QuizGenerator.generate('baroque'));
      await run(() => const ScoreRepository().search('bach'));
      await run(() => SessionSummaryService.fetchSummary('session-1'));
      await run(
        () => PhraseUploadService.sendPhrase(
          phraseNumber: 1,
          bpm: 90,
          timeSignature: '4/4',
          piece: const PieceInfo(title: 'T', composer: 'C', composedDate: '1722'),
          expectedNotes: const [],
          userNotes: const [],
        ),
      );

      expect(seen, hasLength(4), reason: 'one request each; got ${seen.map((r) => r.uri.path).toList()}');
      expect(keys.values.toSet(), {'k-123'}, reason: jsonEncode(keys));
    });
  });
}

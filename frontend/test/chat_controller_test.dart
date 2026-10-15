import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:hu_accomponist/features/hum/chat_controller.dart';
import 'package:hu_accomponist/features/hum/hum_controller.dart';
import 'package:hu_accomponist/integrations/hum/chat_models.dart';
import 'package:hu_accomponist/integrations/hum/song_project.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

import 'support/hum_fakes.dart';

/// The chat, typed and spoken, with the hum page as its host.
void main() {
  late FakePlayer song;
  late FakePlayer voice;
  late FakeRecorder mic;
  late FakeHumRepository repository;
  late HumController controller;
  late ChatController chat;

  setUp(() async {
    song = FakePlayer();
    voice = FakePlayer();
    mic = FakeRecorder(path: '/tmp/said.wav');
    repository = FakeHumRepository();
    controller = HumController(
      repository: repository,
      recorder: FakeRecorder(),
      player: song,
      rawPlayer: FakePlayer(),
      chatRecorder: mic,
      voicePlayer: voice,
      sharer: FakeSharer(),
      store: MemorySavedHumStore(),
    );
    chat = controller.chat;
    await controller.startHum();
    await controller.stopHum();
  });

  tearDown(() => controller.dispose());

  double drums() => controller.band.project!.track('drums')!.volume;
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('permission to share with the AI services', () {
    // Talk mode sends requests to Google Gemini and ElevenLabs. Nothing may leave, and the microphone
    // may not even start, until the person has said yes.
    late FakeRecorder voiceMic;
    final extra = <HumController>[];
    var asked = 0;

    HumController withConsent(Future<bool> Function() ask) {
      final c = HumController(
        repository: repository,
        recorder: FakeRecorder(),
        player: FakePlayer(),
        rawPlayer: FakePlayer(),
        chatRecorder: voiceMic,
        voicePlayer: FakePlayer(),
        sharer: FakeSharer(),
        store: MemorySavedHumStore(),
        ensureTalkConsent: () {
          asked++;
          return ask();
        },
      );
      extra.add(c);
      return c;
    }

    setUp(() {
      voiceMic = FakeRecorder(path: '/tmp/said.wav');
      asked = 0;
    });

    tearDown(() async {
      for (final c in extra) {
        c.dispose();
      }
      extra.clear();
    });

    Future<HumController> ready(Future<bool> Function() ask) async {
      final c = withConsent(ask);
      await c.startHum();
      await c.stopHum();
      return c;
    }

    test('typing sends nothing until they agree', () async {
      final c = await ready(() async => false);
      await c.chat.send('softer drums');

      expect(repository.chatTexts, isEmpty);
      expect(
        c.chat.entries.where((e) => e.speaker == ChatSpeaker.user),
        isEmpty,
      );
      expect(c.chat.entries.single.speaker, ChatSpeaker.notice);
      expect(c.chat.entries.single.text, contains('AI services'));
      expect(c.chat.state, ChatVoice.idle);
    });

    test(
      'speaking does not even ask for the microphone until they agree',
      () async {
        final c = await ready(() async => false);
        await c.chat.tapMic();

        expect(voiceMic.permissionRequests, 0);
        expect(voiceMic.starts, 0);
        expect(c.chat.state, ChatVoice.idle);
        expect(c.chat.entries.single.speaker, ChatSpeaker.notice);
      },
    );

    test('they are asked before the microphone permission', () async {
      var micAskedBeforeConsent = true;
      final c = await ready(() async {
        micAskedBeforeConsent = voiceMic.permissionRequests > 0;
        return true;
      });
      await c.chat.tapMic();

      expect(micAskedBeforeConsent, isFalse);
      expect(voiceMic.starts, 1);
      expect(c.chat.state, ChatVoice.listening);
    });

    test('agreeing lets the edit through', () async {
      final c = await ready(() async => true);
      await c.chat.send('softer drums');

      expect(repository.chatTexts, ['softer drums']);
      expect(c.band.project!.track('drums')!.volume, closeTo(0.4, 1e-9));
    });

    test('stopping a recording does not ask a second time', () async {
      final c = await ready(() async => true);
      await c.chat.tapMic(); // start: asks
      await c.chat.tapMic(); // stop and send: must not ask again
      await settle();

      expect(asked, 1);
      expect(repository.chatVoicePaths, ['/tmp/said.wav']);
    });

    test(
      'a second tap while the question is open does not open a second question',
      () async {
        final answer = Completer<bool>();
        final c = await ready(() => answer.future);
        final first = c.chat.send('softer drums');
        final second = c.chat.send('softer drums');
        answer.complete(true);
        await Future.wait([first, second]);

        expect(asked, 1);
        expect(repository.chatTexts, ['softer drums']);
      },
    );

    test('a question that fails counts as no', () async {
      final c = await ready(() async => throw StateError('no screen'));
      await c.chat.send('softer drums');

      expect(repository.chatTexts, isEmpty);
      expect(c.chat.entries.single.speaker, ChatSpeaker.notice);
    });

    test(
      'with no question wired in, nothing changes (existing behaviour)',
      () async {
        await chat.send('softer drums');
        expect(repository.chatTexts, ['softer drums']);
      },
    );
  });

  group('typing', () {
    test('an edit changes the song, plays it, and can be undone', () async {
      await chat.send('softer drums');

      expect(chat.entries.map((e) => (e.speaker, e.text)), [
        (ChatSpeaker.user, 'softer drums'),
        (ChatSpeaker.assistant, 'Drums are softer now.'),
      ]);
      expect(drums(), closeTo(0.4, 1e-9));
      expect(controller.undoLabel, 'drums quieter');
      expect(song.played, hasLength(2)); // the new version plays
      expect(voice.urls, isEmpty); // typed replies are silent by default
      expect(chat.state, ChatVoice.idle);
    });

    test('undo and redo by chat step through the edits', () async {
      await chat.send('softer drums');
      await chat.send('undo that');
      expect(drums(), closeTo(0.6, 1e-9));
      await chat.send('redo');
      expect(drums(), closeTo(0.4, 1e-9));
      expect(song.played, hasLength(4));
    });

    test(
      'an undo or redo that fails becomes a notice, not an error that escapes',
      () async {
        // The edit itself is guarded; the step back and forward must be too.
        final failing = _FailingStepsHost(controller.band.project!);
        final guarded = ChatController(
          repository: repository,
          host: failing,
          recorder: FakeRecorder(),
          voice: FakePlayer(),
        );
        addTearDown(guarded.dispose);
        var notices = 0;
        for (final intent in ['undo', 'redo']) {
          repository.onChat = (text, project) =>
              ChatReply(heard: text, intent: intent, reply: 'Done.');
          await guarded.send(intent); // no exception may reach here
          final said = guarded.entries
              .where((e) => e.speaker == ChatSpeaker.notice)
              .toList();
          expect(said, hasLength(++notices), reason: intent);
          expect(said.last.text, contains("didn't go through"), reason: intent);
          expect(guarded.state, ChatVoice.idle, reason: intent);
        }
      },
    );

    test('a question or a refusal changes nothing', () async {
      repository.onChat = (text, project) => const ChatReply(
        heard: 'quieter',
        intent: 'clarify',
        reply: 'Which part: the drums or everything?',
      );
      await chat.send('quieter');
      expect(chat.entries.last.text, 'Which part: the drums or everything?');
      expect(controller.canUndo, isFalse);
      expect(song.played, hasLength(1));
    });

    test('server trouble becomes a reply, not a crash', () async {
      repository.chatError = const ApiException(
        'Too many requests',
        status: 429,
      );
      await chat.send('softer drums');
      expect(chat.entries.last.text, 'Too many requests');
      expect(chat.state, ChatVoice.idle);
      repository.chatError = Exception('no network');
      await chat.send('softer drums');
      expect(chat.entries.last.text, contains("couldn't reach the server"));
    });

    test('blank messages are ignored', () async {
      await chat.send('   ');
      expect(chat.entries, isEmpty);
      expect(repository.chatTexts, isEmpty);
    });

    test(
      'with spoken replies on, the reply is said first and then the song plays',
      () async {
        chat.toggleSpeakReplies();
        await chat.send('softer drums');

        expect(voice.urls.single.path, endsWith('/chat/speech/s-0.60'));
        expect(chat.state, ChatVoice.speaking);
        expect(song.played, hasLength(1)); // not over the voice

        voice.finish();
        await settle();
        expect(chat.state, ChatVoice.idle);
        expect(song.played, hasLength(2));
      },
    );
  });

  group('speaking', () {
    test('listen, think, speak, then play the new song', () async {
      await chat.tapMic();
      expect(chat.state, ChatVoice.listening);
      expect(mic.starts, 1);

      await chat.tapMic(); // stop and send
      expect(repository.chatVoicePaths, ['/tmp/said.wav']);
      expect(chat.entries.first.text, 'softer drums'); // what was heard
      expect(chat.state, ChatVoice.speaking);

      voice.finish();
      await settle();
      expect(song.played, hasLength(2));
    });

    test('tapping the mic while it speaks cuts it off and listens', () async {
      await chat.tapMic();
      await chat.tapMic();
      expect(chat.state, ChatVoice.speaking);

      await chat.tapMic();

      expect(voice.stops, greaterThan(0));
      expect(chat.state, ChatVoice.listening);
      voice.finish();
      await settle();
      expect(
        song.played,
        hasLength(1),
      ); // the interrupted turn's song waits for the next
    });

    test('listening stops by itself after a while', () async {
      controller.dispose();
      song = FakePlayer();
      mic = FakeRecorder(path: '/tmp/said.wav');
      controller = HumController(
        repository: repository,
        recorder: FakeRecorder(),
        player: song,
        rawPlayer: FakePlayer(),
        chatRecorder: mic,
        voicePlayer: FakePlayer(),
        sharer: FakeSharer(),
        store: MemorySavedHumStore(),
      );
      // a short limit, through a chat of its own
      final quick = ChatController(
        repository: repository,
        host: controller,
        recorder: mic,
        voice: FakePlayer(),
        maxListen: const Duration(milliseconds: 20),
      );
      await controller.startHum();
      await controller.stopHum();
      await quick.tapMic();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(repository.chatVoicePaths, hasLength(1));
      quick.dispose();
    });

    test('with the microphone off, it says to type instead', () async {
      mic.allowed = false;
      await chat.tapMic();
      expect(chat.state, ChatVoice.idle);
      expect(chat.entries.single.text, contains('type instead'));
    });

    test(
      'when the voice service is down, the text answer stands and the song still plays',
      () async {
        voice.urlError = Exception('voice down');
        await chat.tapMic();
        await chat.tapMic();

        expect(chat.state, ChatVoice.idle);
        expect(
          chat.entries.map((e) => e.text),
          contains('Drums are softer now.'),
        );
        expect(
          chat.entries.last.text,
          contains("Voice replies aren't available"),
        );
        expect(song.played, hasLength(2));
      },
    );
  });

  test('before any hum, the chat asks for one', () async {
    controller.dispose();
    controller = HumController(
      repository: FakeHumRepository(),
      recorder: FakeRecorder(),
      player: FakePlayer(),
      rawPlayer: FakePlayer(),
      chatRecorder: FakeRecorder(),
      voicePlayer: FakePlayer(),
      sharer: FakeSharer(),
      store: MemorySavedHumStore(),
    );
    await controller.chat.send('softer drums');
    expect(
      controller.chat.entries.last.text,
      'Hum a tune first, then tell me how to change it.',
    );
  });
}

/// A host whose song can be edited but whose undo and redo always fail (the way a real one might if
/// the band engine throws part-way).
class _FailingStepsHost implements ChatHost {
  _FailingStepsHost(this._project);
  final SongProject _project;

  @override
  Future<SongProject?> projectForChat() async => _project;
  @override
  String get notReadyReason => '';
  @override
  bool get canUndo => true;
  @override
  bool get canRedo => true;
  @override
  Future<void> applyChatEdit(SongProject project, String label) async {}
  @override
  Future<bool> undoEdit() async => throw Exception('engine stopped');
  @override
  Future<bool> redoEdit() async => throw Exception('engine stopped');
  @override
  Future<void> playSong() async {}
  @override
  Future<void> stopSong() async {}
}

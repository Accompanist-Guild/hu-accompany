import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/features/guides/guideline_editor_page.dart';
import 'package:hu_accomponist/features/guides/guides_page.dart';
import 'package:hu_accomponist/features/onboarding/onboarding_store.dart';
import 'package:hu_accomponist/features/practice/Phrase_Feedback_Pill.dart';
import 'package:hu_accomponist/features/practice/how_to_play_card.dart';
import 'package:hu_accomponist/features/practice/score_practice_widgets.dart';
import 'package:hu_accomponist/features/practice/session_summary_panel.dart';
import 'package:hu_accomponist/features/shell/app_shell.dart';
import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_user.dart';
import 'package:hu_accomponist/integrations/auth/session_store.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/integrations/scores/score_models.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

import 'support/auth_fakes.dart';
import 'support/guideline_fakes.dart';

PhraseReport reportWith(List<Map<String, dynamic>> findings) =>
    PhraseReport.fromJson({
      'phrase': 2,
      'bpm': 96.0,
      'time_signature': '4/4',
      'bars': [2, 2],
      'scores': {'overall': 88, 'pitch': 90, 'guidelines': 0},
      'feedback': findings,
      'session_id': 's',
      'guidelines_applied': [
        {'id': 1, 'version': 2, 'title': 'Baroque: detached touch'},
      ],
    });

const guidelineFinding = {
  'bars': 2,
  'category': 'guideline',
  'severity': 'minor',
  'confidence': 1.0,
  'message': 'Detach the notes more.',
  'details': {
    'guideline_title': 'Baroque: detached touch',
    'suggestion': 'Lift between notes.',
  },
};

final summaryJson = {
  'session_id': 's',
  'phases': [1, 2],
  'phase2': {
    'Summary': {
      'summary': 'Pitch accuracy was strong.',
      'positive_feedback': ['Pitch accuracy was strong.'],
      'feedback': [],
    },
    'Era': {'label': 'Baroque'},
    'Guidelines': {
      'type': 'guidelines',
      'guidelines': [
        {
          'id': 1,
          'version': 2,
          'title': 'Baroque: detached touch',
          'phrases_checked': 3,
        },
        {'id': 2, 'version': 1, 'title': 'Steady pulse', 'phrases_checked': 3},
      ],
      'rubrics': [
        {
          'guideline_title': 'Baroque: detached touch',
          'label': 'Gap between notes',
          'phrases_checked': 3,
          'phrases_failed': 2,
          'worst_bars': [4, 7],
          'suggestion': 'Lift between notes.',
        },
      ],
      'feedback': [],
    },
  },
};

Future<void> pumpPage(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Future<AuthController> signedIn(AuthUser user) async {
  final auth = AuthController(
    store: MemorySessionStore(StoredSession(token: 'tok', user: user)),
    repository: FakeAuthRepository()..me_ = user,
  );
  await auth.restore();
  return auth;
}

void main() {
  group('models', () {
    test('a piece sends its score id and tags with every phrase', () {
      const piece = PieceInfo(
        title: 'Prelude',
        composer: 'Bach',
        composedDate: '1722',
        scoreId: '42',
        tags: ['baroque'],
      );
      expect(piece.toJson(), {
        'title': 'Prelude',
        'composer': 'Bach',
        'composed_date': '1722',
        'score_id': 42,
        'tags': ['baroque'],
      });
      // Nothing to send for a piece without them.
      expect(
        const PieceInfo(
          title: 'x',
          composer: '',
          composedDate: '',
        ).toJson().keys,
        ['title', 'composer', 'composed_date'],
      );
    });

    test('phrase reports carry guideline scores and findings', () {
      final report = reportWith([guidelineFinding]);
      expect(report.scores.guidelines, 0);
      expect(report.scores.overall, 88);
      expect(report.guidelinesApplied, ['Baroque: detached touch']);
      expect(report.feedback.single.isGuideline, isTrue);
      expect(report.feedback.single.guidelineTitle, 'Baroque: detached touch');
      expect(PhraseStrip.headline(report), 'Style tip');
    });

    test('score summaries read tags and dates', () {
      final s = ScoreSummary.fromJson({
        'id': 7,
        'title': 'Prelude',
        'composed_date': 'ca. 1720',
        'tags': ['baroque', 'j-s-bach'],
      });
      expect((s.id, s.composedDate), ('7', 'ca. 1720'));
      expect(s.tags, ['baroque', 'j-s-bach']);
    });

    test('the session summary is typed, guidelines included', () {
      final summary = SessionSummary.fromJson(summaryJson);
      expect(summary.summary, 'Pitch accuracy was strong.');
      expect(summary.eraLabel, 'Baroque');
      final rubric = summary.guidelineRubrics.single;
      expect((rubric.phrasesChecked, rubric.phrasesFailed), (3, 2));
      expect(rubric.worstBars, [4, 7]);
      expect(rubric.passRate, closeTo(1 / 3, 1e-9));
      expect(summary.guidelinesMet, ['Steady pulse']);
    });

    test('roles decide who can author', () {
      expect(grace.canAuthorGuidelines, isTrue);
      expect(ada.canAuthorGuidelines, isFalse);
      expect(AuthUser.fromJson(grace.toJson()).roles, ['contributor']);
      expect(diskPages[PageSlot.guides].title, 'Guides');
    });

    test('a parse result fills a rubric, keeping its messages', () {
      const base = Rubric(
        metric: 'sounding_ratio',
        operator: 'lt',
        value: 1,
        unit: 'ratio',
        suggestion: 'Lift.',
      );
      final parsed = const RubricParse(
        rule: {
          'metric': 'note_gap',
          'operator': 'between',
          'value': 0.2,
          'value_max': 0.4,
          'unit': 'sec',
          'applies_to': 'all',
        },
      ).apply(base, 'gap between 0.2 and 0.4 s');
      expect(
        (
          parsed.metric,
          parsed.operator,
          parsed.value,
          parsed.valueMax,
          parsed.unit,
          parsed.suggestion,
          parsed.sourceText,
        ),
        (
          'note_gap',
          'between',
          0.2,
          0.4,
          'sec',
          'Lift.',
          'gap between 0.2 and 0.4 s',
        ),
      );
    });
  });

  group('player side', () {
    testWidgets('the pill marks a guideline finding as a style guideline', (
      tester,
    ) async {
      await pumpPage(
        tester,
        PhraseFeedbackPill(
          report: reportWith([guidelineFinding]),
          onDismiss: () {},
        ),
      );
      expect(find.text('Guideline · Baroque: detached touch'), findsOneWidget);
      expect(find.text('Detach the notes more.'), findsOneWidget);
      expect(find.text('Lift between notes.'), findsOneWidget);
      // The guideline score is not shown as a dimension.
      expect(find.textContaining('Guidelines 0'), findsNothing);
    });

    testWidgets('the how-to-play card reads, expands and closes', (
      tester,
    ) async {
      var dismissed = false;
      const second = Guideline(
        id: 2,
        title: 'Steady pulse',
        body: 'Keep time.',
      );
      await pumpPage(
        tester,
        HowToPlayCard(
          guidelines: const [baroque, second],
          onDismiss: () => dismissed = true,
        ),
      );
      expect(find.text('Baroque: detached touch'), findsOneWidget);
      expect(find.text('Steady pulse'), findsNothing);
      await tester.tap(find.text('Read all (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Steady pulse'), findsOneWidget);
      expect(find.text('Keep time.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close how to play'));
      expect(dismissed, isTrue);
    });

    testWidgets('the session summary panel shows how the guidelines went', (
      tester,
    ) async {
      await pumpPage(
        tester,
        SessionSummaryPanel(
          load: () async => SessionSummary.fromJson(summaryJson),
        ),
      );
      expect(find.text('GUIDELINES · BAROQUE'), findsOneWidget);
      expect(
        find.text(
          'Baroque: detached touch — Gap between notes: met in 1 of 3 phrases',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Mostly bars 4, 7. Lift between notes.'),
        findsOneWidget,
      );
      expect(find.text('Steady pulse: met throughout'), findsOneWidget);
    });

    testWidgets('the panel says so when there is no summary', (tester) async {
      await pumpPage(tester, SessionSummaryPanel(load: () async => null));
      expect(find.textContaining('isn’t available'), findsOneWidget);
    });
  });

  group('Guides tab', () {
    Future<void> pumpShell(
      WidgetTester tester,
      AuthUser user,
      ShellController shell,
    ) async {
      SharedPreferences.setMockInitialValues({OnboardingStore.key: true});
      final auth = await signedIn(user);
      addTearDown(auth.dispose);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: ShellScope(controller: shell, child: child!),
          ),
          home: AppShell(
            auth: auth,
            controller: shell,
            pageBuilder: (slot) => Scaffold(
              body: Center(child: Text('page:${diskPages[slot].title}')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool hasGuidesDisk(WidgetTester tester) => tester
        .widgetList<MiniDisk>(find.byType(MiniDisk))
        .any((d) => d.icon == guidesDiskPage.icon);

    testWidgets('is offered to ada, after Settings', (tester) async {
      final shell = ShellController();
      addTearDown(shell.dispose);
      await pumpShell(tester, ada, shell);
      shell.goTo(PageSlot.settings);
      await tester.pumpAndSettle();
      expect(hasGuidesDisk(tester), isTrue);
      shell.goTo(PageSlot.guides);
      await tester.pumpAndSettle();
      expect(find.text('page:Guides'), findsOneWidget);
    });

    testWidgets('is offered to grace, after Settings', (tester) async {
      final shell = ShellController();
      addTearDown(shell.dispose);
      await pumpShell(tester, grace, shell);
      shell.goTo(PageSlot.settings);
      await tester.pumpAndSettle();
      expect(hasGuidesDisk(tester), isTrue);
      shell.goTo(PageSlot.guides);
      await tester.pumpAndSettle();
      expect(find.text('page:Guides'), findsOneWidget);
    });

    testWidgets('an author lists their own and everyone\'s', (tester) async {
      final repo = FakeGuidelineRepository();
      await pumpPage(
        tester,
        GuidesPage(auth: await signedIn(grace), repository: repo),
      );
      expect(find.text('Baroque: detached touch'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      expect(repo.calls, ['list mine tok']);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'list all tok');
    });

    testWidgets('a player reads published guidelines, without editing', (
      tester,
    ) async {
      final repo = FakeGuidelineRepository();
      await pumpPage(
        tester,
        GuidesPage(auth: await signedIn(ada), repository: repo),
      );
      expect(repo.calls, ['list published']);
      expect(find.text('New guideline'), findsNothing);
      expect(find.text('Mine'), findsNothing);
      await tester.tap(find.text('Baroque: detached touch'));
      await tester.pumpAndSettle();
      expect(
        find.text('Notes should be highly detached in this era.'),
        findsOneWidget,
      );
      expect(find.text('WHAT THE FEEDBACK LISTENS FOR'), findsOneWidget);
      expect(find.text('Edit guideline'), findsNothing);
    });
  });

  group('editor', () {
    Future<FakeGuidelineRepository> pumpEditor(
      WidgetTester tester, {
      Guideline? initial,
    }) async {
      final repo = FakeGuidelineRepository();
      final auth = await signedIn(grace);
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => GuidelineEditorPage(
                      auth: auth,
                      repository: repo,
                      initial: initial,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets(
      'typing a rule fills the structured form, and saving sends it',
      (tester) async {
        final repo = await pumpEditor(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Title'),
          'Baroque: detached touch',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'How to play'),
          'Detach.',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Add a tag'),
          'Baroque',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(InputChip, 'baroque'), findsOneWidget);

        await tester.tap(find.text('Add rubric'));
        await tester.pumpAndSettle();
        const sentence = 'gaps between the notes is more then 0.5 sec';
        await tester.enterText(
          find.widgetWithText(TextField, 'Rule in words'),
          sentence,
        );
        await tester.tap(find.text('Understand'));
        await tester.pumpAndSettle();
        expect(repo.calls, contains('parse $sentence'));
        expect(find.text('metric: gaps'), findsOneWidget);
        expect(find.text('unit: sec'), findsOneWidget);
        expect(
          find.text('Filled in below — check it before saving.'),
          findsOneWidget,
        );
        final value = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Value'),
        );
        expect(value.controller!.text, '0.5');

        await tester.tap(find.text('Published'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(repo.calls.last, 'create tok');
        final saved = repo.saved!;
        expect(
          (saved.title, saved.status),
          ('Baroque: detached touch', 'published'),
        );
        expect(saved.tags, ['baroque']);
        final rubric = saved.rubrics.single;
        expect(
          (
            rubric.metric,
            rubric.operator,
            rubric.value,
            rubric.unit,
            rubric.sourceText,
          ),
          ('note_gap', 'gt', 0.5, 'sec', sentence),
        );
        expect(find.text('open'), findsOneWidget); // popped back
      },
    );

    testWidgets('a refused save is shown, and the editor stays open', (
      tester,
    ) async {
      final repo = await pumpEditor(tester, initial: baroque);
      repo.saveError = const ApiException(
        'You can only change guidelines you wrote.',
        status: 403,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'update 1');
      expect(
        find.text('You can only change guidelines you wrote.'),
        findsOneWidget,
      );
      expect(find.text('Edit guideline'), findsOneWidget);
    });
  });
}

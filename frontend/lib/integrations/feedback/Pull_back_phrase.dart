import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:hu_accomponist/integrations/server/ServerDiscovery.dart';
import 'package:hu_accomponist/integrations/server/server_auth.dart';

/// Models + fetch logic for backend/practice_hub/feedback_generator's two endpoints:
///   - POST /api/feedback/phrase  -> PhraseReport (see Phrase_Send2_Server.dart,
///     which sends the request; this file just owns the response shape)
///   - POST /api/feedback/summary -> the phase-2, whole-session summary
///     (the real "pull back" in this pair, since it's a separate request
///     from sending any individual phrase)

/// The piece currently being practiced.
///
/// [scoreId] (a catalogue score) and [tags] (an exercise has no score row)
/// tell the backend which authored guidelines apply: their rubrics are
/// checked on every phrase alongside the built-in judges.
class PieceInfo {
  final String title;
  final String composer;
  final String composedDate;
  final String? scoreId;
  final List<String> tags;

  const PieceInfo({
    required this.title,
    required this.composer,
    required this.composedDate,
    this.scoreId,
    this.tags = const [],
  });

  factory PieceInfo.fromJson(Map<String, dynamic> json) => PieceInfo(
    title: json['title'] as String? ?? '',
    composer: json['composer'] as String? ?? '',
    composedDate: json['composed_date'] as String? ?? '',
    scoreId: json['score_id']?.toString(),
    tags: [for (final t in json['tags'] as List<dynamic>? ?? const []) '$t'],
  );

  Map<String, dynamic> toJson() {
    final id = int.tryParse(scoreId ?? '');
    return {
      'title': title,
      'composer': composer,
      'composed_date': composedDate,
      // The backend takes an integer id; a non-numeric one is left out.
      'score_id': ?id,
      if (tags.isNotEmpty) 'tags': tags,
    };
  }
}

/// 0-100 category scores for a phrase. Any category can come back null —
/// per the README, a null score means that judge had nothing to measure
/// and it drops out of `overall` rather than counting as zero.
/// `dynamics` and `pedaling` are always null (no loudness/pedal data
/// upstream).
class PhraseScores {
  final int overall;
  final int? pitch;
  final int? rhythm;
  final int? tempo;
  final int? dynamics;
  final int? articulation;
  final int? notes;
  final int? pedaling;

  /// Mean pass rate (0-100) of the authored guideline rubrics checked on
  /// this phrase; null when none applied. Never part of [overall].
  final int? guidelines;

  const PhraseScores({
    required this.overall,
    this.pitch,
    this.rhythm,
    this.tempo,
    this.dynamics,
    this.articulation,
    this.notes,
    this.pedaling,
    this.guidelines,
  });

  factory PhraseScores.fromJson(Map<String, dynamic> json) => PhraseScores(
    overall: json['overall'] as int? ?? 0,
    pitch: json['pitch'] as int?,
    rhythm: json['rhythm'] as int?,
    tempo: json['tempo'] as int?,
    dynamics: json['dynamics'] as int?,
    articulation: json['articulation'] as int?,
    notes: json['notes'] as int?,
    pedaling: json['pedaling'] as int?,
    guidelines: json['guidelines'] as int?,
  );
}

/// Pixel rectangle for one bar on the rendered score page, so the app can
/// mark the spot instead of making the player count bars. Null whenever
/// `bar_boxes` wasn't supplied on the request (see Phrase_Send2_Server.dart).
/// [pageSize] is the [width, height] of the PNG page these pixels were
/// measured on — a client rendering the PDF at another resolution needs
/// to scale by its own width/height against this.
class FeedbackBox {
  final int page;
  final double x;
  final double y;
  final double w;
  final double h;
  final List<int> pageSize;

  const FeedbackBox({
    required this.page,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.pageSize,
  });

  static FeedbackBox? fromJsonNullable(Map<String, dynamic>? json) {
    if (json == null) return null;
    return FeedbackBox(
      page: json['page'] as int? ?? 0,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      w: (json['w'] as num?)?.toDouble() ?? 0,
      h: (json['h'] as num?)?.toDouble() ?? 0,
      pageSize: (json['page_size'] as List<dynamic>? ?? const [])
          .map((e) => e as int)
          .toList(),
    );
  }
}

/// One issue found in the phrase (e.g. a wrong note, a late onset).
///
/// [details] is left as a raw map rather than a strongly-typed class
/// because its shape varies by [category] (pitch feedback carries
/// expected/user Hz and cents, rhythm carries ms offsets, etc.) — read
/// what you need by key rather than assuming a fixed shape. Every finding
/// also carries a `suggestion` inside [details] per the README.
class PhraseFeedbackItem {
  final int bars;
  final FeedbackBox? box;
  final String category;
  final String severity; // "minor" | "major"
  final double confidence; // 0.5 (borderline) .. 1.0 (unmistakable)
  final String message;
  final Map<String, dynamic> details;

  const PhraseFeedbackItem({
    required this.bars,
    required this.box,
    required this.category,
    required this.severity,
    required this.confidence,
    required this.message,
    required this.details,
  });

  factory PhraseFeedbackItem.fromJson(Map<String, dynamic> json) =>
      PhraseFeedbackItem(
        bars: json['bars'] as int? ?? 0,
        box: FeedbackBox.fromJsonNullable(
          json['box'] as Map<String, dynamic>?,
        ),
        category: json['category'] as String? ?? '',
        severity: json['severity'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        message: json['message'] as String? ?? '',
        details: (json['details'] as Map<String, dynamic>?) ?? const {},
      );

  /// A finding from an authored guideline's rubric rather than a built-in
  /// judge.
  bool get isGuideline => category == 'guideline';

  /// For a guideline finding: the guideline it came from.
  String get guidelineTitle => details['guideline_title'] as String? ?? '';
}

/// The full phase-1 report for one phrase, as returned directly by the
/// POST /api/feedback/phrase response.
class PhraseReport {
  final PieceInfo piece;
  final DateTime recordedAt;
  final int phrase;
  final double bpm;
  final String timeSignature;
  final List<int> bars;
  final PhraseScores scores;
  final List<PhraseFeedbackItem> feedback;

  /// Server-assigned session id, formatted "<date>-<piece title>" (e.g.
  /// "2026-09-07-Prelude_in_C") unless an explicit session_id was sent.
  /// Capture this from phrase 1's response and pass it back in on every
  /// later phrase in the same recording (see Phrase_Send2_Server.dart) —
  /// don't invent a client-side session id, the server owns this.
  final String sessionId;
  final String storedAt;

  /// Titles of the authored guidelines checked on this phrase.
  final List<String> guidelinesApplied;

  const PhraseReport({
    required this.piece,
    required this.recordedAt,
    required this.phrase,
    required this.bpm,
    required this.timeSignature,
    required this.bars,
    required this.scores,
    required this.feedback,
    required this.sessionId,
    required this.storedAt,
    this.guidelinesApplied = const [],
  });

  factory PhraseReport.fromJson(Map<String, dynamic> json) {
    final rawRecordedAt = json['recorded_at'] as String?;
    return PhraseReport(
      piece: PieceInfo.fromJson(
        json['piece'] as Map<String, dynamic>? ?? const {},
      ),
      recordedAt: rawRecordedAt != null
          ? (DateTime.tryParse(rawRecordedAt) ?? DateTime.now())
          : DateTime.now(),
      phrase: json['phrase'] as int? ?? 0,
      bpm: (json['bpm'] as num?)?.toDouble() ?? 0,
      timeSignature: json['time_signature'] as String? ?? '',
      bars: (json['bars'] as List<dynamic>? ?? const [])
          .map((e) => e as int)
          .toList(),
      scores: PhraseScores.fromJson(
        json['scores'] as Map<String, dynamic>? ?? const {},
      ),
      feedback: (json['feedback'] as List<dynamic>? ?? const [])
          .map((e) => PhraseFeedbackItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      sessionId: json['session_id'] as String? ?? '',
      storedAt: json['stored_at'] as String? ?? '',
      guidelinesApplied: [
        for (final g in json['guidelines_applied'] as List<dynamic>? ?? const [])
          if (g is Map<String, dynamic>) g['title'] as String? ?? '',
      ],
    );
  }
}

/// One authored rubric's result across a whole session (phase 2's
/// Guidelines.json `rubrics`).
class GuidelineRubricResult {
  final String guidelineTitle;
  final String label;
  final int phrasesChecked;
  final int phrasesFailed;
  final List<int> worstBars;
  final String suggestion;

  const GuidelineRubricResult({
    required this.guidelineTitle,
    required this.label,
    required this.phrasesChecked,
    required this.phrasesFailed,
    this.worstBars = const [],
    this.suggestion = '',
  });

  factory GuidelineRubricResult.fromJson(Map<String, dynamic> json) =>
      GuidelineRubricResult(
        guidelineTitle: json['guideline_title'] as String? ?? '',
        label: json['label'] as String? ?? '',
        phrasesChecked: json['phrases_checked'] as int? ?? 0,
        phrasesFailed: json['phrases_failed'] as int? ?? 0,
        worstBars: [
          for (final b in json['worst_bars'] as List<dynamic>? ?? const [])
            if (b is int) b,
        ],
        suggestion: json['suggestion'] as String? ?? '',
      );

  /// Share of checked phrases this rubric passed, 0..1.
  double get passRate =>
      phrasesChecked == 0 ? 1 : 1 - phrasesFailed / phrasesChecked;
}

/// The phase-2 whole-session summary (POST /api/feedback/summary): the
/// built-in judges' summary plus how the authored guidelines went.
class SessionSummary {
  final String summary;
  final List<String> positives;
  final List<PhraseFeedbackItem> mainFeedback;

  /// Every guideline checked this session: title -> phrases it was checked in.
  final Map<String, int> guidelinesChecked;
  final List<GuidelineRubricResult> guidelineRubrics;
  final String eraLabel;

  const SessionSummary({
    this.summary = '',
    this.positives = const [],
    this.mainFeedback = const [],
    this.guidelinesChecked = const {},
    this.guidelineRubrics = const [],
    this.eraLabel = '',
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    final phase2 = json['phase2'] as Map<String, dynamic>? ?? const {};
    final main = phase2['Summary'] as Map<String, dynamic>? ?? const {};
    final guidelines = phase2['Guidelines'] as Map<String, dynamic>? ?? const {};
    final era = phase2['Era'] as Map<String, dynamic>? ?? const {};
    return SessionSummary(
      summary: main['summary'] as String? ?? '',
      positives: [
        for (final p in main['positive_feedback'] as List<dynamic>? ?? const [])
          '$p',
      ],
      mainFeedback: [
        for (final f in main['feedback'] as List<dynamic>? ?? const [])
          PhraseFeedbackItem.fromJson(f as Map<String, dynamic>),
      ],
      guidelinesChecked: {
        for (final g in guidelines['guidelines'] as List<dynamic>? ?? const [])
          if (g is Map<String, dynamic>)
            g['title'] as String? ?? '': g['phrases_checked'] as int? ?? 0,
      },
      guidelineRubrics: [
        for (final r in guidelines['rubrics'] as List<dynamic>? ?? const [])
          GuidelineRubricResult.fromJson(r as Map<String, dynamic>),
      ],
      eraLabel: era['label'] as String? ?? '',
    );
  }

  /// Guidelines that were checked and never failed.
  List<String> get guidelinesMet {
    final failing = {for (final r in guidelineRubrics) r.guidelineTitle};
    return [
      for (final title in guidelinesChecked.keys)
        if (!failing.contains(title)) title,
    ];
  }
}

/// Fetches the phase-2, whole-session summary once every phrase for a
/// session has been sent.
///
/// [fetch] returns it typed as a [SessionSummary]; [fetchSummary] is the
/// raw decoded JSON.
class SessionSummaryService {
  SessionSummaryService._();

  static const String _summaryPath = '/api/feedback/summary';
  static const Duration _fetchTimeout = Duration(seconds: 30);

  /// [fetchSummary], typed. Null whenever that is.
  static Future<SessionSummary?> fetch(String sessionId) async {
    final raw = await fetchSummary(sessionId);
    if (raw == null) return null;
    try {
      return SessionSummary.fromJson(raw);
    } catch (error) {
      debugPrint('[Diagnostics] summary: unexpected shape — $error');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchSummary(String sessionId) async {
    final baseUrl = await ServerDiscovery.resolveBaseUrl();
    if (baseUrl == null) {
      debugPrint(
        '[Diagnostics] summary FAILED: no backend found on this network. '
        'Will retry discovery on the next request.',
      );
      return null;
    }

    final stopwatch = Stopwatch()..start();
    debugPrint('[Diagnostics] summary -> POST $baseUrl$_summaryPath (session=$sessionId)');

    var response = await _post(baseUrl, sessionId);

    if (response == null) {
      ServerDiscovery.invalidateCache();
      final freshBaseUrl = await ServerDiscovery.resolveBaseUrl(
        forceRefresh: true,
      );
      if (freshBaseUrl == null) {
        debugPrint(
          '[Diagnostics] summary FAILED: backend not found on rediscovery. '
          'Will retry on the next request.',
        );
        return null;
      }
      debugPrint('[Diagnostics] rediscovered backend at $freshBaseUrl — retrying summary once.');
      response = await _post(freshBaseUrl, sessionId);
    }

    if (response == null) {
      debugPrint(
        '[Diagnostics] summary FAILED after ${stopwatch.elapsedMilliseconds}ms '
        '(network error). Will retry on the next request.',
      );
      return null;
    }

    // 404 is not a failure: it means no phase-1 phrase has been stored for
    // this session yet, so there is simply nothing to summarize.
    if (response.statusCode == 404) {
      debugPrint(
        '[Diagnostics] summary: HTTP 404 in ${stopwatch.elapsedMilliseconds}ms '
        '— nothing stored yet for "$sessionId" (not an error).',
      );
      return null;
    }

    if (response.statusCode != 200) {
      debugPrint(
        '[Diagnostics] summary FAILED: HTTP ${response.statusCode} in '
        '${stopwatch.elapsedMilliseconds}ms — ${response.body}',
      );
      return null;
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint(
        '[Diagnostics] summary OK: HTTP 200 in ${stopwatch.elapsedMilliseconds}ms '
        '(${decoded.keys.length} top-level field(s))',
      );
      return decoded;
    } catch (error) {
      debugPrint('[Diagnostics] summary: could not parse response — $error');
      return null;
    }
  }

  static Future<http.Response?> _post(String baseUrl, String sessionId) async {
    final uri = Uri.parse('$baseUrl$_summaryPath');
    try {
      return await http
          .post(
            uri,
            headers: ServerAuth.headers({'Content-Type': 'application/json'}),
            body: jsonEncode({'session_id': sessionId}),
          )
          .timeout(_fetchTimeout);
    } on Exception catch (error) {
      debugPrint('[SessionSummary] Request failed: $error');
      return null;
    }
  }
}
import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';

/// One thing the feedback generator said about a bar, tied to the written
/// note it is about where the report says which note that is.
///
/// Everything here comes from a real [PhraseReport]: the wording is the
/// generator's own, and a notice is anchored to a note only when the finding
/// names one (`details.note_id`). Nothing is guessed about notes the report
/// does not mention.
class PracticeNotice {
  /// Zero-based bar, like [ExpectedNote.bar].
  final int bar;

  /// The written note it is about, or null when it is about the whole bar
  /// (tempo drift, a note played that was not written) or is praise.
  final int? noteId;

  /// pitch, rhythm, articulation, notes, tempo; or `clean` for praise.
  final String category;

  /// "minor" or "major"; praise is "minor".
  final String severity;
  final String message;
  final String? suggestion;
  final bool positive;

  const PracticeNotice({
    required this.bar,
    required this.noteId,
    required this.category,
    required this.severity,
    required this.message,
    this.suggestion,
    this.positive = false,
  });

  bool get isMajor => severity == 'major';

  /// Findings of these categories carry the id of the written note they are
  /// about. Others (tempo) are about the phrase.
  static const _noteCategories = {'pitch', 'rhythm', 'articulation', 'notes'};

  /// The id of the written note [item] is about, if it names one in [written].
  ///
  /// A note that was played but not written (`extra_note`) carries the id of
  /// the *heard* note, which says nothing about the score, so it is not tied
  /// to a written note.
  static int? writtenNoteId(
    PhraseFeedbackItem item,
    List<ExpectedNote> written,
  ) {
    if (!_noteCategories.contains(item.category)) return null;
    if (item.details['issue'] == 'extra_note') return null;
    final id = item.details['note_id'];
    if (id is! num) return null;
    return written.any((n) => n.noteId == id.toInt()) ? id.toInt() : null;
  }

  /// What a judged bar has to say, worst first. An empty list means the
  /// generator had nothing to flag and the bar did not score well enough to
  /// praise either.
  static List<PracticeNotice> fromReport(
    PhraseReport report,
    List<ExpectedNote> written,
  ) {
    final notices = <PracticeNotice>[];
    for (final item in report.feedback) {
      final noteId = writtenNoteId(item, written);
      final note = noteId == null
          ? null
          : written.firstWhere((n) => n.noteId == noteId);
      final suggestion = item.details['suggestion'];
      notices.add(
        PracticeNotice(
          // The finding's own bar is 1-based; a note knows its bar exactly.
          bar: note?.bar ?? (item.bars > 0 ? item.bars - 1 : report.phrase - 1),
          noteId: noteId,
          category: item.category,
          severity: item.severity,
          message: item.message,
          suggestion: suggestion is String && suggestion.isNotEmpty
              ? suggestion
              : null,
        ),
      );
    }
    notices.sort((a, b) {
      final severity = (b.isMajor ? 1 : 0).compareTo(a.isMajor ? 1 : 0);
      return severity != 0 ? severity : a.bar.compareTo(b.bar);
    });

    // Praise only when it is earned: nothing flagged and a high score.
    if (notices.isEmpty && report.scores.overall >= cleanScore) {
      notices.add(
        PracticeNotice(
          bar: report.phrase - 1,
          noteId: null,
          category: 'clean',
          severity: 'minor',
          message: 'Nice, that bar was clean.',
          positive: true,
        ),
      );
    }
    return notices;
  }

  /// The overall score from which a bar with no findings is called clean.
  static const int cleanScore = 90;
}

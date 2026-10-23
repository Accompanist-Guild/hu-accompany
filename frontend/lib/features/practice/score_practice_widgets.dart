import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/practice/live_judge.dart';
import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/features/practice/score_practice_session.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';
import 'package:hu_accomponist/shared/ui/Press_Scale.dart';

/// The backend's verdict on the latest phrase, in one thin line along the
/// top of the score: which bars, the score, and the main thing to work on.
/// The details wait for the summary at the end.
class PhraseStrip extends StatelessWidget {
  final PhraseReport? report;
  const PhraseStrip({super.key, required this.report});

  /// What most of a phrase's findings are about, in a few words.
  static String headline(PhraseReport report) {
    final counts = <String, int>{};
    for (final f in report.feedback) {
      final key = switch (f.category) {
        'notes' => f.details['issue'] == 'extra_note' ? 'extra' : 'missed',
        'tempo' => f.details['direction'] == 'rushing' ? 'rushing' : 'tempo',
        _ => f.category,
      };
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'Clean';
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    final n = top.value;
    String notes(String what) => '$n ${n == 1 ? 'note' : 'notes'} $what';
    return switch (top.key) {
      'pitch' => notes('wrong'),
      'missed' => notes('missed'),
      'extra' => '$n extra ${n == 1 ? 'note' : 'notes'}',
      'rhythm' => notes('off the beat'),
      'rushing' => 'Rushing',
      'tempo' => 'Tempo drifting',
      'articulation' => notes('not as marked'),
      'dynamics' => 'Uneven loudness',
      _ => notes('to check'),
    };
  }

  static Color _tone(int score) => score >= 80
      ? PracticePrefs.instance.colors.perfect
      : score >= 55
      ? PracticePrefs.instance.colors.close
      : PracticePrefs.instance.colors.wrong;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    return AnimatedSwitcher(
      duration: Motion.base,
      child: report == null
          ? const SizedBox(height: 26)
          : Container(
              key: ValueKey(report.phrase),
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              decoration: BoxDecoration(
                color: PracticePalette.paper.withValues(alpha: 0.94),
                borderRadius: Radii.pillRadius,
                border: Border.all(
                  color: PracticePalette.lightGold.withValues(alpha: 0.8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _tone(report.scores.overall),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Text(
                    [
                      if (report.bars.isNotEmpty)
                        report.bars.first == report.bars.last
                            ? 'Bar ${report.bars.first}'
                            : 'Bars ${report.bars.first}–${report.bars.last}',
                      '${report.scores.overall}',
                      headline(report),
                    ].join('  ·  '),
                    style: const TextStyle(
                      color: PracticePalette.brown,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// The count-in, beat by beat, over the score.
class ScoreCountIn extends StatelessWidget {
  final ScorePracticeSession session;
  const ScoreCountIn({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final beat = session.countIn;
        return AnimatedOpacity(
          opacity: beat == null ? 0 : 1,
          duration: Motion.fast,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: Tween(begin: 0.7, end: 1.0).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Container(
                key: ValueKey(beat),
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PracticePalette.paper.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(color: PracticePalette.lightGold),
                  boxShadow: Elevations.overlay(PracticePalette.brown),
                ),
                child: Text(
                  beat == null ? '' : '$beat',
                  style: const TextStyle(
                    color: PracticePalette.gold,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A small pill over the score with an optional ✕ (picking a note to start
/// from, or where the next run starts).
class ScoreBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback? onClose;

  const ScoreBanner({
    super.key,
    required this.text,
    required this.icon,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Space.sm,
        Space.xxs + 2,
        onClose == null ? Space.sm : Space.xxs,
        Space.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: PracticePalette.brown.withValues(alpha: 0.86),
        borderRadius: Radii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: PracticePalette.paper),
          const SizedBox(width: Space.xs),
          Text(
            text,
            style: const TextStyle(
              color: PracticePalette.paper,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: Space.xs),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: PracticePalette.paper,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// + and − for the score's size.
class ZoomButtons extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final Axis direction;

  const ZoomButtons({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    this.direction = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback onTap) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: PracticePalette.paper.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            border: Border.all(color: PracticePalette.lightGold),
          ),
          child: Icon(icon, size: 20, color: PracticePalette.gold),
        ),
      ),
    );
    final gap = direction == Axis.vertical
        ? const SizedBox(height: Space.xs)
        : const SizedBox(width: Space.xs);
    return Flex(
      direction: direction,
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.add_rounded, 'Zoom in', onZoomIn),
        gap,
        button(Icons.remove_rounded, 'Zoom out', onZoomOut),
      ],
    );
  }
}

/// What the player chose in the summary.
class SummaryChoice {
  /// A mistake to look at on the score, by note id; null to look over the
  /// whole run there.
  final int? note;
  const SummaryChoice.note(int this.note);
  const SummaryChoice.review() : note = null;
}

/// After a run: the score, how the notes went, and every mistake, by section
/// of the piece. A section a repeat plays twice folds open to show each time
/// through. Tapping a mistake, or "See it on the score", closes the sheet.
class ScoreSummarySheet extends StatelessWidget {
  final ScorePracticeSession session;
  const ScoreSummarySheet({super.key, required this.session});

  static Future<SummaryChoice?> show(
    BuildContext context,
    ScorePracticeSession session,
  ) {
    return showModalBottomSheet<SummaryChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PracticePalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.modal)),
      ),
      builder: (_) => ScoreSummarySheet(session: session),
    );
  }

  /// 0-100 for what was played: perfect notes count fully, a little off
  /// three quarters, mistakes nothing. Notes not reached don't count.
  static int score(ScorePracticeSession session) {
    final c = session.judge.counts;
    final total = c.values.fold(0, (a, b) => a + b);
    if (total == 0) return 0;
    return ((c[NoteResult.perfect]! + 0.75 * c[NoteResult.close]!) /
            total *
            100)
        .round();
  }

  /// The backend's suggestion for a note, if it made one.
  static String? tipFor(ScorePracticeSession session, int id) {
    for (final f
        in session.judge.findings[id] ?? const <PhraseFeedbackItem>[]) {
      final suggestion = f.details['suggestion'];
      if (suggestion is String && suggestion.isNotEmpty) return suggestion;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // The server's verdicts keep arriving after the run ends.
    listenable: session,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final judge = session.judge;
    final counts = judge.counts;
    bool isMistake(int id) => judge.marks[id]?.result.isMistake ?? false;
    bool reached(List<int> ids) => ids.any(judge.marks.containsKey);
    final sections = [
      for (final s in judge.sections)
        if (s.times.any(reached)) s,
    ];
    final colors = PracticePrefs.instance.colors;
    final mistakeCount = judge.marks.values
        .where((v) => v.result.isMistake)
        .length;
    final total = counts.values.fold(0, (a, b) => a + b);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.xl,
        ),
        children: [
          const Text(
            'YOUR RUN',
            style: TextStyle(
              color: PracticePalette.gold,
              fontSize: 11,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${score(session)}',
                style: const TextStyle(
                  color: PracticePalette.brown,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: Space.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  total == 0
                      ? 'nothing heard'
                      : '${counts[NoteResult.perfect]! + counts[NoteResult.close]!} of $total notes right',
                  style: const TextStyle(
                    color: PracticePalette.mutedBrown,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.md,
            runSpacing: Space.xs,
            children: [
              _count(colors.perfect, 'Perfect', counts[NoteResult.perfect]!),
              _count(colors.close, 'A little off', counts[NoteResult.close]!),
              _count(colors.wrong, 'Mistakes', mistakeCount),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: Space.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(context, const SummaryChoice.review()),
                icon: const Icon(Icons.library_music_outlined, size: 18),
                label: const Text('See it on the score'),
                style: FilledButton.styleFrom(
                  backgroundColor: PracticePalette.brown,
                  foregroundColor: PracticePalette.paper,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.lg),
          if (mistakeCount == 0)
            Text(
              total == 0
                  ? 'Play along with the score and your run shows up here.'
                  : 'No mistakes. Try it a little faster next time.',
              style: const TextStyle(
                color: PracticePalette.brown,
                fontSize: 14,
              ),
            )
          else ...[
            const Text(
              'Tap a mistake to see it on the score',
              style: TextStyle(color: PracticePalette.mutedBrown, fontSize: 12),
            ),
            const SizedBox(height: Space.xs),
            for (final section in sections)
              if (section.repeated)
                _repeatedSection(context, section, isMistake, reached, colors)
              else if (section.times.first.any(isMistake)) ...[
                if (sections.length > 1) _sectionHeading(section.bars),
                for (final id in section.times.first)
                  if (isMistake(id)) _mistakeRow(context, id, colors),
              ],
          ],
        ],
      ),
    );
  }

  Widget _sectionHeading(String text) => Padding(
    padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxs),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: PracticePalette.gold,
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  /// A section played more than once: folded, with how each time went;
  /// open, each time's mistakes.
  Widget _repeatedSection(
    BuildContext context,
    ScoreSection section,
    bool Function(int id) isMistake,
    bool Function(List<int> ids) reached,
    NoteColors colors,
  ) {
    final times = [
      for (var i = 0; i < section.times.length; i++)
        if (reached(section.times[i])) i,
    ];
    String howMany(int i) {
      final n = section.times[i].where(isMistake).length;
      return n == 0 ? 'clean' : '$n ${n == 1 ? 'mistake' : 'mistakes'}';
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('section-${section.firstBar}'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: Space.sm),
        iconColor: PracticePalette.gold,
        collapsedIconColor: PracticePalette.gold,
        title: Text(
          '${section.bars} · played ${section.times.length} times',
          style: const TextStyle(
            color: PracticePalette.brown,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          [
            for (final i in times) '${ScoreSection.timeName(i)}: ${howMany(i)}',
          ].join(' · '),
          style: const TextStyle(
            color: PracticePalette.mutedBrown,
            fontSize: 12,
          ),
        ),
        children: [
          for (final i in times) ...[
            _sectionHeading(ScoreSection.timeName(i)),
            if (!section.times[i].any(isMistake))
              const Padding(
                padding: EdgeInsets.only(bottom: Space.xs),
                child: Text(
                  'No mistakes',
                  style: TextStyle(color: PracticePalette.brown, fontSize: 13),
                ),
              )
            else
              for (final id in section.times[i])
                if (isMistake(id)) _mistakeRow(context, id, colors),
          ],
        ],
      ),
    );
  }

  Widget _count(Color color, String label, int n) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: Space.xxs + 2),
      Text(
        '$n $label',
        style: const TextStyle(
          color: PracticePalette.brown,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _mistakeRow(BuildContext context, int id, NoteColors colors) {
    final note = session.judge.note(id)!;
    final verdict = session.judge.marks[id]!;
    final tip = tipFor(session, id);
    return InkWell(
      onTap: () => Navigator.pop(context, SummaryChoice.note(id)),
      borderRadius: Radii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                'Bar ${LiveJudge.bar(note)}',
                style: const TextStyle(
                  color: PracticePalette.mutedBrown,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    verdict.describe(note),
                    style: const TextStyle(
                      color: PracticePalette.brown,
                      fontSize: 14,
                    ),
                  ),
                  if (tip != null)
                    Text(
                      tip,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PracticePalette.mutedBrown,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: PracticePalette.lightGold,
            ),
          ],
        ),
      ),
    );
  }
}

/// A pill with a few text actions, over the score (a paused run, a run
/// being looked over).
class ScoreActionBar extends StatelessWidget {
  final IconData icon;
  final String text;
  final List<(String, VoidCallback)> actions;

  const ScoreActionBar({
    super.key,
    required this.icon,
    required this.text,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.sm, 2, 2, 2),
      decoration: BoxDecoration(
        color: PracticePalette.brown.withValues(alpha: 0.9),
        borderRadius: Radii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: PracticePalette.paper),
          const SizedBox(width: Space.xs),
          Text(
            text,
            style: const TextStyle(
              color: PracticePalette.paper,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Space.xxs),
          for (final (label, onTap) in actions)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: PracticePalette.lightGold,
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(label),
            ),
        ],
      ),
    );
  }
}

/// Looking back over a finished run on the score. For each section a repeat
/// plays more than once, which time through is showing; folded away until
/// asked for.
class RunReviewPanel extends StatefulWidget {
  final ScorePracticeSession session;

  /// Section (index into [LiveJudge.sections]) -> the time through showing.
  final Map<int, int> shown;
  final void Function(int section, int time) onShow;
  final VoidCallback onSummary;
  final VoidCallback onClose;

  const RunReviewPanel({
    super.key,
    required this.session,
    required this.shown,
    required this.onShow,
    required this.onSummary,
    required this.onClose,
  });

  /// The sections played more than once this run, by index, with the times
  /// through that were reached.
  static Map<int, List<int>> repeats(ScorePracticeSession session) {
    final judge = session.judge;
    final out = <int, List<int>>{};
    for (var s = 0; s < judge.sections.length; s++) {
      final section = judge.sections[s];
      final reached = [
        for (var t = 0; t < section.times.length; t++)
          if (section.times[t].any(judge.marks.containsKey)) t,
      ];
      if (reached.length > 1) out[s] = reached;
    }
    return out;
  }

  @override
  State<RunReviewPanel> createState() => _RunReviewPanelState();
}

class _RunReviewPanelState extends State<RunReviewPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final repeats = RunReviewPanel.repeats(widget.session);
    final sections = widget.session.judge.sections;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScoreActionBar(
          icon: Icons.library_music_outlined,
          text: 'Your run',
          actions: [
            if (repeats.isNotEmpty)
              (
                _open ? 'Hide repeats' : 'Repeats',
                () => setState(() => _open = !_open),
              ),
            ('Summary', widget.onSummary),
            ('Done', widget.onClose),
          ],
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.standard,
          alignment: Alignment.topCenter,
          child: !_open || repeats.isEmpty
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(top: Space.xs),
                  padding: const EdgeInsets.all(Space.sm),
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: PracticePalette.paper.withValues(alpha: 0.97),
                    borderRadius: Radii.cardRadius,
                    border: Border.all(color: PracticePalette.lightGold),
                    boxShadow: Elevations.overlay(PracticePalette.brown),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final MapEntry(key: s, value: times)
                          in repeats.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sections[s].bars,
                                  style: const TextStyle(
                                    color: PracticePalette.brown,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              for (final t in times)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: Space.xxs,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(ScoreSection.timeName(t)),
                                    selected:
                                        (widget.shown[s] ?? times.last) == t,
                                    onSelected: (_) => widget.onShow(s, t),
                                    showCheckmark: false,
                                    visualDensity: VisualDensity.compact,
                                    labelStyle: const TextStyle(fontSize: 12),
                                    selectedColor: PracticePalette.lightGold,
                                    side: const BorderSide(
                                      color: PracticePalette.lightGold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

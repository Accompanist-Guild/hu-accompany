import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/practice/score_practice_session.dart';
import 'package:hu_accomponist/features/practice/score_timeline.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';
import 'package:hu_accomponist/shared/ui/Press_Scale.dart';

/// Bottom sheet for how to practise a score: the tempo (from the written
/// one) and, on a keyboard score, which hands.
class ScorePracticeSheet extends StatefulWidget {
  final String title;
  final ScoreTimeline timeline;
  final ScorePracticeSettings current;
  final String action;

  const ScorePracticeSheet({
    super.key,
    required this.title,
    required this.timeline,
    required this.current,
    required this.action,
  });

  /// [action] labels the confirm button ("Start" before a recording).
  static Future<ScorePracticeSettings?> show(
    BuildContext context, {
    required String title,
    required ScoreTimeline timeline,
    required ScorePracticeSettings current,
    String action = 'Done',
  }) {
    return showModalBottomSheet<ScorePracticeSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PracticePalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.modal)),
      ),
      builder: (_) => ScorePracticeSheet(
        title: title,
        timeline: timeline,
        current: current,
        action: action,
      ),
    );
  }

  /// Shares of the written tempo offered as quick picks.
  static const List<(String, double)> presets = [
    ('Slow', 0.6),
    ('Steady', 0.8),
    ('As written', 1.0),
  ];

  static const double minShare = 0.3, maxShare = 1.2;

  @override
  State<ScorePracticeSheet> createState() => _ScorePracticeSheetState();
}

class _ScorePracticeSheetState extends State<ScorePracticeSheet> {
  late double _bpm = widget.current.bpm;
  late Hands _hands = widget.current.hands;

  double get _written => widget.timeline.bpm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'PLAY ALONG',
              style: TextStyle(
                color: PracticePalette.gold,
                fontSize: 11,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              widget.title.isEmpty ? 'This score' : widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PracticePalette.brown,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.md),
            _label('Tempo'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${_bpm.round()}',
                  style: const TextStyle(
                    color: PracticePalette.brown,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: Space.xxs),
                const Text(
                  'bpm',
                  style: TextStyle(
                    color: PracticePalette.mutedBrown,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  'written ${_written.round()}',
                  style: TextStyle(
                    color: PracticePalette.mutedBrown.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: PracticePalette.gold,
                inactiveTrackColor: PracticePalette.lightGold.withValues(
                  alpha: 0.5,
                ),
                thumbColor: PracticePalette.gold,
                overlayColor: PracticePalette.gold.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: _bpm.clamp(
                  _written * ScorePracticeSheet.minShare,
                  _written * ScorePracticeSheet.maxShare,
                ),
                min: (_written * ScorePracticeSheet.minShare).roundToDouble(),
                max: (_written * ScorePracticeSheet.maxShare).roundToDouble(),
                onChanged: (v) => setState(() => _bpm = v.roundToDouble()),
              ),
            ),
            Wrap(
              spacing: Space.xs,
              children: [
                for (final (label, share) in ScorePracticeSheet.presets)
                  _chip(
                    label,
                    (_bpm - (_written * share).roundToDouble()).abs() < 0.5,
                    () => setState(
                      () => _bpm = (_written * share).roundToDouble(),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              'The score follows you if you speed up or slow down.',
              style: TextStyle(
                color: PracticePalette.mutedBrown.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
            if (widget.timeline.hasHands) ...[
              const SizedBox(height: Space.md),
              _label('Hands'),
              Wrap(
                spacing: Space.xs,
                children: [
                  for (final h in Hands.values)
                    _chip(
                      h.label,
                      h == _hands,
                      () => setState(() => _hands = h),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.lg),
            PressScale(
              onTap: () => Navigator.pop(
                context,
                ScorePracticeSettings(bpm: _bpm, hands: _hands),
              ),
              borderRadius: Radii.pillRadius,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PracticePalette.gold,
                  borderRadius: Radii.pillRadius,
                ),
                child: Text(
                  widget.action,
                  style: const TextStyle(
                    color: PracticePalette.paper,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: Space.xs),
    child: Text(
      text,
      style: const TextStyle(
        color: PracticePalette.brown,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    selectedColor: PracticePalette.gold.withValues(alpha: 0.18),
    backgroundColor: PracticePalette.ivory,
    side: BorderSide(
      color: selected ? PracticePalette.gold : PracticePalette.lightGold,
    ),
    labelStyle: TextStyle(
      color: selected ? PracticePalette.brown : PracticePalette.mutedBrown,
      fontWeight: FontWeight.w600,
    ),
    showCheckmark: false,
  );
}

import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Bottom sheet for how notes are judged and shown: how strict timing is,
/// and the colour of a perfect, a close and a wrong note. Changes apply at
/// once and are kept ([PracticePrefs]).
class PracticePrefsSheet extends StatelessWidget {
  final PracticePrefs prefs;

  const PracticePrefsSheet({super.key, required this.prefs});

  static Future<void> show(BuildContext context, {PracticePrefs? prefs}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PracticePalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.modal)),
      ),
      builder: (_) =>
          PracticePrefsSheet(prefs: prefs ?? PracticePrefs.instance),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.lg,
            Space.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NOTES',
                style: TextStyle(
                  color: PracticePalette.gold,
                  fontSize: 11,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.xs),
              const Text(
                'How notes are judged',
                style: TextStyle(
                  color: PracticePalette.brown,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.md),
              _label('Timing'),
              for (final s in Strictness.values) _strictnessRow(s),
              const SizedBox(height: Space.md),
              _label('Colours'),
              _colorRow(
                'Perfect',
                prefs.colors.perfect,
                NoteColors.perfectChoices,
                (c) => prefs.setColors(prefs.colors.copyWith(perfect: c)),
              ),
              _colorRow(
                'A little off',
                prefs.colors.close,
                NoteColors.closeChoices,
                (c) => prefs.setColors(prefs.colors.copyWith(close: c)),
              ),
              _colorRow(
                'Wrong',
                prefs.colors.wrong,
                NoteColors.wrongChoices,
                (c) => prefs.setColors(prefs.colors.copyWith(wrong: c)),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Changes show from your next run.',
                style: TextStyle(
                  color: PracticePalette.mutedBrown.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
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

  Widget _strictnessRow(Strictness s) {
    final selected = prefs.strictness == s;
    return InkWell(
      onTap: () => prefs.setStrictness(s),
      borderRadius: Radii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected
                  ? PracticePalette.gold
                  : PracticePalette.lightGold,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    style: const TextStyle(
                      color: PracticePalette.brown,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    s.description,
                    style: const TextStyle(
                      color: PracticePalette.mutedBrown,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorRow(
    String label,
    Color current,
    List<Color> choices,
    ValueChanged<Color> onPick,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: PracticePalette.brown,
                fontSize: 14,
              ),
            ),
          ),
          for (final c in choices)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Semantics(
                button: true,
                selected: c.toARGB32() == current.toARGB32(),
                label: '$label colour',
                child: GestureDetector(
                  onTap: () => onPick(c),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c.toARGB32() == current.toARGB32()
                            ? PracticePalette.brown
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

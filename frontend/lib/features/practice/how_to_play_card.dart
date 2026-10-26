import 'package:flutter/material.dart';

import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// "How to play this piece": the authored guidelines whose tags match the
/// loaded score, shown before the first run. The body is plain text, line
/// breaks kept. Their rubrics are what the phrase feedback checks.
class HowToPlayCard extends StatefulWidget {
  final List<Guideline> guidelines;
  final VoidCallback onDismiss;

  const HowToPlayCard({
    super.key,
    required this.guidelines,
    required this.onDismiss,
  });

  @override
  State<HowToPlayCard> createState() => _HowToPlayCardState();
}

class _HowToPlayCardState extends State<HowToPlayCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final first = widget.guidelines.first;
    final more = widget.guidelines.length - 1;
    return Semantics(
      container: true,
      label: 'How to play this piece',
      child: Material(
        color: PracticePalette.paper,
        elevation: 0,
        borderRadius: Radii.lgRadius,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          padding: const EdgeInsets.all(Space.sm),
          decoration: BoxDecoration(
            borderRadius: Radii.lgRadius,
            border: Border.all(
              color: PracticePalette.lightGold.withValues(alpha: 0.8),
            ),
            boxShadow: Elevations.overlay(PracticePalette.brown),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.menu_book_rounded,
                    size: 18,
                    color: PracticePalette.gold,
                  ),
                  const SizedBox(width: Space.xs),
                  const Expanded(
                    child: Text(
                      'HOW TO PLAY',
                      style: TextStyle(
                        color: PracticePalette.gold,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close how to play',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: PracticePalette.mutedBrown,
                    ),
                    onPressed: widget.onDismiss,
                  ),
                ],
              ),
              if (!_open) ...[
                Text(
                  first.title,
                  style: const TextStyle(
                    color: PracticePalette.brown,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (first.body.isNotEmpty) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    first.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: _bodyStyle,
                  ),
                ],
                TextButton(
                  onPressed: () => setState(() => _open = true),
                  child: Text(
                    more > 0 ? 'Read all (${more + 1})' : 'Read more',
                  ),
                ),
              ] else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final g in widget.guidelines) ...[
                        Text(
                          g.title,
                          style: const TextStyle(
                            color: PracticePalette.brown,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: Space.xxs),
                        if (g.body.isNotEmpty) Text(g.body, style: _bodyStyle),
                        const SizedBox(height: Space.sm),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const _bodyStyle = TextStyle(
    color: PracticePalette.mutedBrown,
    fontSize: 13,
    height: 1.4,
  );
}

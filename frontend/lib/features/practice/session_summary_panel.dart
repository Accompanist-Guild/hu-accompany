import 'package:flutter/material.dart';

import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// The server's take on the whole run, at the end of the run summary: its
/// one-line summary, what went well, the top things to work on, and how the
/// piece's authored guidelines ("Baroque: detached touch") went.
///
/// Loads once, when first shown; says so quietly when there is nothing.
class SessionSummaryPanel extends StatefulWidget {
  final Future<SessionSummary?> Function() load;

  const SessionSummaryPanel({super.key, required this.load});

  @override
  State<SessionSummaryPanel> createState() => _SessionSummaryPanelState();
}

class _SessionSummaryPanelState extends State<SessionSummaryPanel> {
  late final Future<SessionSummary?> _summary = widget.load().catchError(
    (Object _) => null,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionSummary?>(
      future: _summary,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: Space.xs),
                Text(
                  'Getting the full summary…',
                  style: TextStyle(
                    color: PracticePalette.mutedBrown,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }
        final summary = snapshot.data;
        if (summary == null) {
          return const Text(
            'The full summary isn’t available right now.',
            style: TextStyle(color: PracticePalette.mutedBrown, fontSize: 12),
          );
        }
        return _content(summary);
      },
    );
  }

  Widget _content(SessionSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('THE WHOLE RUN'),
        if (summary.summary.isNotEmpty)
          Text(
            summary.summary,
            style: const TextStyle(color: PracticePalette.brown, fontSize: 14),
          ),
        for (final p in summary.positives)
          _line(Icons.thumb_up_alt_outlined, p),
        for (final f in summary.mainFeedback)
          _line(
            Icons.flag_outlined,
            f.message,
            detail: f.details['suggestion'] as String?,
          ),
        if (summary.guidelinesChecked.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          _heading(
            summary.eraLabel.isEmpty
                ? 'GUIDELINES'
                : 'GUIDELINES · ${summary.eraLabel.toUpperCase()}',
          ),
          for (final r in summary.guidelineRubrics)
            _line(
              Icons.menu_book_rounded,
              '${r.guidelineTitle}${r.label.isEmpty ? '' : ' — ${r.label}'}: '
              'met in ${r.phrasesChecked - r.phrasesFailed} of '
              '${r.phrasesChecked} phrases',
              detail: [
                if (r.worstBars.isNotEmpty)
                  'Mostly bars ${r.worstBars.join(', ')}.',
                if (r.suggestion.isNotEmpty) r.suggestion,
              ].join(' '),
              color: PracticePalette.caution,
            ),
          for (final title in summary.guidelinesMet)
            _line(Icons.check_circle_outline_rounded, '$title: met throughout'),
        ],
      ],
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: Space.xxs),
    child: Text(
      text,
      style: const TextStyle(
        color: PracticePalette.gold,
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _line(
    IconData icon,
    String text, {
    String? detail,
    Color color = PracticePalette.mutedBrown,
  }) => Padding(
    padding: const EdgeInsets.only(top: Space.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  color: PracticePalette.brown,
                  fontSize: 13,
                ),
              ),
              if (detail != null && detail.isNotEmpty)
                Text(
                  detail,
                  style: const TextStyle(
                    color: PracticePalette.mutedBrown,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

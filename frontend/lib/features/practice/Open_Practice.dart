import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/shelf/Shelf_Manager.dart';
import 'package:hu_accomponist/integrations/scores/score_models.dart';
import 'package:hu_accomponist/integrations/scores/score_repository.dart';
import 'package:hu_accomponist/main.dart' show ScoreViewerPage;
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';

/// Opening a score for practice, from wherever it was chosen.
///
/// Both the library and the shelf need to land the user on the score, and
/// previously neither did: the library popped a [LoadedScore] that only
/// the practice screen knew how to consume, so choosing a sheet from the
/// turntable dropped the user back at home, and the shelf only showed a
/// snackbar. Keeping the transition in one place means a new entry point
/// gets the same behaviour for free.
abstract final class OpenPractice {
  /// Opens [selected] in Practice.
  ///
  /// Inside the app shell that means closing whatever was pushed over it and
  /// showing the Practice tab with the score. Without a shell (a page under
  /// test) it replaces the current route with the score viewer, so Back
  /// returns to where the picker was opened from rather than to the picker.
  static Future<void> withScore(
    BuildContext context,
    LoadedScore selected,
  ) async {
    final shell = ShellScope.maybeOf(context);
    if (shell != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      shell.openScore(selected);
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ScoreViewerPage(selected: selected)),
    );
  }

  /// Opens a score the user previously played, from the shelf.
  ///
  /// The shelf stores only id/title/composer, so the MusicXML has to be fetched
  /// before the viewer can show anything. That is a network round trip, so
  /// the caller gets a blocking progress dialog rather than an unexplained
  /// pause on a tapped tile.
  static Future<void> withShelfEntry(
    BuildContext context,
    ShelfEntry entry,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final shell = ShellScope.maybeOf(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );

    try {
      final loaded = await const ScoreRepository().load(
        ScoreSummary(
          id: entry.id,
          title: entry.title,
          composer: entry.composer,
        ),
      );
      // Dismiss the progress dialog before routing onward.
      navigator.pop();
      if (shell != null) {
        navigator.popUntil((route) => route.isFirst);
        shell.openScore(loaded);
        return;
      }
      await navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => ScoreViewerPage(selected: loaded)),
      );
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_friendly(e)),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(Space.md),
        ),
      );
    }
  }

  /// Strips Dart's "Exception: " prefix so a backend reason reads naturally.
  static String _friendly(Object e) {
    final message = e.toString();
    return message.startsWith('Exception: ') ? message.substring(11) : message;
  }
}

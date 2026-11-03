import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

import 'package:hu_accomponist/features/practice/live_judge.dart';
import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/features/practice/score_timeline.dart';

/// Points at one specific note inside the score — zero-based measure,
/// voice-entry, and note-within-that-voice-entry index, in the same order
/// the notes appear in the source MusicXML. This is how "this note was
/// played wrong" gets mapped onto the rendered engraving.
class NoteRef {
  final int measure;
  final int voiceEntry;
  final int noteIndex;
  const NoteRef({
    required this.measure,
    required this.voiceEntry,
    required this.noteIndex,
  });

  Map<String, int> toJson() => {
    'measure': measure,
    'voiceEntry': voiceEntry,
    'noteIndex': noteIndex,
  };
}

/// What a touch on the score does. With [InkMode.pen] or [InkMode.eraser],
/// one finger draws or erases and two fingers scroll and zoom; with
/// [InkMode.off], one finger scrolls. Pinching zooms in every mode.
enum InkMode { off, pen, eraser }

/// Drives the OSMD WebView: loads MusicXML, colors or resets individual
/// notes, and holds the pen ink drawn on the score (inside the page, so it
/// scrolls and zooms with the music), without re-fetching or re-navigating
/// anything. Calls made before
/// the page's JS bridge (`window.OSMDBridge`) has announced itself ready
/// are queued and flushed once the 'bridgeReady' message arrives — NOT
/// just once WebView's onPageFinished fires, since the OSMD script may
/// still be executing at that point.
class ScoreOsmdController {
  /// Runs a script in the page, whichever web view shows it.
  Future<void> Function(String js)? _web;
  bool _bridgeReady = false;
  final List<String> _pendingCalls = [];

  /// Whether there's ink to undo on the score.
  final ValueNotifier<bool> canUndoInk = ValueNotifier(false);

  /// Called with the score's strokes (JSON) whenever the ink changes, so
  /// they can be kept for next time.
  void Function(String strokesJson)? onInkChanged;

  /// Called once a loaded score's notes have been read off it (see
  /// `assets/osmd/score_timeline.js`): what there is to play, and when. An
  /// empty timeline means the score has no notes this app can follow.
  void Function(ScoreTimeline timeline)? onTimeline;

  /// A note was tapped: the timeline ids drawn there, nearest first (a
  /// repeat draws several ids on one note).
  void Function(List<int> ids)? onNoteTap;

  /// A note was tapped while picking a place to start ([setPicking]).
  void Function(List<int> ids)? onNotePick;

  /// While [setImmersive] is on: a click or tap on the page ([count] 1) or a
  /// double one (2).
  void Function(int count)? onScreenTap;

  /// The ink the next loaded score starts with (see [setInk]).
  String _inkJson = '[]';

  /// A freshly attached WebView has not loaded the bridge yet, so calls
  /// queue until its own 'bridgeReady' arrives.
  void attach(Future<void> Function(String js) runJavaScript) {
    _web = runJavaScript;
    _bridgeReady = false;
  }

  void onBridgeReady() {
    _bridgeReady = true;
    for (final call in _pendingCalls) {
      _web?.call(call);
    }
    _pendingCalls.clear();
  }

  /// Call this if the page navigates again (e.g. a hot restart of the
  /// WebView) so pending calls queue up again instead of firing into a
  /// bridge that no longer exists.
  void reset() {
    _bridgeReady = false;
  }

  void _call(String js) {
    if (_bridgeReady && _web != null) {
      _web!(js);
    } else {
      _pendingCalls.add(js);
    }
  }

  Future<void> loadScore(String musicXml) async {
    final encoded = jsonEncode(musicXml);
    canUndoInk.value = false;
    _call('OSMDBridge.loadScore($encoded); OSMDBridge.setInk($_inkJson);');
  }

  /// The strokes to show on the score (JSON, as [onInkChanged] gave them).
  /// Set it before or after the score loads; a new score should start with
  /// '[]' until its own ink is known.
  void setInk(String strokesJson) {
    _inkJson = strokesJson;
    canUndoInk.value = false;
    _call('OSMDBridge.setInk($strokesJson);');
  }

  void setInkMode(InkMode mode, {Color? color, double? width}) {
    final hex = color == null ? 'null' : '"${_hex(color)}"';
    _call('OSMDBridge.setInkMode("${mode.name}", $hex, ${width ?? 'null'});');
  }

  void undoInk() => _call('OSMDBridge.undoInk();');

  void clearInk() => _call('OSMDBridge.clearInk();');

  void _inkMessage(Map<String, dynamic>? payload) {
    if (payload == null) return;
    canUndoInk.value = payload['canUndo'] == true;
    _inkJson = jsonEncode(payload['strokes'] ?? const []);
    onInkChanged?.call(_inkJson);
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  /// Colors the given notes (e.g. ones flagged as wrong by your audio
  /// analysis) — defaults to red. Call [resetColors] to clear all of them.
  Future<void> colorNotes(
    List<NoteRef> notes, {
    Color color = const Color(0xFFE53935),
  }) async {
    if (notes.isEmpty) return;
    final hex = _hex(color);
    final refsJson = jsonEncode(notes.map((n) => n.toJson()).toList());
    _call('OSMDBridge.colorNotes($refsJson, "$hex");');
  }

  Future<void> resetColors() async {
    _call('OSMDBridge.resetColors();');
  }

  /// Shows what is happening as the score is played: how each note went
  /// (see `OSMDBridge.live` in osmd_viewer.html for how each verdict is
  /// drawn), the notes due now (they sway) and the notes just played (they
  /// hop), and the start of a repeat. Notes are timeline ids. [follow] keeps
  /// the next note in view while a recording runs.
  void live(LiveUpdate update, {bool? follow}) {
    final payload = jsonEncode({
      if (update.marks.isNotEmpty)
        'marks': [
          for (final e in update.marks.entries)
            {
              'id': e.key,
              'r': e.value.result.name,
              'played': ?e.value.playedMidi,
            },
        ],
      if (update.cleared.isNotEmpty) 'cleared': update.cleared,
      'due': ?update.due,
      if (update.played.isNotEmpty) 'played': update.played,
      'repeat': ?update.repeat,
      'showPass': ?update.showPass,
      'follow': ?follow,
    });
    _call('OSMDBridge.live($payload);');
  }

  /// Scrolls the score by [dy] logical pixels (a drag on a layer above it).
  /// While on, clicks on the page are reported through [onScreenTap]
  /// instead of as note taps (playing along: one pauses, two finish).
  void setImmersive(bool on) => _call('OSMDBridge.setImmersive($on);');

  void scrollBy(double dy) =>
      _call('OSMDBridge.scrollBy(${dy.toStringAsFixed(1)});');

  /// Every note back as written, for a new run.
  void resetLive() => _call('OSMDBridge.resetLive();');

  /// The colours notes turn (see [PracticePrefs]).
  void setColors(NoteColors colors) => _call(
    'OSMDBridge.setColors(${jsonEncode({'perfect': _hex(colors.perfect), 'close': _hex(colors.close), 'wrong': _hex(colors.wrong)})});',
  );

  /// A small note beside note [id]: [lines] first in bold, the rest smaller.
  /// Hidden by the next tap or scroll, or [hideTip].
  void showTip(int id, List<String> lines) =>
      _call('OSMDBridge.showTip($id, ${jsonEncode(lines)});');

  void hideTip() => _call('OSMDBridge.hideTip();');

  /// Scrolls to note [id] and darkens and blurs everything else, until the
  /// next tap or scroll.
  void spotlight(int id) => _call('OSMDBridge.spotlight($id);');

  /// While on, a tapped note goes to [onNotePick] instead of [onNoteTap].
  void setPicking(bool on) => _call('OSMDBridge.setPicking($on);');

  /// Zooms in (factor > 1) or out, keeping the middle of the screen in place.
  void zoomBy(double factor) => _call('OSMDBridge.zoomBy($factor);');
}

/// Renders MusicXML with OpenSheetMusicDisplay inside a WebView. OSMD owns
/// its own layout and scrolling, so this is one continuous view rather than
/// discrete pages. OSMD is bundled under assets/osmd/, so it works offline.
///
/// webview_flutter has no Windows version, so there the page runs in
/// Microsoft's WebView2 (webview_windows) instead, with the same bridge.
class ScoreOsmdView extends StatefulWidget {
  final String musicXml;
  final ScoreOsmdController controller;

  const ScoreOsmdView({
    super.key,
    required this.musicXml,
    required this.controller,
  });

  @override
  State<ScoreOsmdView> createState() => _ScoreOsmdViewState();
}

class _ScoreOsmdViewState extends State<ScoreOsmdView> {
  WebViewController? _web;
  WebviewController? _windowsWeb;
  StreamSubscription<dynamic>? _windowsMessages;
  bool _loading = true;
  String? _error;

  /// Where WebView2 serves the app's assets/osmd folder from (see
  /// [_startWindowsWebView]). Made up, and never looked up on the network.
  static const String _windowsHost = 'score.accompanist.invalid';

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      final web = _windowsWeb = WebviewController();
      widget.controller.attach(web.executeScript);
      _startWindowsWebView(web);
    } else {
      widget.controller.attach(_buildWebViewController().runJavaScript);
    }
  }

  @override
  void dispose() {
    _windowsMessages?.cancel();
    _windowsWeb?.dispose();
    super.dispose();
  }

  Future<void> _run(String js) =>
      widget.controller._web?.call(js) ?? Future.value();

  Future<void> _startWindowsWebView(WebviewController web) async {
    try {
      await web.initialize();
      // The page posts every message to window.FlutterBridge, which
      // webview_flutter provides elsewhere; here it is WebView2's channel.
      await web.addScriptToExecuteOnDocumentCreated(
        'window.FlutterBridge = { postMessage: function (m) { window.chrome.webview.postMessage(m); } };',
      );
      _windowsMessages = web.webMessage.listen(
        (message) => _onPageMessage(message as String),
      );
      // Flutter's assets are plain files beside the app on Windows.
      final assets = [
        File(Platform.resolvedExecutable).parent.path,
        'data',
        'flutter_assets',
        'assets',
        'osmd',
      ].join(r'\');
      await web.addVirtualHostNameMapping(
        _windowsHost,
        assets,
        WebviewHostResourceAccessKind.allow,
      );
      await web.loadUrl('https://$_windowsHost/osmd_viewer.html');
    } on PlatformException catch (e) {
      // No WebView2 runtime: Windows 11 has it, Windows 10 gets it with Edge.
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Scores need Microsoft Edge WebView2, which this computer '
              'does not have (${e.message}). Install it from Microsoft and '
              'open Accompanist again.';
        });
      }
    }
  }

  WebViewController _buildWebViewController() {
    final web = _web = WebViewController();
    // macOS web views can't be made transparent: the call throws, and the
    // page would never load. The page paints its own paper there.
    if (!Platform.isMacOS) web.setBackgroundColor(const Color(0x00000000));
    web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _onBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          // NOTE: we deliberately do NOT call loadScore() here. This only
          // tells us the HTML document finished parsing — the OSMD script
          // (and window.OSMDBridge) may still be executing. The
          // actual "safe to call JS" signal is the 'bridgeReady' message
          // posted from the page itself once OSMDBridge exists.
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Failed to load score viewer: ${error.description}';
              });
            }
          },
        ),
      )
      // Case-sensitive on iOS. The page loads opensheetmusicdisplay.min.js
      // from the same asset folder.
      ..loadFlutterAsset('assets/osmd/osmd_viewer.html');
    return web;
  }

  @override
  void didUpdateWidget(covariant ScoreOsmdView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new sheet was selected — reload it into the same WebView instead
    // of tearing down and recreating the page.
    if (widget.musicXml != oldWidget.musicXml) {
      setState(() {
        _loading = true;
        _error = null;
      });
      widget.controller.loadScore(widget.musicXml);
    }
  }

  void _onBridgeMessage(JavaScriptMessage message) =>
      _onPageMessage(message.message);

  void _onPageMessage(String message) {
    final data = jsonDecode(message) as Map<String, dynamic>;
    switch (data['type']) {
      case 'bridgeReady':
        // window.OSMDBridge now exists — safe to flush queued calls and
        // kick off the very first loadScore.
        if (Platform.isMacOS || Platform.isWindows) {
          // Not transparent there (see above; WebView2 is left opaque too):
          // white would show around the music, so it gets the card's paper.
          _run("document.documentElement.style.background = '#FFFCF4';");
        }
        widget.controller.onBridgeReady();
        widget.controller.loadScore(widget.musicXml);
        break;
      case 'loaded':
        if (mounted) setState(() => _loading = false);
        break;
      case 'timeline':
        final payload = data['payload'] as Map<String, dynamic>? ?? const {};
        if (payload['error'] != null) {
          debugPrint(
            '[Diagnostics] score: could not read its notes — ${payload['error']}',
          );
        }
        final timeline = ScoreTimeline.fromJson(payload);
        debugPrint(
          '[Diagnostics] score: ${timeline.notes.length} notes to follow, '
          '${timeline.bpm} bpm, ${timeline.timeSignature}',
        );
        widget.controller.onTimeline?.call(timeline);
        break;
      case 'screenTap':
        final count = (data['payload']?['count'] as num?)?.toInt() ?? 1;
        widget.controller.onScreenTap?.call(count);
        break;
      case 'noteTap':
      case 'notePick':
        final ids = [
          for (final id in (data['payload']?['ids'] as List? ?? const []))
            (id as num).toInt(),
        ];
        if (ids.isEmpty) break;
        if (data['type'] == 'notePick') {
          widget.controller.onNotePick?.call(ids);
        } else {
          widget.controller.onNoteTap?.call(ids);
        }
        break;
      case 'ink':
        widget.controller._inkMessage(data['payload'] as Map<String, dynamic>?);
        break;
      case 'error':
        if (mounted) {
          setState(() {
            _loading = false;
            _error = data['payload']?['message']?.toString();
          });
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_windowsWeb case final web?)
          ValueListenableBuilder<WebviewValue>(
            valueListenable: web,
            builder: (context, value, _) =>
                value.isInitialized ? Webview(web) : const SizedBox.expand(),
          )
        else
          WebViewWidget(controller: _web!),
        if (_loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Couldn't render score: $_error",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
              ),
            ),
          ),
      ],
    );
  }
}

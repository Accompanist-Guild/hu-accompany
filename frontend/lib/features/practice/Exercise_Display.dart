import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/features/practice/Exercise_Session.dart';
import 'package:hu_accomponist/features/practice/practice_feedback.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Shows an exercise in place of the PDF score: its notes by bar, the ones
/// to play now in red, a pulse on every beat, and the count-in.
///
/// Once a bar has been judged, what the feedback generator said about it
/// appears on the notes it is about: a small badge on the note, and one chat
/// bubble at a time that pops up beside it and dismisses itself. Earlier
/// feedback stays in the history (the speech-bubble button).
///
/// The pulse is visual only. An audible click would be picked up by the
/// microphone and could be taken for a played note.
class ExerciseDisplay extends StatefulWidget {
  final ExerciseSession session;

  /// How long a bubble stays before it dismisses itself.
  final Duration bubbleLinger;

  const ExerciseDisplay({
    super.key,
    required this.session,
    this.bubbleLinger = const Duration(seconds: 6),
  });

  @override
  State<ExerciseDisplay> createState() => _ExerciseDisplayState();
}

class _ExerciseDisplayState extends State<ExerciseDisplay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// Beat since the downbeat (0 = first note), and the notes being played
  /// (more than one when written notes overlap, as in a chord). Only changes
  /// to these trigger a rebuild, not every frame.
  int _beat = -1;
  Set<int> _active = const {};

  /// Where each note and each bar's label are on screen, so a bubble can
  /// follow the thing it is about.
  final Map<int, LayerLink> _noteLinks = {};
  final Map<int, LayerLink> _barLinks = {};

  PracticeNotice? _bubble;
  Timer? _bubbleTimer;
  List<PracticeNotice>? _announced;

  ExerciseSession get _session => widget.session;

  LayerLink _noteLink(int noteId) =>
      _noteLinks.putIfAbsent(noteId, LayerLink.new);
  LayerLink _barLink(int bar) => _barLinks.putIfAbsent(bar, LayerLink.new);

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(ExerciseDisplay old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSessionChanged);
      widget.session.addListener(_onSessionChanged);
      _hideBubble();
    }
  }

  void _onSessionChanged() {
    final running = _session.downbeat != null;
    if (running && !_ticker.isActive) _ticker.start();
    if (!running && _ticker.isActive) {
      _ticker.stop();
      _beat = -1;
      _active = const {};
    }
    // A new bar was judged: announce its most important notice.
    if (!identical(_announced, _session.latest)) {
      _announced = _session.latest;
      _announce(_session.latest);
    }
    setState(() {});
  }

  /// One bubble at a time: the worst thing said about the bar just judged
  /// (or its praise). The rest are on the notes as badges and in the
  /// history, so a bar with five findings still shows one bubble.
  void _announce(List<PracticeNotice> notices) {
    _bubbleTimer?.cancel();
    if (notices.isEmpty) {
      _bubble = null;
      return;
    }
    _bubble = notices.first;
    _bubbleTimer = Timer(widget.bubbleLinger, _hideBubble);
  }

  void _hideBubble() {
    _bubbleTimer?.cancel();
    if (mounted && _bubble != null) setState(() => _bubble = null);
  }

  void _onTick(Duration _) {
    final downbeat = _session.downbeat;
    if (downbeat == null) return;
    final elapsed = DateTime.now().difference(downbeat).inMicroseconds / 1000.0;
    final beat = elapsed < 0 ? -1 : (elapsed / _session.beatMs).floor();
    final active = elapsed < 0
        ? const <int>{}
        : {
            for (var i = 0; i < _session.notes.length; i++)
              if (elapsed >= _session.notes[i].startMs &&
                  elapsed < _session.notes[i].endMs)
                i,
          };
    if (beat != _beat || !_sameSet(active, _active)) {
      setState(() {
        _beat = beat;
        _active = active;
      });
    }
  }

  static bool _sameSet(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _bubbleTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  /// The worst notice for each written note, for its badge.
  Map<int, PracticeNotice> get _badges {
    final badges = <int, PracticeNotice>{};
    for (final notice in _session.notices) {
      final id = notice.noteId;
      if (id == null) continue;
      final current = badges[id];
      if (current == null || (notice.isMajor && !current.isMajor)) {
        badges[id] = notice;
      }
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final notes = _session.notes;
    final bars = <List<int>>[];
    for (var i = 0; i < notes.length; i++) {
      if (bars.length <= notes[i].bar) bars.add([]);
      bars[notes[i].bar].add(i);
    }
    final badges = _badges;
    final cleanBars = {
      for (final n in _session.notices)
        if (n.positive) n.bar,
    };

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.xxxl,
            Space.lg,
            Space.xl,
          ),
          children: [
            Text(
              _session.exercise.title,
              style: const TextStyle(
                color: PracticePalette.brown,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xxs),
            Text(
              '${_session.bpm} bpm · starting on '
              '${Exercise.noteName(notes.first.midi)}',
              style: const TextStyle(
                color: PracticePalette.mutedBrown,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: Space.lg),
            for (var b = 0; b < bars.length; b++)
              _bar(b, bars[b], notes, badges, clean: cleanBars.contains(b)),
            const SizedBox(height: Space.md),
            _hint(),
          ],
        ),
        Positioned(top: Space.md, right: Space.md, child: _pulse()),
        if (_session.notices.isNotEmpty)
          Positioned(top: Space.sm, right: Space.xxxl, child: _historyButton()),
        if (_bubble != null) _bubbleFor(_bubble!, bars),
        if (_session.countIn != null) _countIn(_session.countIn!),
      ],
    );
  }

  Widget _bar(
    int bar,
    List<int> indexes,
    List<ExpectedNote> notes,
    Map<int, PracticeNotice> badges, {
    required bool clean,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          CompositedTransformTarget(
            link: _barLink(bar),
            child: SizedBox(
              width: 28,
              child: clean
                  ? const _Pop(
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: PracticePalette.gold,
                      ),
                    )
                  : Text(
                      '${bar + 1}',
                      style: TextStyle(
                        color: PracticePalette.mutedBrown.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
          for (final i in indexes)
            Expanded(
              flex: notes[i].durationMs.round(),
              child: CompositedTransformTarget(
                link: _noteLink(notes[i].noteId),
                child: _chip(
                  notes[i],
                  current: _active.contains(i),
                  badge: badges[notes[i].noteId],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A written note. Red while it is the one to play: bold enough to follow
  /// at a glance, yet the note name stays readable on it. Afterwards it
  /// returns to its resting look, with a badge if the generator flagged it.
  Widget _chip(
    ExpectedNote note, {
    required bool current,
    PracticeNotice? badge,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          margin: const EdgeInsets.symmetric(horizontal: Space.xxs / 2),
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: current ? PracticePalette.alert : PracticePalette.ivory,
            borderRadius: Radii.cardRadius,
            border: Border.all(
              color: current
                  ? PracticePalette.alert
                  : PracticePalette.lightGold,
            ),
            boxShadow: current
                ? [
                    BoxShadow(
                      color: PracticePalette.alert.withValues(alpha: 0.28),
                      blurRadius: 10,
                    ),
                  ]
                : const [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: TextStyle(
              color: current ? PracticePalette.paper : PracticePalette.brown,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            child: Text(note.name),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -4,
            right: 0,
            // Pops in when the verdict arrives.
            child: _Pop(
              key: ValueKey('badge-${note.noteId}-${badge.category}'),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badge.isMajor
                      ? PracticePalette.alert
                      : PracticePalette.caution,
                  border: Border.all(color: PracticePalette.paper, width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The bubble for [notice], hung off the note it is about (or the bar's
  /// number for a bar-wide notice) and angled so it stays inside the page:
  /// notes on the left half of a bar open it to the right, and vice versa.
  /// It sits above its target, over bars already played rather than the ones
  /// still to come.
  Widget _bubbleFor(PracticeNotice notice, List<List<int>> bars) {
    final link = notice.noteId != null
        ? _noteLink(notice.noteId!)
        : _barLink(notice.bar);

    var side = _BubbleSide.start;
    if (notice.noteId != null && notice.bar < bars.length) {
      final indexes = bars[notice.bar];
      final position = indexes.indexWhere(
        (i) => _session.notes[i].noteId == notice.noteId,
      );
      final fraction = indexes.length <= 1
          ? 0.5
          : position / (indexes.length - 1);
      side = fraction < 0.34
          ? _BubbleSide.start
          : fraction > 0.66
          ? _BubbleSide.end
          : _BubbleSide.middle;
    }

    final (target, follower) = switch (side) {
      _BubbleSide.start => (Alignment.topLeft, Alignment.bottomLeft),
      _BubbleSide.middle => (Alignment.topCenter, Alignment.bottomCenter),
      _BubbleSide.end => (Alignment.topRight, Alignment.bottomRight),
    };

    // Positioned, so the bubble is only as big as it needs to be; the
    // follower then lines its corner up with the note's.
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        targetAnchor: target,
        followerAnchor: follower,
        offset: const Offset(0, -Space.xs),
        child: _FeedbackBubble(
          key: ValueKey(notice),
          notice: notice,
          side: side,
          onDismiss: _hideBubble,
        ),
      ),
    );
  }

  Widget _historyButton() {
    return Badge(
      label: Text('${_session.notices.where((n) => !n.positive).length}'),
      isLabelVisible: _session.notices.any((n) => !n.positive),
      backgroundColor: PracticePalette.alert,
      child: IconButton(
        tooltip: 'Feedback so far',
        visualDensity: VisualDensity.compact,
        icon: const Icon(
          Icons.chat_bubble_outline_rounded,
          size: 20,
          color: PracticePalette.mutedBrown,
        ),
        onPressed: _showHistory,
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PracticePalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.modal)),
      ),
      builder: (context) => _History(notices: _session.notices),
    );
  }

  /// A dot that pops on every beat once playing has started.
  Widget _pulse() {
    final active = _beat >= 0;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_beat),
      tween: Tween(begin: active ? 1.6 : 1.0, end: 1.0),
      duration: Motion.base,
      curve: Motion.enter,
      builder: (context, scale, _) => Transform.scale(
        scale: scale,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? (_beat % Exercise.beatsPerBar == 0
                      ? PracticePalette.gold
                      : PracticePalette.lightGold)
                : PracticePalette.lightGold.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  Widget _hint() {
    return Text(
      'Tap the mic to start. You get a ${ExerciseSession.countInBeats}-beat '
      'count-in; play the first note on the beat after the last count.',
      style: TextStyle(
        color: PracticePalette.mutedBrown.withValues(alpha: 0.8),
        fontSize: 12,
        height: 1.4,
      ),
    );
  }

  Widget _countIn(int beat) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: PracticePalette.paper.withValues(alpha: 0.85),
          alignment: Alignment.center,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(beat),
            tween: Tween(begin: 1.3, end: 1.0),
            duration: Motion.base,
            curve: Motion.enter,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Text(
              '$beat',
              style: const TextStyle(
                color: PracticePalette.gold,
                fontSize: 72,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _BubbleSide { start, middle, end }

/// Pops its child in with a little bounce, once, when it first appears.
class _Pop extends StatelessWidget {
  final Widget child;
  const _Pop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

/// A small chat bubble with a tail pointing down at the note it is about.
/// It fades and grows in from the tail, and fades out when dismissed.
class _FeedbackBubble extends StatelessWidget {
  final PracticeNotice notice;
  final _BubbleSide side;
  final VoidCallback onDismiss;

  const _FeedbackBubble({
    super.key,
    required this.notice,
    required this.side,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final accent = notice.positive
        ? PracticePalette.gold
        : notice.isMajor
        ? PracticePalette.alert
        : PracticePalette.caution;
    final tailAlignment = switch (side) {
      _BubbleSide.start => Alignment.bottomLeft,
      _BubbleSide.middle => Alignment.bottomCenter,
      _BubbleSide.end => Alignment.bottomRight,
    };

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.slow,
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.85 + 0.15 * t,
          alignment: tailAlignment,
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: onDismiss,
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: switch (side) {
              _BubbleSide.start => CrossAxisAlignment.start,
              _BubbleSide.middle => CrossAxisAlignment.center,
              _BubbleSide.end => CrossAxisAlignment.end,
            },
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 230),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: PracticePalette.paper,
                  borderRadius: Radii.lgRadius,
                  border: Border.all(color: accent.withValues(alpha: 0.55)),
                  boxShadow: Elevations.overlay(PracticePalette.brown),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PracticePalette.brown,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    if (notice.suggestion != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        notice.suggestion!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PracticePalette.mutedBrown,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                child: CustomPaint(
                  size: const Size(12, 7),
                  painter: _TailPainter(
                    fill: PracticePalette.paper,
                    edge: accent.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  final Color fill;
  final Color edge;
  const _TailPainter({required this.fill, required this.edge});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.fill != fill || old.edge != edge;
}

/// Everything said so far this run, oldest first, for looking back at.
class _History extends StatelessWidget {
  final List<PracticeNotice> notices;
  const _History({required this.notices});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const Text(
              'FEEDBACK SO FAR',
              style: TextStyle(
                color: PracticePalette.gold,
                fontSize: 11,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.sm),
            if (notices.isEmpty)
              const Text(
                'Feedback appears here as you play.',
                style: TextStyle(color: PracticePalette.mutedBrown),
              ),
            for (final n in notices)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5, right: Space.sm),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: n.positive
                            ? PracticePalette.gold
                            : n.isMajor
                            ? PracticePalette.alert
                            : PracticePalette.caution,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Bar ${n.bar + 1} · ',
                              style: const TextStyle(
                                color: PracticePalette.brown,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: n.message,
                              style: const TextStyle(
                                color: PracticePalette.brown,
                              ),
                            ),
                            if (n.suggestion != null)
                              TextSpan(
                                text: '  ${n.suggestion}',
                                style: const TextStyle(
                                  color: PracticePalette.mutedBrown,
                                ),
                              ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.35),
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
}

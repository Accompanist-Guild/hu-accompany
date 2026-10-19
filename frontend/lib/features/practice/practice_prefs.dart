import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How exactly on time a note must be to count as perfect.
enum Strictness {
  strict('Strict', 'Perfect only right on the beat'),
  normal('Normal', 'Perfect within a tenth of a beat'),
  relaxed('Relaxed', 'Perfect within a fifth of a beat'),
  anyTime('Right key is enough', 'Timing is not judged at all');

  const Strictness(this.label, this.description);
  final String label;
  final String description;

  /// The share of a beat a note may be off and still be perfect.
  double get perfectShare => switch (this) {
    Strictness.strict => 0.05,
    Strictness.normal => 0.10,
    Strictness.relaxed => 0.20,
    Strictness.anyTime => double.infinity,
  };

  /// How much more (or less) room than normal a note has before it is
  /// early or late rather than just a little off.
  double get closeScale => switch (this) {
    Strictness.strict => 0.6,
    Strictness.normal => 1.0,
    Strictness.relaxed => 1.6,
    Strictness.anyTime => double.infinity,
  };
}

/// The colours notes turn on the score.
class NoteColors {
  final Color perfect;
  final Color close;
  final Color wrong;

  const NoteColors({
    required this.perfect,
    required this.close,
    required this.wrong,
  });

  static const NoteColors standard = NoteColors(
    perfect: Color(0xFF6DBE8C),
    close: Color(0xFFE0B43A),
    wrong: Color(0xFFD9534F),
  );

  /// Offered for each role in the settings, the standard one first.
  static const List<Color> perfectChoices = [
    Color(0xFF6DBE8C),
    Color(0xFF3FA36B),
    Color(0xFF5AA9E6),
    Color(0xFF8E7CC3),
  ];
  static const List<Color> closeChoices = [
    Color(0xFFE0B43A),
    Color(0xFFF0A04B),
    Color(0xFFB9C94A),
    Color(0xFF9DB0BF),
  ];
  static const List<Color> wrongChoices = [
    Color(0xFFD9534F),
    Color(0xFFE0457B),
    Color(0xFFB23A3A),
    Color(0xFF9C4FD6),
  ];

  NoteColors copyWith({Color? perfect, Color? close, Color? wrong}) =>
      NoteColors(
        perfect: perfect ?? this.perfect,
        close: close ?? this.close,
        wrong: wrong ?? this.wrong,
      );
}

/// The player's practice settings: how strict timing is and which colours
/// notes turn. Kept on the device; listeners hear every change.
class PracticePrefs extends ChangeNotifier {
  PracticePrefs._();

  static final PracticePrefs instance = PracticePrefs._();

  static const _strictnessKey = 'practice.strictness';
  static const _perfectKey = 'practice.color.perfect';
  static const _closeKey = 'practice.color.close';
  static const _wrongKey = 'practice.color.wrong';

  Strictness _strictness = Strictness.normal;
  NoteColors _colors = NoteColors.standard;
  bool _loaded = false;

  Strictness get strictness => _strictness;
  NoteColors get colors => _colors;

  /// Reads the saved settings (once; later calls return at once).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_strictnessKey);
      _strictness = Strictness.values.firstWhere(
        (s) => s.name == name,
        orElse: () => Strictness.normal,
      );
      Color? read(String key) {
        final value = prefs.getInt(key);
        return value == null ? null : Color(value);
      }

      _colors = NoteColors.standard.copyWith(
        perfect: read(_perfectKey),
        close: read(_closeKey),
        wrong: read(_wrongKey),
      );
      notifyListeners();
    } catch (_) {
      // No storage (tests): the defaults stand.
    }
  }

  Future<void> setStrictness(Strictness value) async {
    _strictness = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_strictnessKey, value.name);
    } catch (_) {}
  }

  Future<void> setColors(NoteColors value) async {
    _colors = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_perfectKey, value.perfect.toARGB32());
      await prefs.setInt(_closeKey, value.close.toARGB32());
      await prefs.setInt(_wrongKey, value.wrong.toARGB32());
    } catch (_) {}
  }

  /// Back to the defaults (tests).
  @visibleForTesting
  void reset() {
    _strictness = Strictness.normal;
    _colors = NoteColors.standard;
    _loaded = false;
  }
}

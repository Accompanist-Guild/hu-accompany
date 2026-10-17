import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The macOS app runs inside Apple's sandbox. In the sandbox the microphone is off unless the app both asks for it
/// (an entitlement) and says why (a usage string); without either, recording silently gets nothing, or the app is
/// killed. Hum mode and practice both record, so these two entries are what make the downloaded app usable.
void main() {
  final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();

  for (final name in ['Release', 'DebugProfile']) {
    test('$name entitlements let the sandboxed app use the microphone', () {
      final entitlements = File('macos/Runner/$name.entitlements').readAsStringSync();
      expect(
        entitlements,
        matches(RegExp(r'<key>com\.apple\.security\.device\.audio-input</key>\s*<true/>')),
      );
    });
  }

  test('Info.plist explains why the microphone is used', () {
    final usage = RegExp(r'<key>NSMicrophoneUsageDescription</key>\s*<string>([^<]+)</string>').firstMatch(infoPlist);
    expect(usage, isNotNull, reason: 'macOS refuses microphone access without a usage description');
    expect(usage!.group(1)!.trim(), isNotEmpty);
  });
}

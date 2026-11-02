import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hu_accomponist/integrations/audio/Rust_Bridge.dart';
import 'package:hu_accomponist/main.dart';
import 'package:integration_test/integration_test.dart';

/// Where to also write what each check found (--dart-define=TEST_REPORT=path).
/// On Windows the test runner passes back only pass or fail, not the reason,
/// so the release workflow prints this file instead.
const String _reportPath = String.fromEnvironment('TEST_REPORT');

void _report(String line) {
  // ignore: avoid_print
  print('[startup test] $line');
  if (_reportPath.isEmpty) return;
  try {
    File(_reportPath).writeAsStringSync('$line\n', mode: FileMode.append);
  } on FileSystemException catch (e) {
    // A sandboxed app (macOS) may not write there; the report is only a help.
    // ignore: avoid_print
    print('[startup test] could not write the report: $e');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Same loader as main(): on iOS/macOS the Rust code is linked statically,
  // so the generated default (dlopen of native_ffi.framework) can't find it.
  setUpAll(() async => await RustBridge.ensureInitialized());

  testWidgets('the Rust engine loads', (WidgetTester tester) async {
    _report(
      RustBridge.isAvailable
          ? 'rust engine: loaded'
          : 'rust engine: NOT loaded: ${RustBridge.error}',
    );
    expect(RustBridge.isAvailable, isTrue, reason: RustBridge.error);
  });

  testWidgets('the app starts without errors', (WidgetTester tester) async {
    // Smoke test only: the app's widget tree builds cleanly end to end
    // (Vinyl_Loading_Screen -> the auth gate). There's no Rust API surface to
    // exercise yet, so this doesn't call into the generated bindings.
    await tester.pumpWidget(const HuAccumponistApp());
    await tester.pump(
      const Duration(milliseconds: 950),
    ); // past the loading screen's minDuration
    final error = tester.takeException();
    _report(
      error == null
          ? 'app start: no errors'
          : 'app start: ERROR ${error.runtimeType}: $error',
    );
    expect(error, isNull);
  });
}

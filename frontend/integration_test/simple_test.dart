import 'package:flutter_test/flutter_test.dart';
import 'package:hu_accomponist/integrations/audio/Rust_Bridge.dart';
import 'package:hu_accomponist/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Same loader as main(): on iOS/macOS the Rust code is linked statically,
  // so the generated default (dlopen of native_ffi.framework) can't find it.
  setUpAll(() async => await RustBridge.ensureInitialized());

  testWidgets('App boots with RustLib initialized', (WidgetTester tester) async {
    expect(RustBridge.isAvailable, isTrue);
    // Smoke test only: confirms the Rust bridge comes up and the app's
    // widget tree builds cleanly end to end (Vinyl_Loading_Screen ->
    // Record_Navigator_Page). There's no Rust API surface to exercise yet
    // (the old greet() demo fn was removed and nothing has replaced it),
    // so this intentionally doesn't assert on any generated-binding output —
    // add that back here once native_ffi exposes real functions to call.
    await tester.pumpWidget(const HuAccumponistApp());
    await tester.pump(const Duration(milliseconds: 950)); // past the loading screen's minDuration
    expect(tester.takeException(), isNull);
  });
}
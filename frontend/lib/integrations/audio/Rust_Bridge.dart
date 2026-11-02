import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import 'package:hu_accomponist/src/rust/frb_generated.dart';

/// Single place that brings up the flutter_rust_bridge runtime.
///
/// Exists because how the Rust library is loaded differs by platform, and
/// two call sites need to agree about it.
///
/// On iOS the Rust code is linked **statically** into the Runner executable
/// (`ios/libnative_ffi_sim.a`, via the Frameworks build phase), so its
/// symbols are already in the running process. The generated default loader
/// instead tries to `dlopen` a dynamic `native_ffi.framework`, which does
/// not exist in that build and fails with "Failed to load dynamic library".
/// `ExternalLibrary.process()` looks the symbols up in the current process,
/// which is the correct strategy for static linking.
///
/// macOS does the same, but gets the library differently: the `rust_builder`
/// plugin (cargokit) compiles `native_ffi` during the Xcode build and links it
/// into the app, so there is no prebuilt file to commit.
///
/// Windows keeps the generated default, which opens `native_ffi.dll`: cargokit
/// builds it during `flutter build windows` and puts it beside the app.
///
/// Other platforms keep the generated default too, but those builds don't have
/// the library, so initialization is expected to fail there and anything
/// Rust-backed is unavailable.
abstract final class RustBridge {
  static bool _initialized = false;
  static bool _available = false;

  /// True once initialization has succeeded. False means the Rust side is
  /// not reachable in this build, and callers should degrade rather than
  /// assume a stream will ever produce anything.
  static bool get isAvailable => _available;

  /// Why initialization failed, when it did.
  static String? get error => _error;
  static String? _error;

  /// Safe to call repeatedly; the work happens once.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Platform.isIOS || Platform.isMacOS) {
        await RustLib.init(
          externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
        );
      } else {
        await RustLib.init();
      }
      _available = true;
      debugPrint('[Diagnostics] rust: bridge initialized.');
    } catch (e) {
      _available = false;
      _error = '$e';
      debugPrint('[Diagnostics] rust: bridge unavailable — $e');
    }
  }
}

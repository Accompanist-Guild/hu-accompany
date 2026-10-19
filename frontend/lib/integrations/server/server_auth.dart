import 'package:flutter/foundation.dart';

import 'package:hu_accomponist/config/app_constants.dart';

/// The header that proves a request comes from the app. The deployed server answers 401 to anything without it
/// (see `AppKeyMiddleware` in the backend), so every request the app makes to the server goes through [headers].
///
/// Only requests to the app's own server may use this: the key must never go to another address.
abstract final class ServerAuth {
  static const String _header = 'X-App-Key';

  static String _key = AppConstants.appKey;

  /// Replaces the key, for tests. An empty string means "send none".
  @visibleForTesting
  static void useKey(String key) => _key = key;

  /// [extra] plus the app key, as a new map. With no key configured (a local server that has none set), [extra]
  /// is returned unchanged. Whatever the caller put under `X-App-Key`, in any letter case, is dropped, so the
  /// configured key is the only one that is sent.
  static Map<String, String> headers([Map<String, String>? extra]) {
    final result = <String, String>{
      for (final entry in (extra ?? const <String, String>{}).entries)
        if (entry.key.toLowerCase() != _header.toLowerCase())
          entry.key: entry.value,
    };
    if (_key.isNotEmpty) result[_header] = _key;
    return result;
  }
}

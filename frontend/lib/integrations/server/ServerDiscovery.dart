import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart';

import 'package:hu_accomponist/config/app_constants.dart';

class ServerDiscovery {
  static const String _serviceType = '_huaccompany._tcp';

  static const Duration _discoveryTimeout = Duration(seconds: 5);

  static String? _cachedBaseUrl;

  /// The address this build was given (SERVER_URL), already checked, or null to search the network instead.
  static String? _configuredBaseUrl = configuredBaseUrl(AppConstants.serverUrl);

  /// True when this build was given a usable server address and so never searches the network.
  static bool get isConfigured => _configuredBaseUrl != null;

  /// Replaces the configured address, for tests. An empty string means "none".
  @visibleForTesting
  static void useConfiguredUrl(String raw) =>
      _configuredBaseUrl = configuredBaseUrl(raw);

  /// Checks a build-time server address and tidies it, or returns null if it should not be used.
  ///
  /// The app key travels with every request to this address, and a key sent in the clear can be read by anyone
  /// on the path, so only `https` is accepted, plus plain `http` to this machine or the local network (to try a
  /// build against a server on your laptop). A refused address is logged and ignored, which makes the app fall
  /// back to searching the network; a loud log is better than a build that quietly leaks its key.
  static String? configuredBaseUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }

    final uri = Uri.tryParse(text);
    final usable = uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' ||
            (uri.scheme == 'http' && _isLocalHost(uri.host)));
    if (!usable) {
      debugPrint(
        '[Diagnostics] discovery: ignoring SERVER_URL "$raw" — it must be '
        'https (or http to a local machine). Searching the network instead.',
      );
      return null;
    }
    return text;
  }

  /// This machine, or one on the same network: loopback, a private IPv4 range, or a `.local` name.
  static bool _isLocalHost(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name == '::1' || name.endsWith('.local')) {
      return true;
    }
    final parts = name.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return false;
    final a = octets[0]!, b = octets[1]!;
    return a == 127 ||
        a == 10 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  /// Skips discovery and uses [baseUrl], for tests that talk to a server they started.
  @visibleForTesting
  static void useBaseUrl(String baseUrl) => _cachedBaseUrl = baseUrl;

  /// Cleans up the hostname mDNS hands back before it is used in a URL.
  ///
  /// Two things need fixing. A Bonjour hostname is fully qualified and ends
  /// in a trailing dot ("host.local."), which some HTTP clients will not
  /// resolve. And the backend advertises a doubled suffix — mdns.py builds
  /// its `server` field as `socket.gethostname() + ".local."`, but on macOS
  /// gethostname() already returns `<name>.local`, so the record says
  /// `<name>.local.local.` — a name that resolves nowhere. Collapsing
  /// the repeat here fixes discovery from the app side without touching the
  /// backend.
  static String normalizeHost(String host) {
    var cleaned = host;
    while (cleaned.endsWith('.')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    while (cleaned.toLowerCase().endsWith('.local.local')) {
      cleaned = cleaned.substring(0, cleaned.length - '.local'.length);
    }
    return cleaned;
  }

  /// Finds the backend server using mDNS/Bonjour.
  ///
  /// If a server was already found, the cached address is returned immediately.
  static Future<String?> resolveBaseUrl({bool forceRefresh = false}) async {
    // A build given a server address uses it and never searches: the network search only finds a server on the
    // same Wi-Fi, which is no use to someone downloading the app. Nothing to refresh either: the address is fixed.
    final configured = _configuredBaseUrl;
    if (configured != null) return configured;

    // Use the previously discovered server when possible.
    if (!forceRefresh && _cachedBaseUrl != null) {
      debugPrint('[Diagnostics] discovery: using cached backend $_cachedBaseUrl');
      return _cachedBaseUrl;
    }

    debugPrint(
      '[Diagnostics] discovery: searching for $_serviceType '
      '(timeout ${_discoveryTimeout.inSeconds}s)...',
    );

    final stopwatch = Stopwatch()..start();
    Discovery? discovery;
    final completer = Completer<String?>();

    try {
      discovery = await startDiscovery(_serviceType);

      discovery.addServiceListener((service, status) {
        debugPrint(
          '[Diagnostics] discovery: event [$status] '
          'host=${service.host} port=${service.port}',
        );

        // Only accept a discovered service with a valid host and port.
        if (status == ServiceStatus.found &&
            service.host != null &&
            service.host!.isNotEmpty &&
            service.port != null &&
            service.port! > 0 &&
            !completer.isCompleted) {
          final host = normalizeHost(service.host!);
          if (host != service.host) {
            debugPrint(
              '[Diagnostics] discovery: normalized advertised host '
              '"${service.host}" -> "$host"',
            );
          }
          final baseUrl = 'http://$host:${service.port}';

          debugPrint(
            '[Diagnostics] discovery: backend FOUND at $baseUrl '
            'in ${stopwatch.elapsedMilliseconds}ms',
          );

          _cachedBaseUrl = baseUrl;
          completer.complete(baseUrl);
        }
      });

      final result = await completer.future.timeout(
        _discoveryTimeout,
        onTimeout: () {
          debugPrint(
            '[Diagnostics] discovery: TIMED OUT after '
            '${stopwatch.elapsedMilliseconds}ms — no backend on this network. '
            'The next request will retry discovery.',
          );
          return null;
        },
      );

      return result;
    } catch (e, stackTrace) {
      debugPrint(
        '[Diagnostics] discovery: FAILED after ${stopwatch.elapsedMilliseconds}ms '
        '— $e. The next request will retry discovery.',
      );
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } finally {
      if (discovery != null) {
        try {
          await stopDiscovery(discovery);
        } catch (e) {
          debugPrint('[Diagnostics] discovery: could not stop cleanly — $e');
        }
      }
    }
  }

  /// Clears the saved backend address.
  ///
  /// Call this when the server changes address or when a request fails.
  /// Clears the saved backend address.
  ///
  /// Call this when the server changes address or when a request fails.
  static void invalidateCache() {
    debugPrint(
      '[Diagnostics] discovery: clearing cached backend $_cachedBaseUrl — '
      'next request will rediscover.',
    );
    _cachedBaseUrl = null;
  }

  /// Alias for invalidateCache().
  ///
  /// Kept so either method name can be used.
  static void clearCache() {
    invalidateCache();
  }
}

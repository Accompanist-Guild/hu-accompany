import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A newer release than the one running, and where to get it.
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.downloadUrl});

  /// Like "0.2.0".
  final String version;

  /// The installer for this computer, or the release page when the release
  /// has none for it.
  final String downloadUrl;
}

/// Asks the release feed (GitHub's "latest release" for the repository) whether
/// there is a newer version than this one.
///
/// The downloadable apps are not on any store, so nothing updates them; this
/// is how someone finds out. Only builds made by the release workflow have a
/// feed (`--dart-define=UPDATE_FEED=...`): a build for the App Store must not
/// point people elsewhere, and a development build has nothing to compare.
class UpdateChecker {
  UpdateChecker({
    required this.feedUrl,
    required this.currentVersion,
    http.Client? client,
    String? platform,
  }) : _client = client ?? http.Client(),
       _platform = platform ?? Platform.operatingSystem;

  final String feedUrl;
  final String currentVersion;
  final http.Client _client;
  final String _platform;

  /// What each platform's installer is called on a release (see
  /// .github/workflows/release.yml). Fixed names, so the website can link to
  /// the latest one directly.
  static const Map<String, String> installers = {
    'macos': 'Accompanist-macos.dmg',
    'windows': 'Accompanist-windows-setup.exe',
  };

  /// The newer release, or null when this one is the latest, the feed is
  /// unset, or the feed could not be read (offline, rate limited): a failed
  /// check must never bother anyone.
  Future<AvailableUpdate?> check() async {
    if (feedUrl.isEmpty) return null;
    try {
      final response = await _client
          .get(
            Uri.parse(feedUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final release = jsonDecode(response.body) as Map<String, dynamic>;
      if (release['draft'] == true || release['prerelease'] == true) {
        return null;
      }
      final tag = (release['tag_name'] as String? ?? '').replaceFirst(
        RegExp('^v'),
        '',
      );
      if (compareVersions(tag, currentVersion) <= 0) return null;
      final wanted = installers[_platform];
      final assets = (release['assets'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final installer = assets
          .where((a) => a['name'] == wanted)
          .map((a) => a['browser_download_url'] as String?)
          .firstWhere((url) => url != null, orElse: () => null);
      final page = release['html_url'] as String?;
      final url = installer ?? page;
      if (url == null) return null;
      return AvailableUpdate(version: tag, downloadUrl: url);
    } on Object catch (e) {
      debugPrint('[Diagnostics] updates: could not check — $e');
      return null;
    }
  }

  /// Orders versions like "1.2.3" and "1.2.3-beta.1" (a pre-release comes
  /// before its release). Anything that isn't a version sorts first, so a
  /// strange tag is never offered as an update.
  static int compareVersions(String a, String b) {
    final pa = _parse(a), pb = _parse(b);
    if (pa == null || pb == null) {
      return (pa == null ? 0 : 1) - (pb == null ? 0 : 1);
    }
    for (var i = 0; i < 3; i++) {
      if (pa.$1[i] != pb.$1[i]) return pa.$1[i].compareTo(pb.$1[i]);
    }
    if (pa.$2 == pb.$2) return 0;
    if (pa.$2.isEmpty) return 1;
    if (pb.$2.isEmpty) return -1;
    return pa.$2.compareTo(pb.$2);
  }

  static (List<int>, String)? _parse(String version) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?(?:\+.*)?$',
    ).firstMatch(version.trim());
    if (match == null) return null;
    return (
      [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)],
      match.group(4) ?? '',
    );
  }
}

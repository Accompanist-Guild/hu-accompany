import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Apple rejects uploads whose privacy manifest disagrees with the code, and the App Privacy answers in App Store
/// Connect must say the same thing. These tests pin down what the manifest declares, so a change is deliberate.
/// The same list is in docs/app-store/submission-checklist.md, section 2.
void main() {
  final manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();

  /// type name -> (linked to the person?)
  Map<String, bool> collected() {
    final result = <String, bool>{};
    final entry = RegExp(
      r'<key>NSPrivacyCollectedDataType</key>\s*<string>(\w+)</string>\s*<key>NSPrivacyCollectedDataTypeLinked</key>\s*<(true|false)/>',
    );
    for (final m in entry.allMatches(manifest)) {
      result[m.group(1)!] = m.group(2) == 'true';
    }
    return result;
  }

  test('declares exactly the data the app and server handle', () {
    expect(collected(), {
      'NSPrivacyCollectedDataTypeEmailAddress': true,
      'NSPrivacyCollectedDataTypeName': true,
      'NSPrivacyCollectedDataTypeUserID': true,
      // Hum recordings and Talk mode requests are not tied to an account on the server.
      'NSPrivacyCollectedDataTypeAudioData': false,
      'NSPrivacyCollectedDataTypeOtherUserContent': false,
      // Apple: a retained IP address must be declared by how it is used. Cloud Run's request log keeps it.
      'NSPrivacyCollectedDataTypeOtherDiagnosticData': false,
    });
  });

  test('says nothing is used for tracking', () {
    expect(manifest, matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')));
    expect(manifest, isNot(matches(RegExp(r'NSPrivacyCollectedDataTypeTracking</key>\s*<true/>'))));
    expect(manifest, matches(RegExp(r'<key>NSPrivacyTrackingDomains</key>\s*<array/>')));
  });

  test('every declared type is for App Functionality only', () {
    final purposes = RegExp(r'NSPrivacyCollectedDataTypePurpose\w+').allMatches(manifest).map((m) => m.group(0)).toSet();
    expect(purposes, {'NSPrivacyCollectedDataTypePurposes', 'NSPrivacyCollectedDataTypePurposeAppFunctionality'});
  });

  test('gives the one required-reason API it uses a reason Apple lists', () {
    expect(manifest, contains('NSPrivacyAccessedAPICategoryFileTimestamp'));
    // C617.1: metadata of files inside the app's own container (the audio engine reads its own files).
    expect(manifest, matches(RegExp(r'NSPrivacyAccessedAPITypeReasons</key>\s*<array>\s*<string>C617\.1</string>')));
    for (final other in ['SystemBootTime', 'DiskSpace', 'UserDefaults', 'ActiveKeyboard']) {
      expect(manifest, isNot(contains('NSPrivacyAccessedAPICategory$other')), reason: other);
    }
  });

  test('is part of the app target, so it is copied into the built app', () {
    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    // Once where the build file is defined, once where the Resources phase lists it.
    expect(project, matches(RegExp(r'PrivacyInfo\.xcprivacy in Resources \*/ = \{isa = PBXBuildFile')));
    expect(project, matches(RegExp(r'files = \([^)]*PrivacyInfo\.xcprivacy in Resources', dotAll: true)));
  });
}

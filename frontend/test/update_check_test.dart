import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hu_accomponist/features/updates/update_banner.dart';
import 'package:hu_accomponist/integrations/updates/update_checker.dart';

import 'support/auth_fakes.dart' show FakeLinkOpener;

/// GitHub's answer for the latest release, trimmed to what the checker reads.
Map<String, dynamic> release(
  String tag, {
  List<String> assets = const [
    'Accompanist-macos.dmg',
    'Accompanist-windows-setup.exe',
  ],
  bool prerelease = false,
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/o/r/releases/tag/$tag',
  'draft': false,
  'prerelease': prerelease,
  'assets': [
    for (final name in assets)
      {
        'name': name,
        'browser_download_url':
            'https://github.com/o/r/releases/download/$tag/$name',
      },
  ],
};

UpdateChecker checker(
  Object answer, {
  String current = '0.1.0',
  String platform = 'macos',
  int status = 200,
  List<Uri>? asked,
}) => UpdateChecker(
  feedUrl: 'https://api.github.com/repos/o/r/releases/latest',
  currentVersion: current,
  platform: platform,
  client: MockClient((request) async {
    asked?.add(request.url);
    return http.Response(jsonEncode(answer), status);
  }),
);

void main() {
  group('checking', () {
    test('a newer release offers this computer\'s installer', () async {
      final mac = await checker(release('v0.2.0')).check();
      final windows = await checker(
        release('v0.2.0'),
        platform: 'windows',
      ).check();
      expect(mac?.version, '0.2.0');
      expect(mac?.downloadUrl, endsWith('/v0.2.0/Accompanist-macos.dmg'));
      expect(
        windows?.downloadUrl,
        endsWith('/v0.2.0/Accompanist-windows-setup.exe'),
      );
    });

    test('the same or an older release is no update', () async {
      expect(await checker(release('v0.1.0')).check(), isNull);
      expect(
        await checker(release('v0.0.9'), current: '0.1.0').check(),
        isNull,
      );
    });

    test(
      'without an installer for this computer it sends to the release page',
      () async {
        final update = await checker(
          release('v0.2.0', assets: ['Accompanist-macos.dmg']),
          platform: 'windows',
        ).check();
        expect(
          update?.downloadUrl,
          'https://github.com/o/r/releases/tag/v0.2.0',
        );
      },
    );

    test('pre-releases, odd tags and failures never bother anyone', () async {
      expect(
        await checker(release('v9.0.0', prerelease: true)).check(),
        isNull,
      );
      expect(await checker(release('nightly')).check(), isNull);
      expect(
        await checker({'message': 'rate limited'}, status: 403).check(),
        isNull,
      );
      expect(await checker('not a release').check(), isNull);
    });

    test('a build without a feed never asks', () async {
      final asked = <Uri>[];
      final quiet = UpdateChecker(
        feedUrl: '',
        currentVersion: '0.1.0',
        client: MockClient((r) async {
          asked.add(r.url);
          return http.Response('{}', 200);
        }),
      );
      expect(await quiet.check(), isNull);
      expect(asked, isEmpty);
    });

    test('versions order like semver', () {
      int c(String a, String b) => UpdateChecker.compareVersions(a, b);
      expect(c('0.10.0', '0.9.9'), greaterThan(0));
      expect(c('1.0.0', '1.0.0-beta.2'), greaterThan(0));
      expect(c('1.0.0-beta.2', '1.0.0-beta.10'), isNonZero);
      expect(c('1.0.0+5', '1.0.0'), 0);
      expect(c('junk', '0.0.1'), lessThan(0));
    });
  });

  group('banner', () {
    Future<FakeLinkOpener> pumpBanner(
      WidgetTester tester,
      AvailableUpdate? update,
    ) async {
      final links = FakeLinkOpener();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => UpdateBanner(
            check: () async => update,
            links: links,
            child: child!,
          ),
          home: const Scaffold(body: Text('the app')),
        ),
      );
      await tester.pump();
      return links;
    }

    const update = AvailableUpdate(
      version: '0.2.0',
      downloadUrl: 'https://example.org/Accompanist-macos.dmg',
    );

    testWidgets('says a new version is out, and Download opens it', (
      tester,
    ) async {
      final links = await pumpBanner(tester, update);
      expect(find.text('Accompanist 0.2.0 is out.'), findsOneWidget);
      expect(find.text('the app'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(links.opened, ['https://example.org/Accompanist-macos.dmg']);
      expect(find.textContaining('is out'), findsNothing);
    });

    testWidgets('Later hides it', (tester) async {
      final links = await pumpBanner(tester, update);
      await tester.tap(find.text('Later'));
      await tester.pump();
      expect(find.textContaining('is out'), findsNothing);
      expect(links.opened, isEmpty);
    });

    testWidgets('nothing shows when there is no update', (tester) async {
      await pumpBanner(tester, null);
      expect(find.textContaining('is out'), findsNothing);
    });
  });
}

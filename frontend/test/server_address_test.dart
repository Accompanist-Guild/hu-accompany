import 'package:flutter_test/flutter_test.dart';
import 'package:hu_accomponist/integrations/server/ServerDiscovery.dart';

/// A public build is given the server's address when it is built (SERVER_URL), instead of searching the local
/// network for one. The address travels with the app key, a credential, so the rules for accepting one are strict:
/// https, or plain http only to a machine on the same network (for trying a build against a server on your laptop).
void main() {
  group('configuredBaseUrl', () {
    test('nothing configured means "search the network instead"', () {
      expect(ServerDiscovery.configuredBaseUrl(''), isNull);
      expect(ServerDiscovery.configuredBaseUrl('   '), isNull);
    });

    test('accepts an https address and tidies it', () {
      expect(
        ServerDiscovery.configuredBaseUrl('https://api.example.com'),
        'https://api.example.com',
      );
      expect(
        ServerDiscovery.configuredBaseUrl('  https://api.example.com/  '),
        'https://api.example.com',
        reason: 'paths are joined as "<base>/api/..", so a trailing slash would double up',
      );
      expect(
        ServerDiscovery.configuredBaseUrl('https://svc-abc123-uc.a.run.app:8443'),
        'https://svc-abc123-uc.a.run.app:8443',
      );
    });

    test('plain http is accepted only for this machine or the local network', () {
      for (final local in [
        'http://localhost:8000',
        'http://127.0.0.1:8000',
        'http://192.168.1.20:8000',
        'http://10.0.0.5:8080',
        'http://172.16.4.2:8000',
        'http://172.31.255.1:8000',
        'http://my-laptop.local:8000',
      ]) {
        expect(ServerDiscovery.configuredBaseUrl(local), local, reason: local);
      }
    });

    test('plain http to a public address is refused, so the key is never sent in the clear', () {
      for (final unsafe in [
        'http://api.example.com',
        'http://8.8.8.8:8000',
        'http://172.32.0.1:8000', // just outside the private 172.16-31 range
        'http://192.169.1.1:8000', // just outside 192.168
        'http://localhost.example.com', // "localhost" only as a prefix
      ]) {
        expect(ServerDiscovery.configuredBaseUrl(unsafe), isNull, reason: unsafe);
      }
    });

    test('anything that is not a usable web address is refused', () {
      for (final bad in ['ftp://example.com', 'example.com', 'https://', 'not a url', 'https:///path']) {
        expect(ServerDiscovery.configuredBaseUrl(bad), isNull, reason: bad);
      }
    });
  });

  group('resolveBaseUrl with a configured address', () {
    tearDown(() {
      ServerDiscovery.useConfiguredUrl('');
      ServerDiscovery.invalidateCache();
    });

    test('returns it without searching, and a refresh does not search either', () async {
      ServerDiscovery.useConfiguredUrl('https://api.example.com/');

      expect(await ServerDiscovery.resolveBaseUrl(), 'https://api.example.com');
      expect(await ServerDiscovery.resolveBaseUrl(forceRefresh: true), 'https://api.example.com');
    });

    test('a failed request clearing the cache does not lose the configured address', () async {
      ServerDiscovery.useConfiguredUrl('https://api.example.com');

      ServerDiscovery.invalidateCache();

      expect(await ServerDiscovery.resolveBaseUrl(), 'https://api.example.com');
    });

    test('an unusable configured address is ignored rather than trusted', () {
      ServerDiscovery.useConfiguredUrl('http://api.example.com');

      expect(ServerDiscovery.isConfigured, isFalse);
    });
  });
}

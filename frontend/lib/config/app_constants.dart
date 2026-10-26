/// Everything about the app that lives outside it: the pages App Store and
/// Play Store review look for, and who to write to. Change them here, or at
/// build time without touching code:
///
///   flutter build ios --dart-define=PRIVACY_POLICY_URL=https://example.org/privacy
///
/// The pages default to the deployed server's own (`$serverUrl/privacy`), which the server really serves, or
/// to accompanist.app when the build has no server address. Set them to the website's pages once it is up.
abstract final class AppConstants {
  static const String appName = 'Accompanist';

  /// Whether people must sign in before using the app. On by default: the
  /// account carries the roles that let admins and verified contributors
  /// write guidelines (the Guides tab). To build without the login page:
  ///
  ///   flutter run --dart-define=LOGIN_REQUIRED=false
  static const bool loginRequired = bool.fromEnvironment(
    'LOGIN_REQUIRED',
    defaultValue: true,
  );

  /// Whether Talk mode (changing the song by typing or speaking to it) is part of this build. Off by default:
  /// the server answers it through Google Gemini and ElevenLabs, which cost money per use and need their own
  /// privacy wording, so the first public launch leaves it out. Hum, the library, the quiz and practice do not
  /// depend on it. Turn it on with:
  ///
  ///   flutter build macos --dart-define=TALK_MODE=true
  static const bool talkMode = bool.fromEnvironment('TALK_MODE');

  /// Where the backend lives, for a build that talks to a deployed server:
  ///
  ///   flutter build macos --dart-define=SERVER_URL=https://my-service.a.run.app --dart-define=APP_KEY=...
  ///
  /// Left empty (the default), the app searches the local network for a server instead, which is what you want
  /// while developing. See `ServerDiscovery.configuredBaseUrl` for which addresses are accepted.
  static const String serverUrl = String.fromEnvironment('SERVER_URL');

  /// The shared key the server expects in `X-App-Key` (the server's `APP_API_KEY`). It ships inside the app, so
  /// anyone can read it out of the download: it keeps casual traffic out, and the server's rate limits are what
  /// protect it from abuse. Empty means "send none", which is right for a local server that has no key set.
  static const String appKey = String.fromEnvironment('APP_KEY');

  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: serverUrl == ''
        ? 'https://accompanist.app/privacy'
        : '$serverUrl/privacy',
  );

  static const String termsOfServiceUrl = String.fromEnvironment(
    'TERMS_OF_SERVICE_URL',
    defaultValue: serverUrl == ''
        ? 'https://accompanist.app/terms'
        : '$serverUrl/terms',
  );

  /// Support and feedback, and where data requests (export, deletion
  /// questions) are sent.
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@accompanist.app',
  );
}

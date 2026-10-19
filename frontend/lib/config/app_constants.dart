/// Everything about the app that lives outside it: the pages App Store and
/// Play Store review look for, and who to write to. Change them here, or at
/// build time without touching code:
///
///   flutter build ios --dart-define=PRIVACY_POLICY_URL=https://example.org/privacy
///
/// The defaults are placeholders on a reserved `.example` domain, which
/// never resolves. Replace them with the real pages before submitting.
abstract final class AppConstants {
  static const String appName = 'Hu Accomponist';

  /// Whether people must sign in before using the app. Off for now: nothing
  /// in the app needs an account (your shelf and songs live on the phone, and
  /// the server does not tie hums to anyone). The login page and all sign-in
  /// code are still here; turn this on to bring them back:
  ///
  ///   flutter build ios --dart-define=LOGIN_REQUIRED=true
  static const bool loginRequired = bool.fromEnvironment('LOGIN_REQUIRED');

  /// Whether Talk mode (changing the song by typing or speaking to it) is part of this build. On by default. It
  /// does nothing until the person agrees in the consent box (talk_consent.dart), which asks them to confirm they
  /// are 18 or older and says their requests go to Google Gemini and, for voice, ElevenLabs. Both cost money per
  /// use on the server side, so a build for a server without their keys can leave it out:
  ///
  ///   flutter build macos --dart-define=TALK_MODE=false
  ///
  /// Hum, the library, the quiz and practice do not depend on it.
  static const bool talkMode = bool.fromEnvironment('TALK_MODE', defaultValue: true);

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
    defaultValue: 'https://hu-accompany.example/privacy',
  );

  static const String termsOfServiceUrl = String.fromEnvironment(
    'TERMS_OF_SERVICE_URL',
    defaultValue: 'https://hu-accompany.example/terms',
  );

  /// Support and feedback, and where data requests (export, deletion
  /// questions) are sent.
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@hu-accompany.example',
  );
}

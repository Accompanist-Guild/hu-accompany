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

import 'package:url_launcher/url_launcher.dart';

/// Opens things outside the app. An interface so tests don't launch anything.
abstract class LinkOpener {
  /// A web page, in an in-app browser where the platform has one. False if
  /// nothing could open it.
  Future<bool> openWeb(String url);

  /// A new email in the person's mail app. False if there isn't one.
  Future<bool> composeEmail({
    required String to,
    String subject = '',
    String body = '',
  });
}

class SystemLinkOpener implements LinkOpener {
  const SystemLinkOpener();

  @override
  Future<bool> openWeb(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return true;
    } on Object {
      // No in-app browser here (macOS): fall through to the default one.
    }
    return _launch(uri);
  }

  @override
  Future<bool> composeEmail({
    required String to,
    String subject = '',
    String body = '',
  }) {
    // Uri's own query encoding turns spaces into '+', which mail apps show
    // literally; mailto wants %20.
    final query = [
      if (subject.isNotEmpty) 'subject=${Uri.encodeComponent(subject)}',
      if (body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
    ].join('&');
    return _launch(Uri.parse('mailto:$to${query.isEmpty ? '' : '?$query'}'));
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

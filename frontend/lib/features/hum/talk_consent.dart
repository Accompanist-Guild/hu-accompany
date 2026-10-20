import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/integrations/links/link_opener.dart';

/// Whether the person has said yes to Talk mode sending what they type or
/// say to outside AI services (Google Gemini, and ElevenLabs for voice).
///
/// Apple's review rules require telling people where their data goes and
/// getting an explicit yes before it goes to a third-party AI service, so
/// nothing is sent, and the microphone does not start, until this is granted.
abstract class TalkConsent {
  Future<bool> isGranted();
  Future<void> grant();
  Future<void> withdraw();
}

/// Remembered on the phone. The key carries a version: if what Talk mode
/// shares ever changes, bump it and everyone is asked again. v2: adults only,
/// and the disclosure that ElevenLabs may keep and reuse voice recordings.
class PrefsTalkConsent implements TalkConsent {
  const PrefsTalkConsent();

  static const _key = 'talk_ai_consent_v2';

  @override
  Future<bool> isGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> grant() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  @override
  Future<void> withdraw() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// True if Talk mode may send the person's requests onward: either they have
/// agreed before, or they agree now. Tapping outside the box is neither a
/// yes nor a no, so the box stays until they choose.
Future<bool> ensureTalkConsent(
  BuildContext context, {
  TalkConsent consent = const PrefsTalkConsent(),
  LinkOpener links = const SystemLinkOpener(),
}) async {
  if (await consent.isGranted()) return true;
  if (!context.mounted) return false;
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TalkConsentDialog(links: links),
  );
  if (agreed != true) return false;
  await consent.grant();
  return true;
}

/// The question itself. Google's and ElevenLabs' terms both bar people under
/// 18, so "Agree" stays off until the person says they are an adult.
class _TalkConsentDialog extends StatefulWidget {
  const _TalkConsentDialog({required this.links});

  final LinkOpener links;

  @override
  State<_TalkConsentDialog> createState() => _TalkConsentDialogState();
}

class _TalkConsentDialogState extends State<_TalkConsentDialog> {
  bool _adult = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share your requests with AI services?'),
      // The text scrolls on a small phone; the box to tick does not, so it can
      // never be off screen while "Agree" is switched off.
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Talk mode lets you change your song by typing or speaking. '
                    'To do that, the app sends:',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Your request, and a description of your song, to '
                    'Google Gemini, an AI service that works out what to change.',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• If you speak, your voice recording to ElevenLabs, which '
                    'turns it into text and speaks the replies.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your hum recordings are not sent to either of them. Both '
                    'companies handle this data under their own terms, and ElevenLabs '
                    'may keep your voice recording and use it to improve its own '
                    'services. You can turn this off at any time in Settings, which '
                    'stops anything more being sent but cannot take back what was '
                    'already sent.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These services are for adults only, so Talk mode is for '
                    'people 18 or older. The rest of the app does not need this.',
                  ),
                ],
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _adult,
            onChanged: (v) => setState(() => _adult = v ?? false),
            title: const Text('I am 18 or older'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => widget.links.openWeb(AppConstants.privacyPolicyUrl),
          child: const Text('Privacy Policy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: _adult ? () => Navigator.pop(context, true) : null,
          child: const Text('Agree and continue'),
        ),
      ],
    );
  }
}

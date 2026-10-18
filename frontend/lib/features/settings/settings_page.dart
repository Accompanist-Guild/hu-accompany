import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/features/hum/file_sharer.dart';
import 'package:hu_accomponist/features/hum/talk_consent.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/links/link_opener.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';
import 'package:hu_accomponist/shared/ui/Press_Scale.dart';

/// The app's version and build number, as the store listing shows them.
class AppVersion {
  final String version;
  final String build;
  const AppVersion(this.version, this.build);

  static Future<AppVersion> fromPlatform() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(info.version, info.buildNumber);
  }

  @override
  String toString() => build.isEmpty ? version : '$version ($build)';
}

/// Account, tutorial, legal links, data requests and support, in one place.
///
/// Everything the page reaches outside the app for is handed in, so tests
/// can stand in for the browser, the mail app, the share sheet and the
/// platform's package info.
class SettingsPage extends StatefulWidget {
  final AuthController auth;
  final LinkOpener links;
  final FileSharer sharer;
  final TalkConsent consent;
  final Future<AppVersion> Function() loadVersion;

  /// Whether the app has accounts. Null means the build setting,
  /// [AppConstants.loginRequired]. Without accounts, Log out, Delete account
  /// and Export my data have nothing to act on, so they are left out.
  final bool? loginRequired;

  /// Whether Talk mode is part of the app, which decides if its permission row is shown. Null means the build
  /// setting, [AppConstants.talkMode].
  final bool? talkMode;

  /// Defaults to asking the shell, which is where the tutorial lives.
  final VoidCallback? onReplayTutorial;

  const SettingsPage({
    super.key,
    required this.auth,
    this.links = const SystemLinkOpener(),
    this.sharer = const SystemFileSharer(),
    this.consent = const PrefsTalkConsent(),
    this.loadVersion = AppVersion.fromPlatform,
    this.loginRequired,
    this.talkMode,
    this.onReplayTutorial,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Future<AppVersion> _version = widget.loadVersion();

  bool get _hasAccounts => widget.loginRequired ?? AppConstants.loginRequired;
  bool get _hasTalkMode => widget.talkMode ?? AppConstants.talkMode;

  /// Whether Talk mode may share requests with the AI services. Null while loading.
  bool? _talkAllowed;

  @override
  void initState() {
    super.initState();
    widget.consent.isGranted().then((allowed) {
      if (mounted) setState(() => _talkAllowed = allowed);
    });
  }

  Future<void> _talkSharing() async {
    if (_talkAllowed != true) {
      _say('You will be asked the next time you use Talk mode.');
      return;
    }
    final confirmed = await _confirm(
      title: 'Stop sharing with AI services?',
      message:
          'Talk mode will stop working until you agree again. Nothing you '
          'already sent is affected.',
      action: 'Stop sharing',
    );
    if (!confirmed) return;
    await widget.consent.withdraw();
    if (mounted) setState(() => _talkAllowed = false);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(Space.md),
        ),
      );
  }

  String _friendly(Object e) =>
      e is ApiException ? e.message : 'Something went wrong. Please try again.';

  Future<void> _openPage(String url) async {
    if (!await widget.links.openWeb(url)) _say("Couldn't open that page.");
  }

  void _replayTutorial() {
    final replay =
        widget.onReplayTutorial ?? ShellScope.maybeOf(context)?.replayTutorial;
    replay?.call();
  }

  Future<void> _showLicenses() async {
    final version = await _version.catchError((_) => const AppVersion('', ''));
    if (!mounted) return;
    showLicensePage(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: version.toString(),
    );
  }

  Future<void> _logOut() async {
    final confirmed = await _confirm(
      title: 'Log out?',
      message: 'You will need to sign in again to use the app.',
      action: 'Log out',
    );
    if (confirmed) await widget.auth.signOut();
  }

  Future<void> _exportData() async {
    final origin = _originOf(context);
    final data = await _withProgress(() => widget.auth.exportData());
    if (data == null) return;
    try {
      await widget.sharer.share(
        Uint8List.fromList(utf8.encode(data)),
        filename: 'hu-accompany-data.json',
        mimeType: 'application/json',
        origin: origin,
      );
    } on Object {
      _say("Couldn't open the share sheet.");
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirm(
      title: 'Delete your account?',
      message:
          'This permanently deletes your account and signs you out on every '
          'device. It cannot be undone.\n\nScores, songs and practice '
          'history saved on this device are not removed.',
      action: 'Delete account',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    // Deleting signs the person out, which replaces this page, so say
    // nothing more here on success: the login page is the confirmation.
    await _withProgress(() => widget.auth.deleteAccount());
  }

  Future<void> _contactSupport() async {
    final version = await _version.catchError((_) => const AppVersion('', ''));
    final opened = await widget.links.composeEmail(
      to: AppConstants.supportEmail,
      subject: '${AppConstants.appName} support',
      body:
          '\n\n---\nApp ${version.toString()} on '
          '${defaultTargetPlatform.name}',
    );
    if (opened || !mounted) return;
    // No mail app set up: show the address so it can be copied.
    await showAdaptiveDialog<void>(
      context: context,
      builder: (context) => _dialog(
        title: 'Contact support',
        message: 'Email us at ${AppConstants.supportEmail}.',
        actions: [
          _DialogAction(
            label: 'Copy address',
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: AppConstants.supportEmail),
              );
              if (context.mounted) Navigator.pop(context);
              _say('Address copied.');
            },
          ),
          _DialogAction(
            label: 'Close',
            onPressed: () => Navigator.pop(context),
            isDefault: true,
          ),
        ],
      ),
    );
  }

  /// A platform confirmation alert. True only if the action was chosen.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => _dialog(
        title: title,
        message: message,
        actions: [
          _DialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
            isDefault: true,
          ),
          _DialogAction(
            label: action,
            destructive: destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _dialog({
    required String title,
    required String message,
    required List<_DialogAction> actions,
  }) {
    return AlertDialog.adaptive(
      title: Text(title),
      content: Text(message),
      actions: [for (final action in actions) action.build(context)],
    );
  }

  /// Runs [work] behind a blocking spinner. Null if it failed, after
  /// saying why.
  Future<T?> _withProgress<T>(Future<T> Function() work) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
    );
    try {
      return await work();
    } on Object catch (e) {
      _say(_friendly(e));
      return null;
    } finally {
      navigator.pop();
    }
  }

  /// Where a share sheet should anchor (iPads need it): this page's middle.
  static Rect? _originOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.user;

    return Scaffold(
      backgroundColor: PracticePalette.ivory,
      body: SafeArea(
        child: ListView(
          physics: AppScroll.physics,
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.xl,
            Space.lg,
            Space.xxl,
          ),
          children: [
            const Text(
              'SETTINGS',
              style: TextStyle(
                color: PracticePalette.gold,
                fontSize: 11,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              _hasAccounts ? 'Your account' : 'Your settings',
              style: TextStyle(
                color: PracticePalette.brown,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.lg),
            if (user != null)
              _ProfileCard(name: user.displayName, email: user.email),
            const SizedBox(height: Space.lg),
            _Section(
              title: 'Getting around',
              rows: [
                _SettingsRow(
                  icon: Icons.school_outlined,
                  label: 'Replay the tutorial',
                  onTap: _replayTutorial,
                ),
              ],
            ),
            _Section(
              title: 'Legal & policies',
              rows: [
                _SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  external: true,
                  onTap: () => _openPage(AppConstants.privacyPolicyUrl),
                ),
                _SettingsRow(
                  icon: Icons.description_outlined,
                  label: 'Terms of Service',
                  external: true,
                  onTap: () => _openPage(AppConstants.termsOfServiceUrl),
                ),
                _SettingsRow(
                  icon: Icons.code_rounded,
                  label: 'Open-source licenses',
                  onTap: _showLicenses,
                ),
              ],
            ),
            _Section(
              title: 'Account & data',
              rows: [
                if (_hasTalkMode)
                  _SettingsRow(
                    icon: Icons.record_voice_over_outlined,
                    label: 'Talk mode and AI services',
                    subtitle: _talkAllowed == true
                        ? 'Allowed. Tap to stop sharing with Google Gemini and ElevenLabs'
                        : 'Not allowed. You will be asked when you use Talk mode',
                    onTap: _talkSharing,
                  ),
                if (_hasAccounts) ...[
                  _SettingsRow(
                    icon: Icons.download_outlined,
                    label: 'Export my data',
                    subtitle: 'A copy of what we hold about your account',
                    onTap: _exportData,
                  ),
                  _SettingsRow(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete account',
                    subtitle: 'Permanently removes your account',
                    destructive: true,
                    onTap: _deleteAccount,
                  ),
                ],
              ],
            ),
            _Section(
              title: 'Support',
              rows: [
                _SettingsRow(
                  icon: Icons.mail_outline_rounded,
                  label: 'Contact support or send feedback',
                  subtitle: AppConstants.supportEmail,
                  onTap: _contactSupport,
                ),
              ],
            ),
            if (_hasAccounts)
              _Section(
                rows: [
                  _SettingsRow(
                    icon: Icons.logout_rounded,
                    label: 'Log out',
                    onTap: _logOut,
                  ),
                ],
              ),
            const SizedBox(height: Space.sm),
            Center(
              child: FutureBuilder<AppVersion>(
                future: _version,
                builder: (context, snapshot) => Text(
                  snapshot.hasData
                      ? '${AppConstants.appName}  ·  Version ${snapshot.data!.version}'
                            '${snapshot.data!.build.isEmpty ? '' : ' (build ${snapshot.data!.build})'}'
                      : AppConstants.appName,
                  style: TextStyle(
                    color: PracticePalette.mutedBrown.withValues(alpha: 0.8),
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  const _ProfileCard({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: _cardDecoration,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PracticePalette.gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: const TextStyle(
                color: PracticePalette.gold,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PracticePalette.brown,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PracticePalette.mutedBrown,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final BoxDecoration _cardDecoration = BoxDecoration(
  color: PracticePalette.paper,
  borderRadius: Radii.cardRadius,
  border: Border.all(color: PracticePalette.lightGold.withValues(alpha: 0.65)),
  boxShadow: Elevations.card(PracticePalette.brown),
);

class _Section extends StatelessWidget {
  final String? title;
  final List<_SettingsRow> rows;
  const _Section({this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xxs, 0, 0, Space.xs),
              child: Text(
                title!.toUpperCase(),
                style: const TextStyle(
                  color: PracticePalette.mutedBrown,
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Container(
            decoration: _cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: Space.md,
                      endIndent: Space.md,
                      color: PracticePalette.lightGold.withValues(alpha: 0.4),
                    ),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  /// Opens something outside the app.
  final bool external;
  final bool destructive;

  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.external = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? PracticePalette.alert : PracticePalette.brown;
    return PressScale(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + 2,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: destructive ? PracticePalette.alert : PracticePalette.gold,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 15)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: PracticePalette.mutedBrown,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              external
                  ? Icons.open_in_new_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
              color: PracticePalette.mutedBrown.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// A button on a platform alert: Cupertino's on iOS and macOS, Material's
/// elsewhere, so the alert looks like the platform's own.
class _DialogAction {
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
  final bool isDefault;

  const _DialogAction({
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.isDefault = false,
  });

  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return CupertinoDialogAction(
        onPressed: onPressed,
        isDestructiveAction: destructive,
        isDefaultAction: isDefault,
        child: Text(label),
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: destructive
            ? PracticePalette.alert
            : PracticePalette.gold,
      ),
      child: Text(label),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/integrations/links/link_opener.dart';
import 'package:hu_accomponist/integrations/updates/update_checker.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Says so, at the top of the app, when a newer version is out, with a button
/// that downloads it. Checked once per launch; "Later" hides it until the next.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({
    super.key,
    required this.child,
    this.check,
    this.links = const SystemLinkOpener(),
  });

  final Widget child;

  /// How to look for a newer version; [defaultCheck] when not given.
  final Future<AvailableUpdate?> Function()? check;
  final LinkOpener links;

  /// Null when this build doesn't check (see [AppConstants.updateFeed]).
  static final Future<AvailableUpdate?> Function()? defaultCheck =
      AppConstants.updateFeed.isEmpty
      ? null
      : () async => UpdateChecker(
          feedUrl: AppConstants.updateFeed,
          currentVersion: (await PackageInfo.fromPlatform()).version,
        ).check();

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  AvailableUpdate? _update;

  @override
  void initState() {
    super.initState();
    (widget.check ?? UpdateBanner.defaultCheck)?.call().then((update) {
      if (mounted && update != null) setState(() => _update = update);
    });
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    return Stack(
      children: [
        widget.child,
        if (update != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _Banner(
                      version: update.version,
                      onDownload: () {
                        widget.links.openWeb(update.downloadUrl);
                        setState(() => _update = null);
                      },
                      onLater: () => setState(() => _update = null),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.version,
    required this.onDownload,
    required this.onLater,
  });

  final String version;
  final VoidCallback onDownload;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PracticePalette.brown,
      elevation: 6,
      borderRadius: Radii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.xs,
          Space.xs,
          Space.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${AppConstants.appName} $version is out.',
                style: const TextStyle(
                  color: PracticePalette.paper,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onLater,
              style: TextButton.styleFrom(
                foregroundColor: PracticePalette.lightGold,
              ),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: onDownload,
              style: FilledButton.styleFrom(
                backgroundColor: PracticePalette.paper,
                foregroundColor: PracticePalette.brown,
              ),
              child: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}

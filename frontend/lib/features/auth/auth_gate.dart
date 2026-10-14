import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/auth/login_page.dart';
import 'package:hu_accomponist/features/onboarding/onboarding_store.dart';
import 'package:hu_accomponist/features/shell/app_shell.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/links/link_opener.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Chooses between the login page and the app from the auth state, so every
/// way of signing in or out (the form, Log Out, a deleted account, a token
/// the server no longer accepts) lands in the right place.
class AuthGate extends StatelessWidget {
  final AuthController auth;
  final ShellController shell;
  final OnboardingStore onboarding;
  final LinkOpener links;

  /// Passed on to the shell, so tests can leave out the real pages.
  @visibleForTesting
  final Widget Function(int slot)? pageBuilder;

  const AuthGate({
    super.key,
    required this.auth,
    required this.shell,
    this.onboarding = const OnboardingStore(),
    this.links = const SystemLinkOpener(),
    this.pageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => AnimatedSwitcher(
        duration: Motion.page,
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        child: switch (auth.status) {
          // Held on the same dark colour as the splash while the stored
          // session is read, so the splash doesn't flicker.
          AuthStatus.restoring => const ColoredBox(
            key: ValueKey('restoring'),
            color: TurntablePalette.background,
            child: SizedBox.expand(),
          ),
          AuthStatus.signedOut => LoginPage(
            key: const ValueKey('login'),
            auth: auth,
            links: links,
          ),
          AuthStatus.signedIn => AppShell(
            key: const ValueKey('app'),
            auth: auth,
            controller: shell,
            onboarding: onboarding,
            pageBuilder: pageBuilder,
          ),
        },
      ),
    );
  }
}

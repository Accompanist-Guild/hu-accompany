import 'package:flutter/material.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/features/home/Vinyl_Disk_Painter.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/links/link_opener.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Where the app opens when nobody is signed in: sign in, or create an
/// account. A successful attempt updates [AuthController], which swaps this
/// page for the app; nothing here navigates.
class LoginPage extends StatefulWidget {
  final AuthController auth;
  final LinkOpener links;

  const LoginPage({
    super.key,
    required this.auth,
    this.links = const SystemLinkOpener(),
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _creating = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  static const int _minPassword = 8;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _setMode({required bool creating}) {
    if (_creating == creating) return;
    setState(() {
      _creating = creating;
      _error = null;
    });
  }

  /// A message for the first thing wrong with the form, or null if it can
  /// be sent.
  String? _problem() {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    if (_password.text.isEmpty) return 'Enter your password.';
    if (_creating && _password.text.length < _minPassword) {
      return 'Choose a password of at least $_minPassword characters.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_creating) {
        await widget.auth.register(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
        );
      } else {
        await widget.auth.signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // Signed in: the auth gate replaces this page, so nothing to do.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PracticePalette.ivory,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(child: _form()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: VinylDisk(
            size: 72,
            rotation: 0,
            label: '',
            diskColor: TurntablePalette.diskPractice,
          ),
        ),
        const SizedBox(height: Space.lg),
        Text(
          AppConstants.appName.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: PracticePalette.gold,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: Space.xs),
        AnimatedSwitcher(
          duration: Motion.fast,
          child: Text(
            _creating ? 'Create your account' : 'Welcome back',
            key: ValueKey(_creating),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PracticePalette.brown,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: _creating
              ? Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _field(
                    controller: _name,
                    label: 'Name (optional)',
                    icon: Icons.person_outline_rounded,
                    hints: const [AutofillHints.name],
                    capitalization: TextCapitalization.words,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        _field(
          controller: _email,
          label: 'Email',
          icon: Icons.mail_outline_rounded,
          hints: const [AutofillHints.email],
          keyboard: TextInputType.emailAddress,
        ),
        const SizedBox(height: Space.sm),
        _field(
          controller: _password,
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          hints: [
            _creating ? AutofillHints.newPassword : AutofillHints.password,
          ],
          obscure: !_showPassword,
          action: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          suffix: IconButton(
            tooltip: _showPassword ? 'Hide password' : 'Show password',
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
            color: PracticePalette.mutedBrown,
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    _error!,
                    key: const Key('login-error'),
                    style: const TextStyle(
                      color: PracticePalette.alert,
                      fontSize: 13,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: Space.lg),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: PracticePalette.gold,
            foregroundColor: PracticePalette.paper,
            minimumSize: const Size.fromHeight(48),
            shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PracticePalette.paper,
                  ),
                )
              : Text(_creating ? 'Create account' : 'Sign in'),
        ),
        const SizedBox(height: Space.xs),
        TextButton(
          onPressed: _busy ? null : () => _setMode(creating: !_creating),
          style: TextButton.styleFrom(foregroundColor: PracticePalette.gold),
          child: Text(
            _creating
                ? 'I already have an account'
                : "New here? Create an account",
          ),
        ),
        const SizedBox(height: Space.lg),
        _legal(),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required List<String> hints,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    TextInputAction action = TextInputAction.next,
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: Radii.cardRadius,
      borderSide: BorderSide(color: color),
    );
    return TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: obscure,
      keyboardType: keyboard,
      textCapitalization: capitalization,
      textInputAction: action,
      autofillHints: hints,
      autocorrect: false,
      enableSuggestions: !obscure,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: PracticePalette.brown, fontSize: 15),
      cursorColor: PracticePalette.gold,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: PracticePalette.mutedBrown),
        floatingLabelStyle: const TextStyle(color: PracticePalette.gold),
        prefixIcon: Icon(icon, size: 20, color: PracticePalette.gold),
        suffixIcon: suffix,
        filled: true,
        fillColor: PracticePalette.paper,
        enabledBorder: border(PracticePalette.lightGold.withValues(alpha: 0.8)),
        disabledBorder: border(
          PracticePalette.lightGold.withValues(alpha: 0.4),
        ),
        focusedBorder: border(PracticePalette.gold),
      ),
    );
  }

  Widget _legal() {
    const style = TextStyle(
      color: PracticePalette.mutedBrown,
      fontSize: 12,
      height: 1.4,
    );
    Widget link(String text, String url) => GestureDetector(
      onTap: () => widget.links.openWeb(url),
      child: Text(
        text,
        style: style.copyWith(
          color: PracticePalette.gold,
          decoration: TextDecoration.underline,
        ),
      ),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('By continuing you agree to the ', style: style),
        link('Terms of Service', AppConstants.termsOfServiceUrl),
        const Text(' and ', style: style),
        link('Privacy Policy', AppConstants.privacyPolicyUrl),
        const Text('.', style: style),
      ],
    );
  }
}

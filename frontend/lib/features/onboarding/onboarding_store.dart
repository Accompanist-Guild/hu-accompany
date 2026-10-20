import 'package:shared_preferences/shared_preferences.dart';

/// Whether the first-run tutorial has been finished or skipped. It stays set
/// across restarts and sign-outs, so the tutorial only ever starts by itself
/// once; Settings can still replay it by hand.
class OnboardingStore {
  const OnboardingStore();

  static const key = 'hasCompletedOnboarding';

  Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<void> setCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, completed);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

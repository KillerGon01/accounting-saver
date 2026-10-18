import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

import 'enable_ai.dart';

/// Which App Check provider to use for web, without depending on the
/// Firebase SDK: a pure result `main.dart` translates into the
/// concrete `WebProvider` (`WebDebugProvider` or
/// `ReCaptchaEnterpriseProvider`).
enum WebAppCheckProviderChoice { none, debug, recaptchaEnterprise }

/// Which App Check provider to use for Android, just as pure. No
/// production value: there's no production App Check provider
/// configured for Android (Play Integrity would require linking the
/// app in Play Console, not done, see docs/security.md), so an
/// Android release never gets to activate App Check (see
/// `chooseAppCheckConfig`): `debug` is only used in debug/profile.
enum AndroidAppCheckProviderChoice { none, debug }

/// Result of deciding, from the build variables, which App Check
/// providers to activate and whether the AI should really be shown
/// in this build. Pure logic (no Firebase, and the only Flutter
/// symbol it uses, `kReleaseMode`, is resolved before reaching here)
/// so it can be tested with `chooseAppCheckConfig` and fakes, without
/// any real Firebase project.
class AppCheckConfig {
  const AppCheckConfig({
    required this.effectiveEnableAi,
    required this.webProvider,
    required this.androidProvider,
  });

  /// Whether the AI should really be shown and used in this build.
  /// In a non-release build, it matches `enableAi` (the debug
  /// provider needs no key, neither on web nor on Android). In
  /// release, it's only true on **web** and with a non-empty
  /// reCAPTCHA Enterprise key: there's no production App Check
  /// provider for Android (Play Integrity would require linking the
  /// app in Play Console, not done), so an Android release hides the
  /// AI instead of letting it fail with an App Check 403 (see
  /// `TransactionsScreen` and `docs/security.md`).
  final bool effectiveEnableAi;

  final WebAppCheckProviderChoice webProvider;
  final AndroidAppCheckProviderChoice androidProvider;
}

/// Decides the App Check configuration. [isRelease] and [isWeb] are
/// passed as parameters (normally `kReleaseMode` and `kIsWeb`)
/// instead of being read in here, so this function doesn't depend on
/// Flutter and can be tested with any combination, including ones
/// that never occur together in a real build (like `isRelease: true`
/// in a test).
AppCheckConfig chooseAppCheckConfig({
  required bool enableAi,
  required bool isRelease,
  required bool isWeb,
  required String recaptchaSiteKey,
}) {
  if (!enableAi) {
    return const AppCheckConfig(
      effectiveEnableAi: false,
      webProvider: WebAppCheckProviderChoice.none,
      androidProvider: AndroidAppCheckProviderChoice.none,
    );
  }

  if (!isRelease) {
    // Debug and profile: debug provider, on web and Android alike,
    // needing no key.
    return const AppCheckConfig(
      effectiveEnableAi: true,
      webProvider: WebAppCheckProviderChoice.debug,
      androidProvider: AndroidAppCheckProviderChoice.debug,
    );
  }

  // Release on any platform that isn't web: there's no production
  // App Check provider for Android, so the AI is hidden just as
  // with `enableAi: false`, without activating App Check.
  if (!isWeb) {
    return const AppCheckConfig(
      effectiveEnableAi: false,
      webProvider: WebAppCheckProviderChoice.none,
      androidProvider: AndroidAppCheckProviderChoice.none,
    );
  }

  // Release on web: never the debug provider; requires a non-empty
  // reCAPTCHA Enterprise key, or the AI is hidden instead of letting
  // it fail.
  final hasSiteKey = recaptchaSiteKey.isNotEmpty;
  return AppCheckConfig(
    effectiveEnableAi: hasSiteKey,
    webProvider: hasSiteKey ? WebAppCheckProviderChoice.recaptchaEnterprise : WebAppCheckProviderChoice.none,
    androidProvider: AndroidAppCheckProviderChoice.none,
  );
}

/// App Check configuration for this build, computed once from the
/// build constants (`enable_ai.dart`), from `kReleaseMode`, and from
/// `kIsWeb`. `main.dart` uses it to decide what to activate;
/// `effectiveEnableAi` is what screens should check to show or hide
/// the AI controls (instead of `enableAi` on its own).
final appCheckConfig = chooseAppCheckConfig(
  enableAi: enableAi,
  isRelease: kReleaseMode,
  isWeb: kIsWeb,
  recaptchaSiteKey: recaptchaSiteKey,
);

/// Whether the AI should really be shown in this build (see
/// [AppCheckConfig.effectiveEnableAi]). Screens import this symbol
/// instead of `enableAi` to decide whether to show the chat or
/// natural language input.
final effectiveEnableAi = appCheckConfig.effectiveEnableAi;

import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';

import 'app_check_config.dart';
import 'enable_ai.dart';

/// Activates App Check if this build calls for it (`appCheckConfig`,
/// see `app_check_config.dart`), and redeems a token in the
/// background. Extracted from `main.dart` so `eval_main.dart` (see
/// `docs/evaluation.md`) can reuse it as-is, without duplicating this
/// logic.
Future<void> activateAppCheckIfNeeded() async {
  // App Check is only activated if the AI is actually usable in this
  // build (`effectiveEnableAi`, computed in `app_check_config.dart`):
  // not needed with ENABLE_AI=false, nor in a release with no
  // reCAPTCHA key or that isn't web (the AI is hidden either way, see
  // `TransactionsScreen`), so activating App Check would be useless.
  // In particular, this means an Android release never gets here:
  // there's no production App Check provider for Android.
  if (!appCheckConfig.effectiveEnableAi) return;

  final webProvider = switch (appCheckConfig.webProvider) {
    // Debug: only in non-release builds (see AppCheckConfig). The
    // token is generated on the device and has to be registered by
    // hand in the Firebase console; see docs/security.md.
    WebAppCheckProviderChoice.debug => WebDebugProvider(),
    // Production: Fraud Defense (reCAPTCHA Enterprise). The site key
    // is never in the code: it comes from --dart-define at compile
    // time (see docs/security.md).
    WebAppCheckProviderChoice.recaptchaEnterprise => ReCaptchaEnterpriseProvider(recaptchaSiteKey),
    WebAppCheckProviderChoice.none => throw StateError(
      'effectiveEnableAi es true, pero webProvider es none: inconsistencia en AppCheckConfig.',
    ),
  };

  if (appCheckConfig.androidProvider == AndroidAppCheckProviderChoice.debug) {
    // Non-release builds: debug provider on Android, same as on web.
    await FirebaseAppCheck.instance.activate(
      providerWeb: webProvider,
      providerAndroid: const AndroidDebugProvider(),
    );
  } else {
    // Release on web (the only release where `effectiveEnableAi` can
    // be true, see `chooseAppCheckConfig`): `providerAndroid` isn't
    // passed because it isn't needed on this platform, not because
    // there's a production provider for Android pending use.
    await FirebaseAppCheck.instance.activate(providerWeb: webProvider);
  }
  // Redeems the App Check token right away, in the background, so
  // the first time someone uses natural language input doesn't also
  // pay for that redemption (it doesn't spend Gemini quota: it only
  // talks to App Check). If it fails, nothing happens: it will be
  // retried on the first call.
  unawaited(FirebaseAppCheck.instance.getToken().catchError((_) => null));
}

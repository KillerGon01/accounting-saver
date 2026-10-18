/// The AI interface (natural language input, and whatever comes
/// after) is only enabled if compiled with
/// `--dart-define=ENABLE_AI=true`. Disabled by default, so as not to
/// require everyone who clones the repository to set up Firebase AI
/// Logic and App Check just to be able to compile the app.
///
/// This is the request ("AI is wanted"), not whether the AI is
/// actually available in this build: for that, see
/// `effectiveEnableAi` in `app_check_config.dart`, which also
/// requires a reCAPTCHA key in release. `main.dart` uses this
/// constant only to decide the debug provider in non-release builds.
const enableAi = bool.fromEnvironment('ENABLE_AI');

/// reCAPTCHA Enterprise site key for App Check in production (web),
/// passed with `--dart-define=RECAPTCHA_SITE_KEY=...` at compile
/// time. Never written into the repository: empty by default, and
/// only has a value in the build environment of whoever does the
/// production build (see docs/security.md).
const recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');

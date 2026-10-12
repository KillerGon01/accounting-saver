import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';

import 'app_check_config.dart';
import 'enable_ai.dart';

/// Activa App Check si corresponde en esta build (`appCheckConfig`, ver
/// `app_check_config.dart`), y canjea un token en segundo plano. Extraído
/// de `main.dart` para que `eval_main.dart` (ver `docs/evaluation.md`) lo
/// reutilice tal cual, sin duplicar esta lógica.
Future<void> activateAppCheckIfNeeded() async {
  // Solo se activa App Check si la IA es realmente usable en esta build
  // (`effectiveEnableAi`, calculado en `app_check_config.dart`): con
  // ENABLE_AI=false no hace falta, y tampoco en un release sin clave de
  // reCAPTCHA o que no sea web (la IA se oculta igual, ver
  // `TransactionsScreen`), así que activar App Check no serviría de nada.
  // En particular, esto significa que un release de Android nunca entra
  // aquí: no hay ningún proveedor de App Check de producción para Android.
  if (!appCheckConfig.effectiveEnableAi) return;

  final webProvider = switch (appCheckConfig.webProvider) {
    // Depuración: solo en builds que no son de release (ver
    // AppCheckConfig). El token se genera en el dispositivo y hay que
    // registrarlo a mano en la consola de Firebase; ver docs/security.md.
    WebAppCheckProviderChoice.debug => WebDebugProvider(),
    // Producción: Fraud Defense (reCAPTCHA Enterprise). La clave de
    // sitio nunca está en el código: viene de --dart-define en tiempo
    // de compilación (ver docs/security.md).
    WebAppCheckProviderChoice.recaptchaEnterprise => ReCaptchaEnterpriseProvider(recaptchaSiteKey),
    WebAppCheckProviderChoice.none => throw StateError(
      'effectiveEnableAi es true, pero webProvider es none: inconsistencia en AppCheckConfig.',
    ),
  };

  if (appCheckConfig.androidProvider == AndroidAppCheckProviderChoice.debug) {
    // Builds que no son de release: proveedor de depuración en Android,
    // igual que en web.
    await FirebaseAppCheck.instance.activate(
      providerWeb: webProvider,
      providerAndroid: const AndroidDebugProvider(),
    );
  } else {
    // Release en web (el único release donde `effectiveEnableAi` puede
    // ser true, ver `chooseAppCheckConfig`): no se pasa `providerAndroid`
    // porque no hace falta en esta plataforma, no porque haya un
    // proveedor de producción para Android pendiente de usar.
    await FirebaseAppCheck.instance.activate(providerWeb: webProvider);
  }
  // Canjea el token de App Check ya, en segundo plano, para que la
  // primera vez que alguien use la entrada en lenguaje natural no pague
  // también ese canje (no gasta cuota de Gemini: solo habla con App
  // Check). Si falla, no pasa nada: se reintentará en la primera llamada.
  unawaited(FirebaseAppCheck.instance.getToken().catchError((_) => null));
}

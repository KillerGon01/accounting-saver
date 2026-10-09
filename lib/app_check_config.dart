import 'package:flutter/foundation.dart' show kReleaseMode;

import 'enable_ai.dart';

/// Qué proveedor de App Check usar para web, sin depender del SDK de
/// Firebase: un resultado puro que `main.dart` traduce al `WebProvider`
/// concreto (`WebDebugProvider` o `ReCaptchaEnterpriseProvider`).
enum WebAppCheckProviderChoice { none, debug, recaptchaEnterprise }

/// Qué proveedor de App Check usar para Android, igual de puro.
/// `productionDefault` significa "no pasar `providerAndroid` a
/// `activate()` y dejar que el SDK use el suyo" (`AndroidPlayIntegrityProvider`
/// por defecto): no hay una clave que comprobar aquí como en web, pero
/// tampoco se ha configurado ni probado Play Integrity en la consola de
/// Firebase/Play Console, así que sigue siendo un pendiente (ver
/// docs/security.md), no una implementación terminada.
enum AndroidAppCheckProviderChoice { none, debug, productionDefault }

/// Resultado de decidir, a partir de las variables de compilación, qué
/// proveedores de App Check activar y si la IA debe mostrarse de verdad en
/// esta build. Lógica pura (sin Firebase, y el único símbolo de Flutter
/// que usa `kReleaseMode` se resuelve antes de llegar aquí) para poder
/// probarla con `chooseAppCheckConfig` y fakes, sin ningún proyecto de
/// Firebase real.
class AppCheckConfig {
  const AppCheckConfig({
    required this.effectiveEnableAi,
    required this.webProvider,
    required this.androidProvider,
  });

  /// Si la IA debe mostrarse y usarse de verdad en esta build. En una
  /// build que no es de release, coincide con `enableAi` (el proveedor de
  /// depuración no necesita ninguna clave). En release, además exige una
  /// clave de reCAPTCHA Enterprise no vacía: sin ella no hay forma de
  /// activar App Check en producción, así que la IA se oculta en vez de
  /// dejarla fallar (ver `TransactionsScreen` y `docs/security.md`).
  final bool effectiveEnableAi;

  final WebAppCheckProviderChoice webProvider;
  final AndroidAppCheckProviderChoice androidProvider;
}

/// Decide la configuración de App Check. [isRelease] se pasa como
/// parámetro (normalmente `kReleaseMode`) en vez de leerse aquí dentro,
/// para que esta función no dependa de Flutter y se pueda probar con
/// cualquier combinación, incluidas las que no se dan nunca juntas en una
/// build real (como `isRelease: true` en un test).
AppCheckConfig chooseAppCheckConfig({
  required bool enableAi,
  required bool isRelease,
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
    return const AppCheckConfig(
      effectiveEnableAi: true,
      webProvider: WebAppCheckProviderChoice.debug,
      androidProvider: AndroidAppCheckProviderChoice.debug,
    );
  }

  // Release: nunca el proveedor de depuración (ni en web ni en Android).
  final hasSiteKey = recaptchaSiteKey.isNotEmpty;
  return AppCheckConfig(
    effectiveEnableAi: hasSiteKey,
    webProvider: hasSiteKey ? WebAppCheckProviderChoice.recaptchaEnterprise : WebAppCheckProviderChoice.none,
    androidProvider: AndroidAppCheckProviderChoice.productionDefault,
  );
}

/// Configuración de App Check para esta build, calculada una sola vez a
/// partir de las constantes de compilación (`enable_ai.dart`) y de
/// `kReleaseMode`. `main.dart` la usa para decidir qué activar;
/// `effectiveEnableAi` es lo que deben consultar las pantallas para
/// mostrar u ocultar los controles de IA (en vez de `enableAi` a secas).
final appCheckConfig = chooseAppCheckConfig(
  enableAi: enableAi,
  isRelease: kReleaseMode,
  recaptchaSiteKey: recaptchaSiteKey,
);

/// Si la IA debe mostrarse de verdad en esta build (ver
/// [AppCheckConfig.effectiveEnableAi]). Las pantallas importan este
/// símbolo en vez de `enableAi` para decidir si muestran el chat o la
/// entrada en lenguaje natural.
final effectiveEnableAi = appCheckConfig.effectiveEnableAi;

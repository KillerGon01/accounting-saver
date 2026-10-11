import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

import 'enable_ai.dart';

/// Qué proveedor de App Check usar para web, sin depender del SDK de
/// Firebase: un resultado puro que `main.dart` traduce al `WebProvider`
/// concreto (`WebDebugProvider` o `ReCaptchaEnterpriseProvider`).
enum WebAppCheckProviderChoice { none, debug, recaptchaEnterprise }

/// Qué proveedor de App Check usar para Android, igual de puro. No hay un
/// valor de producción: no hay ningún proveedor de App Check de
/// producción configurado para Android (Play Integrity exigiría vincular
/// la app en Play Console, sin hacer, ver docs/security.md), así que un
/// release de Android nunca llega a activar App Check (ver
/// `chooseAppCheckConfig`): `debug` solo se usa en debug/profile.
enum AndroidAppCheckProviderChoice { none, debug }

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
  /// depuración no necesita ninguna clave, en web ni en Android). En
  /// release, solo es verdadero en **web** y con una clave de reCAPTCHA
  /// Enterprise no vacía: no hay ningún proveedor de App Check de
  /// producción para Android (Play Integrity exigiría vincular la app en
  /// Play Console, sin hacer), así que un release de Android oculta la IA
  /// en vez de dejarla fallar con un 403 de App Check (ver
  /// `TransactionsScreen` y `docs/security.md`).
  final bool effectiveEnableAi;

  final WebAppCheckProviderChoice webProvider;
  final AndroidAppCheckProviderChoice androidProvider;
}

/// Decide la configuración de App Check. [isRelease] e [isWeb] se pasan
/// como parámetros (normalmente `kReleaseMode` y `kIsWeb`) en vez de
/// leerse aquí dentro, para que esta función no dependa de Flutter y se
/// pueda probar con cualquier combinación, incluidas las que no se dan
/// nunca juntas en una build real (como `isRelease: true` en un test).
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
    // Debug y profile: proveedor de depuración, en web y en Android por
    // igual, sin necesitar ninguna clave.
    return const AppCheckConfig(
      effectiveEnableAi: true,
      webProvider: WebAppCheckProviderChoice.debug,
      androidProvider: AndroidAppCheckProviderChoice.debug,
    );
  }

  // Release en cualquier plataforma que no sea web: no hay ningún
  // proveedor de App Check de producción para Android, así que la IA se
  // oculta igual que con `enableAi: false`, sin activar App Check.
  if (!isWeb) {
    return const AppCheckConfig(
      effectiveEnableAi: false,
      webProvider: WebAppCheckProviderChoice.none,
      androidProvider: AndroidAppCheckProviderChoice.none,
    );
  }

  // Release en web: nunca el proveedor de depuración; exige una clave de
  // reCAPTCHA Enterprise no vacía, o la IA se oculta en vez de dejarla
  // fallar.
  final hasSiteKey = recaptchaSiteKey.isNotEmpty;
  return AppCheckConfig(
    effectiveEnableAi: hasSiteKey,
    webProvider: hasSiteKey ? WebAppCheckProviderChoice.recaptchaEnterprise : WebAppCheckProviderChoice.none,
    androidProvider: AndroidAppCheckProviderChoice.none,
  );
}

/// Configuración de App Check para esta build, calculada una sola vez a
/// partir de las constantes de compilación (`enable_ai.dart`), de
/// `kReleaseMode` y de `kIsWeb`. `main.dart` la usa para decidir qué
/// activar; `effectiveEnableAi` es lo que deben consultar las pantallas
/// para mostrar u ocultar los controles de IA (en vez de `enableAi` a
/// secas).
final appCheckConfig = chooseAppCheckConfig(
  enableAi: enableAi,
  isRelease: kReleaseMode,
  isWeb: kIsWeb,
  recaptchaSiteKey: recaptchaSiteKey,
);

/// Si la IA debe mostrarse de verdad en esta build (ver
/// [AppCheckConfig.effectiveEnableAi]). Las pantallas importan este
/// símbolo en vez de `enableAi` para decidir si muestran el chat o la
/// entrada en lenguaje natural.
final effectiveEnableAi = appCheckConfig.effectiveEnableAi;

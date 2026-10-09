import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_check_config.dart';
import 'enable_ai.dart';
import 'firebase_options.dart';
import 'presentation/auth/auth_providers.dart';
import 'presentation/auth/login_screen.dart';
import 'presentation/auth/verify_email_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/transactions/transactions_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Solo se activa App Check si la IA es realmente usable en esta build
  // (`effectiveEnableAi`, calculado en `app_check_config.dart`): con
  // ENABLE_AI=false no hace falta, y en release sin clave de reCAPTCHA
  // tampoco (la IA se oculta igual, ver `TransactionsScreen`), así que
  // activar App Check no serviría de nada.
  if (appCheckConfig.effectiveEnableAi) {
    final webProvider = switch (appCheckConfig.webProvider) {
      // Depuración: solo en builds que no son de release (ver
      // AppCheckConfig). El token se genera en el dispositivo y hay que
      // registrarlo a mano en la consola de Firebase; ver
      // docs/security.md.
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
      // Release: nunca el proveedor de depuración en Android. No se pasa
      // `providerAndroid`, así que el SDK usa su propio valor por defecto
      // (`AndroidPlayIntegrityProvider`) en vez de construirlo aquí a
      // mano; Play Integrity no está configurado ni probado en la consola
      // de Firebase ni en Play Console (ver docs/security.md), así que
      // esto sigue siendo un pendiente, no una implementación terminada.
      await FirebaseAppCheck.instance.activate(providerWeb: webProvider);
    }
    // Canjea el token de App Check ya, en segundo plano, para que la
    // primera vez que alguien use la entrada en lenguaje natural no pague
    // también ese canje (no gasta cuota de Gemini: solo habla con App
    // Check). Si falla, no pasa nada: se reintentará en la primera llamada.
    unawaited(FirebaseAppCheck.instance.getToken().catchError((_) => null));
  }
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accounting Saver',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const LoginScreen();
        if (user.needsEmailVerification) return VerifyEmailScreen(user: user);
        return TransactionsScreen(userId: user.uid);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        body: Center(child: Text('Error de autenticación: $error')),
      ),
    );
  }
}

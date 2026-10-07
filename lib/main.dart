import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  if (enableAi) {
    // Gemini (Firebase AI Logic) exige App Check. Solo activamos el
    // proveedor de depuración, para desarrollo local: nada de reCAPTCHA ni
    // de claves de producción. El token se genera en el dispositivo y hay
    // que registrarlo a mano en la consola de Firebase; ver docs/security.md.
    await FirebaseAppCheck.instance.activate(
      providerWeb: WebDebugProvider(),
      providerAndroid: const AndroidDebugProvider(),
    );
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

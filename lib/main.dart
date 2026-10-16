import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_check_bootstrap.dart';
import 'firebase_options.dart';
import 'presentation/auth/auth_providers.dart';
import 'presentation/auth/login_screen.dart';
import 'presentation/auth/verify_email_screen.dart';
import 'presentation/common/app_localization.dart';
import 'presentation/common/motion.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/transactions/transactions_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await activateAppCheckIfNeeded();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accounting Saver',
      // Tema oscuro forzado a propósito (ver docs/design.md, "Tema
      // oscuro"): `AppTheme.light()` se conserva pero ningún `MaterialApp`
      // de la app lo usa.
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      // Widgets de Material en español, igual de forzado que el tema
      // oscuro (ver docs/design.md, "Localización de Material (es-ES)").
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    // `ValueKey` por rama: sin una key propia, `AnimatedSwitcher` no
    // detecta el cambio de pantalla (login/verificación/movimientos) y
    // no anima nada. Puramente visual: la pantalla que se construye en
    // cada rama es exactamente la misma de antes.
    final child = authState.when(
      data: (user) {
        if (user == null) return const LoginScreen(key: ValueKey('login'));
        if (user.needsEmailVerification) {
          return VerifyEmailScreen(key: const ValueKey('verify'), user: user);
        }
        return TransactionsScreen(key: const ValueKey('transactions'), userId: user.uid);
      },
      loading: () => const Scaffold(
        key: ValueKey('loading'),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        key: const ValueKey('error'),
        body: Center(child: Text('Error de autenticación: $error')),
      ),
    );

    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.base),
      child: child,
    );
  }
}

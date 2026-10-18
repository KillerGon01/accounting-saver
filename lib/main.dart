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
      // Dark theme forced on purpose (see docs/design.md, "Tema
      // oscuro"): `AppTheme.light()` is kept but no `MaterialApp` in
      // the app uses it.
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      // Material widgets in Spanish, just as forced as the dark
      // theme (see docs/design.md, "Localización de Material (es-ES)").
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

    // `ValueKey` per branch: without its own key, `AnimatedSwitcher`
    // doesn't detect the screen change (login/verification/transactions)
    // and animates nothing. Purely visual: the screen built in each
    // branch is exactly the same as before.
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

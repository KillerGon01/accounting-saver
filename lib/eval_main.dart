// Herramienta de evaluación local de la calidad del chat con Gemini real
// (ver docs/evaluation.md). NO es parte de la app: no se publica, no se
// incluye en ningún build de producción ni en el Dockerfile, y no la
// ejecuta ni `flutter test` ni el CI (`.github/workflows/ci.yml`) — solo
// se compila si se la pasa explícitamente a `flutter run -t`:
//
//   flutter run -t lib/eval_main.dart -d chrome --web-port=5000 \
//     --dart-define=ENABLE_AI=true \
//     --dart-define=EVAL_ACCOUNT_EMAIL=<correo-de-la-cuenta-de-evaluación>
//
// --web-port=5000 porque la clave de navegador de Firebase solo admite
// ese puerto en local (ver docs/security.md). El correo de la cuenta de
// evaluación nunca se escribe en el código ni en los docs: solo se pasa
// en este --dart-define, y esta herramienta se niega a borrar o escribir
// nada si el correo de la sesión no coincide exactamente con él (ver
// `lib/eval/eval_runner.dart`).
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_check_bootstrap.dart';
import 'domain/auth/app_user.dart';
import 'eval/eval_runner.dart';
import 'firebase_options.dart';
import 'presentation/auth/auth_providers.dart';
import 'presentation/auth/login_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/transactions/transaction_providers.dart';

/// Correo de la única cuenta sobre la que esta herramienta puede borrar o
/// escribir algo. Vacío por defecto: sin `--dart-define=EVAL_ACCOUNT_EMAIL`
/// no hay ninguna cuenta válida, nunca "la que esté disponible".
const _evalAccountEmail = String.fromEnvironment('EVAL_ACCOUNT_EMAIL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await activateAppCheckIfNeeded();
  runApp(const ProviderScope(child: _EvalApp()));
}

class _EvalApp extends StatelessWidget {
  const _EvalApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evaluación del chat (local)',
      theme: AppTheme.light(),
      home: const _EvalGate(),
    );
  }
}

class _EvalGate extends ConsumerWidget {
  const _EvalGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const LoginScreen();
        return _EvalRunnerScreen(user: user);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Error de autenticación: $error'))),
    );
  }
}

/// Pantalla de la herramienta, solo tras iniciar sesión. Si el correo no
/// es exactamente [_evalAccountEmail], no deja pulsar "Ejecutar
/// evaluación": el botón ni siquiera se activa, para que la comprobación
/// de la cuenta sea visible antes de intentar nada (la comprobación real
/// e innegociable está en `runEval`, por si esta pantalla cambiara).
class _EvalRunnerScreen extends ConsumerStatefulWidget {
  const _EvalRunnerScreen({required this.user});

  final AppUser user;

  @override
  ConsumerState<_EvalRunnerScreen> createState() => _EvalRunnerScreenState();
}

class _EvalRunnerScreenState extends ConsumerState<_EvalRunnerScreen> {
  final _log = StringBuffer();
  final _filterController = TextEditingController();
  String? _report;
  bool _isRunning = false;

  bool get _accountMatches =>
      _evalAccountEmail.isNotEmpty && widget.user.email == _evalAccountEmail;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _isRunning = true;
      _log.clear();
      _report = null;
    });

    void onProgress(String message) {
      // ignore: avoid_print
      print('[eval] $message');
      setState(() => _log.writeln(message));
    }

    final filterText = _filterController.text.trim();
    final filter = filterText.isEmpty
        ? null
        : filterText.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

    try {
      final report = await runEval(
        repository: ref.read(transactionRepositoryProvider),
        userId: widget.user.uid,
        sessionEmail: widget.user.email,
        expectedEmail: _evalAccountEmail,
        caseFilter: filter,
        onProgress: onProgress,
      );
      // ignore: avoid_print
      print(report);
      setState(() => _report = report);
    } catch (error) {
      onProgress('Error: $error');
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(signOutProvider)();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Evaluación del chat (local, no se despliega)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sesión: ${widget.user.email ?? '(sin correo)'}'),
            const SizedBox(height: 8),
            if (_evalAccountEmail.isEmpty)
              const Text(
                'Falta --dart-define=EVAL_ACCOUNT_EMAIL=<correo>. Sin él, no se '
                'puede ejecutar nada.',
                style: TextStyle(color: Colors.red),
              )
            else if (!_accountMatches)
              Text(
                'Esta no es la cuenta de evaluación. Cierra sesión y entra con la '
                'cuenta cuyo correo coincide con EVAL_ACCOUNT_EMAIL.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else
              const Text('Cuenta verificada: coincide con EVAL_ACCOUNT_EMAIL.'),
            const SizedBox(height: 16),
            TextField(
              controller: _filterController,
              enabled: !_isRunning,
              decoration: const InputDecoration(
                labelText: 'Solo estos casos (opcional)',
                hintText: 'ids y/o tipos separados por comas, p. ej. escritura, cifra-01',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  onPressed: (_accountMatches && !_isRunning) ? _run : null,
                  child: Text(_isRunning ? 'Ejecutando...' : 'Ejecutar evaluación'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _isRunning ? null : _signOut, child: const Text('Cerrar sesión')),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Progreso:'),
            Expanded(
              flex: 1,
              child: SingleChildScrollView(
                child: SelectableText(_log.toString()),
              ),
            ),
            if (_report != null) ...[
              const Divider(),
              const Text('Informe (cópialo en docs/evaluation.md; también se ha impreso en consola):'),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: SelectableText(_report!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

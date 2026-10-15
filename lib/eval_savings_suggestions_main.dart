// Herramienta de evaluación local de la calidad de la redacción con IA de
// las sugerencias de ahorro (ver docs/evaluation.md, "Sugerencias de
// ahorro con IA"). NO es parte de la app: no se publica, no se incluye en
// ningún build de producción ni en el Dockerfile, y no la ejecuta ni
// `flutter test` ni el CI — solo se compila si se la pasa explícitamente
// a `flutter run -t`:
//
//   flutter run -t lib/eval_savings_suggestions_main.dart -d chrome \
//     --web-port=5000 --dart-define=ENABLE_AI=true
//
// --web-port=5000 por el mismo motivo que `eval_main.dart` (la clave de
// navegador de Firebase solo admite ese puerto en local, ver
// docs/security.md).
//
// A diferencia de `eval_main.dart` (chat), esta herramienta **no pide
// iniciar sesión y no toca Firestore en ningún momento**:
// `GeminiSavingsSuggestionsGateway` es una sola llamada sobre un resumen
// ya construido en memoria (`SavingsSuggestionsSummary`), sin ninguna
// cuenta ni ningún movimiento de por medio — así que no hay nada que
// verificar ni que borrar/sembrar antes de ejecutar.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_check_bootstrap.dart';
import 'eval/eval_runner.dart' show EvalCaseFilterError;
import 'eval/savings_suggestions_eval_runner.dart';
import 'firebase_options.dart';
import 'infrastructure/common/gemini_model_fallback.dart';
import 'infrastructure/savings/gemini_savings_suggestions_gateway.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await activateAppCheckIfNeeded();
  runApp(const _EvalApp());
}

class _EvalApp extends StatelessWidget {
  const _EvalApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evaluación de sugerencias de ahorro (local)',
      theme: AppTheme.light(),
      home: const _EvalRunnerScreen(),
    );
  }
}

class _EvalRunnerScreen extends StatefulWidget {
  const _EvalRunnerScreen();

  @override
  State<_EvalRunnerScreen> createState() => _EvalRunnerScreenState();
}

class _EvalRunnerScreenState extends State<_EvalRunnerScreen> {
  final _log = StringBuffer();
  final _filterController = TextEditingController();
  String? _report;
  bool _isRunning = false;

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
      final gateway = GeminiSavingsSuggestionsGateway(availability: GeminiModelAvailability());
      final report = await runSavingsSuggestionsEval(
        gateway: gateway,
        caseFilter: filter,
        onProgress: onProgress,
      );
      // ignore: avoid_print
      print(report);
      setState(() => _report = report);
    } on EvalCaseFilterError catch (error) {
      // Mismo tratamiento que `eval_main.dart` ante un filtro mal escrito:
      // mensaje claro (`EvalCaseFilterError.toString()` ya es texto en
      // español listo para mostrarse), sin haber llamado a Gemini.
      onProgress('Error: $error');
    } catch (error) {
      onProgress('Error: $error');
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Evaluación de sugerencias de ahorro (local, no se despliega)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'No pide iniciar sesión ni toca Firestore: evalúa el gateway de Gemini '
              'directamente sobre resúmenes ya construidos en memoria.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _filterController,
              enabled: !_isRunning,
              decoration: const InputDecoration(
                labelText: 'Solo estos casos (opcional)',
                hintText: 'ids separados por comas, p. ej. savings-a-parcial-exigente',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isRunning ? null : _run,
              child: Text(_isRunning ? 'Ejecutando...' : 'Ejecutar evaluación'),
            ),
            const SizedBox(height: 16),
            const Text('Progreso:'),
            Expanded(
              flex: 1,
              child: SingleChildScrollView(child: SelectableText(_log.toString())),
            ),
            if (_report != null) ...[
              const Divider(),
              const Text('Informe (cópialo en docs/evaluation.md; también se ha impreso en consola):'),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(child: SelectableText(_report!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

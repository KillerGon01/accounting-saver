// Local tool for evaluating the quality of the AI write-up of
// savings suggestions (see docs/evaluation.md, "Sugerencias de
// ahorro con IA"). NOT part of the app: it isn't published, isn't
// included in any production build or in the Dockerfile, and
// neither `flutter test` nor the CI run it — it only compiles if
// explicitly passed to `flutter run -t`:
//
//   flutter run -t lib/eval_savings_suggestions_main.dart -d chrome \
//     --web-port=5000 --dart-define=ENABLE_AI=true
//
// --web-port=5000 for the same reason as `eval_main.dart` (Firebase's
// browser key only allows that port locally, see docs/security.md).
//
// Unlike `eval_main.dart` (chat), this tool **doesn't ask to sign in
// and never touches Firestore**: `GeminiSavingsSuggestionsGateway` is
// a single call over a summary already built in memory
// (`SavingsSuggestionsSummary`), with no account or transaction
// involved — so there's nothing to check or delete/seed before
// running.
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
      // Same handling as `eval_main.dart` for a badly-written
      // filter: a clear message (`EvalCaseFilterError.toString()` is
      // already Spanish-language text ready to display), without
      // having called Gemini.
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

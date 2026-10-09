import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/common/transactions_change_notifier.dart';
import '../../infrastructure/common/gemini_model_fallback.dart';

/// Una sola instancia por app, compartida entre el chat y la entrada en
/// lenguaje natural: las dos gastan la misma cuota diaria de Gemini, así
/// que deben recordar juntas qué modelo está agotado.
final geminiModelAvailabilityProvider = Provider<GeminiModelAvailability>(
  (ref) => GeminiModelAvailability(),
);

/// Una sola instancia por app: el chat la consulta para saber si su caché
/// en memoria sigue siendo válida, y los casos de uso de movimientos la
/// avisan cuando crean, editan o borran uno.
final transactionsChangeNotifierProvider = Provider<TransactionsChangeNotifier>(
  (ref) => TransactionsChangeNotifier(),
);

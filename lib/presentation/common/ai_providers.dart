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

/// Versión actual de los movimientos (`TransactionsChangeNotifier.version`),
/// pero como estado observable de Riverpod: a diferencia de
/// `transactionsChangeNotifierProvider` (una instancia fija, que solo se
/// puede *consultar* más tarde, como hace `SendChatMessage`), observar
/// este provider con `ref.watch` fuerza a recalcular a quien dependa de
/// él en cuanto cambien los movimientos — por ejemplo,
/// `monthlyReportProvider`, para que el resumen mensual se actualice sin
/// recargar la pantalla al crear, editar o borrar un movimiento, o al
/// cargar o borrar los datos de ejemplo.
final transactionsVersionProvider = NotifierProvider<TransactionsVersionNotifier, int>(
  TransactionsVersionNotifier.new,
);

class TransactionsVersionNotifier extends Notifier<int> {
  @override
  int build() {
    final changeNotifier = ref.watch(transactionsChangeNotifierProvider);
    void listener() => state = changeNotifier.version;
    changeNotifier.addListener(listener);
    ref.onDispose(() => changeNotifier.removeListener(listener));
    return changeNotifier.version;
  }
}

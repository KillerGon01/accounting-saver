import 'activity_summary.dart';
import 'transaction.dart';

abstract class TransactionRepository {
  Stream<List<Transaction>> watchByMonth({
    required String userId,
    required int year,
    required int month,
  });

  String newId({required String userId});

  Future<void> add({required String userId, required Transaction transaction});

  Future<void> addAll({
    required String userId,
    required List<Transaction> transactions,
  });

  Future<bool> hasDemoData({required String userId});

  Future<void> update({
    required String userId,
    required Transaction transaction,
  });

  Future<void> delete({required String userId, required String transactionId});

  /// Resumen de todo el histórico. Las implementaciones deben calcularlo sin
  /// descargar todos los movimientos.
  Future<ActivitySummary> getActivitySummary({required String userId});

  /// Movimientos entre [start] (incluido) y [end] (excluido), ordenados por
  /// fecha descendente y limitados a [limit] resultados.
  ///
  /// Las implementaciones solo filtran por este rango de fechas en el
  /// servidor (y ordenan por esa misma fecha); no añaden ningún otro `where`
  /// (ni por importe, ni por categoría, ni por nada más), para no depender
  /// de índices compuestos de Firestore. Cualquier otro filtrado —
  /// categoría, signo del importe, sumas, etc.— lo hace quien llama, en
  /// código, sobre la lista ya descargada.
  ///
  /// Quien llama decide [limit] según lo que necesite: un tope de seguridad
  /// alto para calcular sumas sobre (casi) todo el rango, o un número
  /// pequeño si solo quiere detectar que hay más resultados de los que
  /// quiere mostrar pidiendo uno de más.
  Future<List<Transaction>> findByDateRange({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int limit,
  });
}

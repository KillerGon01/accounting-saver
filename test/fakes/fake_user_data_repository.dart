import 'package:accounting_saver/domain/user_data/user_data_repository.dart';

import 'fake_savings_goal_repository.dart';
import 'fake_transaction_repository.dart';

/// Borra los movimientos (y, si se pasa [goals], las metas de ahorro) del
/// usuario en lotes, como el repositorio real (`FirestoreUserDataRepository`,
/// que recorre `userDataCollections` — ver ese test de que la lista
/// incluye `'goals'`). Puede fallar a mitad para probar el reintento.
class FakeUserDataRepository implements UserDataRepository {
  FakeUserDataRepository(this.transactions, {this.goals, this.batchSize = 2});

  final FakeTransactionRepository transactions;

  /// `null` en los tests que no necesitan metas (todo el comportamiento
  /// de siempre, sin tocarlo): sin repositorio de metas, no hay nada que
  /// borrar de esa colección.
  final FakeSavingsGoalRepository? goals;
  final int batchSize;

  /// Si se asigna N, la operación falla justo antes del lote N+1, una sola vez.
  /// Con N = 0 falla antes del primer lote.
  int? failBeforeBatch;

  int deletedBatches = 0;

  @override
  Future<void> deleteAllForUser({required String userId}) async {
    await _deleteInBatches(() => transactions.transactionsOf(userId).map((t) => t.id).toList(), (
      id,
    ) => transactions.delete(userId: userId, transactionId: id));

    final goalsRepository = goals;
    if (goalsRepository != null) {
      await _deleteInBatches(() => goalsRepository.goalsOf(userId).map((g) => g.id).toList(), (
        id,
      ) => goalsRepository.delete(userId: userId, goalId: id));
    }
  }

  Future<void> _deleteInBatches(List<String> Function() pendingIds, Future<void> Function(String id) deleteOne) async {
    while (true) {
      final batch = pendingIds().take(batchSize).toList();
      if (batch.isEmpty) return;

      final failAt = failBeforeBatch;
      if (failAt != null) {
        if (failAt == 0) {
          failBeforeBatch = null;
          throw StateError('fallo de red simulado');
        }
        failBeforeBatch = failAt - 1;
      }

      for (final id in batch) {
        await deleteOne(id);
      }
      deletedBatches++;
    }
  }
}

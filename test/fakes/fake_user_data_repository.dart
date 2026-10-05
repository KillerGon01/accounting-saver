import 'package:accounting_saver/domain/user_data/user_data_repository.dart';

import 'fake_transaction_repository.dart';

/// Borra los movimientos del usuario en lotes, como el repositorio real.
/// Puede fallar a mitad para probar el reintento.
class FakeUserDataRepository implements UserDataRepository {
  FakeUserDataRepository(this.transactions, {this.batchSize = 2});

  final FakeTransactionRepository transactions;
  final int batchSize;

  /// Si se asigna N, la operación falla justo antes del lote N+1, una sola vez.
  /// Con N = 0 falla antes del primer lote.
  int? failBeforeBatch;

  int deletedBatches = 0;

  @override
  Future<void> deleteAllForUser({required String userId}) async {
    while (true) {
      final batch = transactions.transactionsOf(userId).take(batchSize).toList();
      if (batch.isEmpty) return;

      final failAt = failBeforeBatch;
      if (failAt != null) {
        if (failAt == 0) {
          failBeforeBatch = null;
          throw StateError('fallo de red simulado');
        }
        failBeforeBatch = failAt - 1;
      }

      for (final transaction in batch) {
        await transactions.delete(userId: userId, transactionId: transaction.id);
      }
      deletedBatches++;
    }
  }
}

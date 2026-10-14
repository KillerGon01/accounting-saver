import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/savings/create_savings_goal.dart';
import '../../application/savings/delete_savings_goal.dart';
import '../../application/savings/list_savings_goals.dart';
import '../../application/savings/update_saved_amount.dart';
import '../../application/savings/update_savings_goal.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';
import '../../infrastructure/savings/firestore_savings_goal_repository.dart';

final savingsGoalRepositoryProvider = Provider<SavingsGoalRepository>((ref) {
  return FirestoreSavingsGoalRepository();
});

final listSavingsGoalsProvider = Provider<ListSavingsGoals>(
  (ref) => ListSavingsGoals(ref.watch(savingsGoalRepositoryProvider)),
);

final createSavingsGoalProvider = Provider<CreateSavingsGoal>(
  (ref) => CreateSavingsGoal(ref.watch(savingsGoalRepositoryProvider)),
);

final updateSavingsGoalProvider = Provider<UpdateSavingsGoal>(
  (ref) => UpdateSavingsGoal(ref.watch(savingsGoalRepositoryProvider)),
);

final updateSavedAmountProvider = Provider<UpdateSavedAmount>(
  (ref) => UpdateSavedAmount(ref.watch(savingsGoalRepositoryProvider)),
);

final deleteSavingsGoalProvider = Provider<DeleteSavingsGoal>(
  (ref) => DeleteSavingsGoal(ref.watch(savingsGoalRepositoryProvider)),
);

/// En tiempo real (ver `SavingsGoalRepository.watchAll`): se actualiza
/// sola al crear, editar o borrar una meta, sin necesitar invalidarla a
/// mano. `Provider.family` por `userId`, igual que el resto de providers
/// de datos del usuario: aislamiento automático al cambiar de cuenta.
final savingsGoalsStreamProvider = StreamProvider.family<List<SavingsGoal>, String>((ref, userId) {
  return ref.watch(listSavingsGoalsProvider)(userId: userId);
});

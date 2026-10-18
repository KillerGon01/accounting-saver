import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/savings/build_savings_suggestions.dart';
import '../../application/savings/create_savings_goal.dart';
import '../../application/savings/delete_savings_goal.dart';
import '../../application/savings/explain_savings_suggestions.dart';
import '../../application/savings/list_savings_goals.dart';
import '../../application/savings/update_saved_amount.dart';
import '../../application/savings/update_savings_goal.dart';
import '../../domain/savings/savings_goal.dart';
import '../../domain/savings/savings_goal_repository.dart';
import '../../domain/savings/savings_suggestions_gateway.dart';
import '../../infrastructure/savings/firestore_savings_goal_repository.dart';
import '../../infrastructure/savings/gemini_savings_suggestions_gateway.dart';
import '../common/ai_providers.dart';
import '../transactions/transaction_providers.dart';

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

/// Called on demand, when pressing "¿De dónde puedo ahorrar?" (see
/// `BuildSavingsSuggestions`): no provider keeps its result cached or
/// recomputes it on its own, unlike `savingsGoalsStreamProvider`.
final buildSavingsSuggestionsProvider = Provider<BuildSavingsSuggestions>(
  (ref) => BuildSavingsSuggestions(ref.watch(transactionRepositoryProvider)),
);

final geminiSavingsSuggestionsGatewayProvider = Provider<SavingsSuggestionsGateway>(
  (ref) => GeminiSavingsSuggestionsGateway(availability: ref.watch(geminiModelAvailabilityProvider)),
);

/// One instance per user (a family by `userId`), same as
/// `explainMonthlyReportProvider`: its own cache and its own cap of 6
/// write-ups per session, isolated between one user and another.
final explainSavingsSuggestionsProvider = Provider.family<ExplainSavingsSuggestions, String>((ref, userId) {
  return ExplainSavingsSuggestions(
    ref.watch(geminiSavingsSuggestionsGatewayProvider),
    ref.watch(transactionsChangeNotifierProvider),
  );
});

/// In real time (see `SavingsGoalRepository.watchAll`): updates on
/// its own when a goal is created, edited, or deleted, with no need
/// to invalidate it by hand. `Provider.family` by `userId`, same as
/// the rest of the user's data providers: automatic isolation when
/// switching accounts.
final savingsGoalsStreamProvider = StreamProvider.family<List<SavingsGoal>, String>((ref, userId) {
  return ref.watch(listSavingsGoalsProvider)(userId: userId);
});

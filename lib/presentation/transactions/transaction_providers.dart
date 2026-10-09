import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/transactions/add_transaction.dart';
import '../../application/transactions/delete_transaction.dart';
import '../../application/transactions/load_demo_data.dart';
import '../../application/transactions/parse_natural_language_transaction.dart';
import '../../application/transactions/update_transaction.dart';
import '../../application/transactions/watch_monthly_transactions.dart';
import '../../domain/transactions/llm_gateway.dart';
import '../../domain/transactions/transaction.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../../infrastructure/transactions/firestore_transaction_repository.dart';
import '../../infrastructure/transactions/gemini_llm_gateway.dart';
import '../common/ai_providers.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return FirestoreTransactionRepository();
});

final llmGatewayProvider = Provider<LlmGateway>(
  (ref) => GeminiLlmGateway(availability: ref.watch(geminiModelAvailabilityProvider)),
);

final parseNaturalLanguageTransactionProvider = Provider<ParseNaturalLanguageTransaction>(
  (ref) => ParseNaturalLanguageTransaction(ref.watch(llmGatewayProvider)),
);

final addTransactionProvider = Provider<AddTransaction>(
  (ref) => AddTransaction(
    ref.watch(transactionRepositoryProvider),
    ref.watch(transactionsChangeNotifierProvider),
  ),
);

final updateTransactionProvider = Provider<UpdateTransaction>(
  (ref) => UpdateTransaction(
    ref.watch(transactionRepositoryProvider),
    ref.watch(transactionsChangeNotifierProvider),
  ),
);

final deleteTransactionProvider = Provider<DeleteTransaction>(
  (ref) => DeleteTransaction(
    ref.watch(transactionRepositoryProvider),
    ref.watch(transactionsChangeNotifierProvider),
  ),
);

final watchMonthlyTransactionsProvider = Provider<WatchMonthlyTransactions>(
  (ref) => WatchMonthlyTransactions(ref.watch(transactionRepositoryProvider)),
);

final loadDemoDataProvider = Provider<LoadDemoData>(
  (ref) => LoadDemoData(
    ref.watch(transactionRepositoryProvider),
    ref.watch(transactionsChangeNotifierProvider),
  ),
);

class MonthlyTransactionsParams {
  const MonthlyTransactionsParams({
    required this.userId,
    required this.year,
    required this.month,
  });

  final String userId;
  final int year;
  final int month;

  @override
  bool operator ==(Object other) {
    return other is MonthlyTransactionsParams &&
        other.userId == userId &&
        other.year == year &&
        other.month == month;
  }

  @override
  int get hashCode => Object.hash(userId, year, month);
}

final monthlyTransactionsStreamProvider = StreamProvider.family<
  List<Transaction>,
  MonthlyTransactionsParams
>((ref, params) {
  return ref.watch(watchMonthlyTransactionsProvider)(
    userId: params.userId,
    year: params.year,
    month: params.month,
  );
});

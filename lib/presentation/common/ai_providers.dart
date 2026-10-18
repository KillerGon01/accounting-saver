import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/common/transactions_change_notifier.dart';
import '../../infrastructure/common/gemini_model_fallback.dart';

/// A single instance per app, shared between the chat and natural
/// language input: both spend Gemini's same daily quota, so they
/// must remember together which model is exhausted.
final geminiModelAvailabilityProvider = Provider<GeminiModelAvailability>(
  (ref) => GeminiModelAvailability(),
);

/// A single instance per app: the chat checks it to know whether its
/// in-memory cache is still valid, and the transaction use cases
/// notify it when they create, edit, or delete one.
final transactionsChangeNotifierProvider = Provider<TransactionsChangeNotifier>(
  (ref) => TransactionsChangeNotifier(),
);

/// Current version of the transactions (`TransactionsChangeNotifier.version`),
/// but as observable Riverpod state: unlike
/// `transactionsChangeNotifierProvider` (a fixed instance, which can
/// only be *checked* later, as `SendChatMessage` does), watching this
/// provider with `ref.watch` forces whoever depends on it to
/// recompute as soon as the transactions change — for example,
/// `monthlyReportProvider`, so the monthly report updates without
/// reloading the screen when a transaction is created, edited, or
/// deleted, or when the demo data is loaded or deleted.
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

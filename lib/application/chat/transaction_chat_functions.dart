import '../../domain/chat/chat_functions.dart';
import '../../domain/transactions/transaction_repository.dart';
import '../reports/build_monthly_report.dart';
import 'functions/breakdown_functions.dart';
import 'functions/comparison_functions.dart';
import 'functions/listing_functions.dart';
import 'functions/shared.dart';

/// Runs, after validating, the functions the chat can request over a
/// user's transactions. The arguments come from the model and aren't
/// trustworthy: each one is validated before touching Firestore and,
/// if one is invalid, no query runs and `{'error': ...}` is returned
/// so the model itself can explain it to the user, instead of
/// throwing.
///
/// A thin facade: each group of functions lives in its own class
/// under `functions/` (`ListingFunctions`, `BreakdownFunctions`,
/// `ComparisonFunctions`, plus the helpers shared between them in
/// `functions/shared.dart`), split by responsibility so no single
/// file grows too large. This class keeps the same public API
/// (`execute` and the static limits below) so callers, tests and the
/// evaluation harness don't need to change.
class TransactionChatFunctions {
  /// [buildMonthlyReport] is optional only so as not to force every
  /// test that doesn't need one to build one; in the app, the same
  /// `BuildMonthlyReport` the monthly report already uses is always
  /// passed (see `chat_providers.dart`), so `getCategoryBreakdown` and
  /// `compareMonths` are, byte for byte, the same source of truth as
  /// the report screen (see docs/design.md: the chat used to improvise
  /// its own per-category calculation from `listTransactions`, which
  /// produced figures different from the report's). The same instance
  /// is shared by `BreakdownFunctions` and `ComparisonFunctions`.
  TransactionChatFunctions(TransactionRepository repository, [BuildMonthlyReport? buildMonthlyReport])
    : this._internal(repository, buildMonthlyReport ?? BuildMonthlyReport(repository));

  TransactionChatFunctions._internal(TransactionRepository repository, BuildMonthlyReport buildMonthlyReport)
    : _listing = ListingFunctions(repository),
      _breakdown = BreakdownFunctions(repository, buildMonthlyReport),
      _comparison = ComparisonFunctions(buildMonthlyReport);

  static const maxResults = ChatFunctionLimits.maxResults;
  static const maxRangeYears = ChatFunctionLimits.maxRangeYears;
  static const maxFetchLimit = ChatFunctionLimits.maxFetchLimit;
  static const recurringExpensesMonths = ChatFunctionLimits.recurringExpensesMonths;

  final ListingFunctions _listing;
  final BreakdownFunctions _breakdown;
  final ComparisonFunctions _comparison;

  Future<Map<String, Object?>> execute({
    required String userId,
    required String name,
    required Map<String, Object?> arguments,
    required DateTime now,
  }) async {
    switch (name) {
      case ChatFunctions.getMonthlySummary:
        return _breakdown.getMonthlySummary(userId: userId, arguments: arguments, now: now);
      case ChatFunctions.listTransactions:
        return _listing.listTransactions(userId: userId, arguments: arguments);
      case ChatFunctions.recurringExpenses:
        return _breakdown.recurringExpenses(userId: userId, now: now);
      case ChatFunctions.getCategoryBreakdown:
        return _breakdown.getCategoryBreakdown(userId: userId, arguments: arguments, now: now);
      case ChatFunctions.compareMonths:
        return _comparison.compareMonths(userId: userId, arguments: arguments, now: now);
      default:
        return {'error': 'Función desconocida: "$name".'};
    }
  }
}

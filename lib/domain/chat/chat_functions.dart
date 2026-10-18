/// Names of the functions the chat can ask to run over the user's
/// transactions. Shared between the functions' declaration to the model
/// (infrastructure) and their validated execution (application), so
/// they can never drift apart.
abstract final class ChatFunctions {
  static const getMonthlySummary = 'getMonthlySummary';
  static const listTransactions = 'listTransactions';
  static const recurringExpenses = 'recurringExpenses';
  static const getCategoryBreakdown = 'getCategoryBreakdown';
  static const compareMonths = 'compareMonths';
}

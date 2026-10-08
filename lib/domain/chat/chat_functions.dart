/// Nombres de las funciones que el chat puede pedir ejecutar sobre los
/// movimientos del usuario. Compartidos entre la declaración de las
/// funciones ante el modelo (infraestructura) y su ejecución validada
/// (aplicación), para que no se puedan desincronizar.
abstract final class ChatFunctions {
  static const getMonthlySummary = 'getMonthlySummary';
  static const listTransactions = 'listTransactions';
  static const recurringExpenses = 'recurringExpenses';
}

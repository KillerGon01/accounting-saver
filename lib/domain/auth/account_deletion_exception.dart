/// Etapa del borrado de cuenta en la que falló. Permite explicar al usuario
/// qué ha quedado hecho y que basta con reintentar.
enum AccountDeletionStage {
  /// Falló el borrado de movimientos. La cuenta sigue intacta.
  userData,

  /// Los movimientos ya se borraron, pero la cuenta de Auth no.
  account,
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.stage, this.cause);

  final AccountDeletionStage stage;
  final Object cause;

  @override
  String toString() => 'AccountDeletionException(${stage.name}): $cause';
}

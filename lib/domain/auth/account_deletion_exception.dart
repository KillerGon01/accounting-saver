/// Stage of account deletion where it failed. Lets the user be told
/// what has already been done and that retrying is enough.
enum AccountDeletionStage {
  /// Deleting the transactions failed. The account is still intact.
  userData,

  /// The transactions were already deleted, but the Auth account wasn't.
  account,
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.stage, this.cause);

  final AccountDeletionStage stage;
  final Object cause;

  @override
  String toString() => 'AccountDeletionException(${stage.name}): $cause';
}

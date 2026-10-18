import '../../domain/auth/account_deletion_exception.dart';
import '../auth/auth_error_messages.dart';

/// Message for an account deletion failure. When the stage is known,
/// it says what has already been done so the user knows they can
/// retry.
String accountDeletionErrorMessage(Object error) {
  if (error is AccountDeletionException) {
    return switch (error.stage) {
      AccountDeletionStage.userData =>
        'No se pudieron borrar todos tus movimientos, así que la cuenta no se ha borrado. Puedes volver a intentarlo.',
      AccountDeletionStage.account =>
        'Tus movimientos se han borrado, pero la cuenta no. Vuelve a intentarlo para terminar.',
    };
  }
  return authErrorMessage(error);
}

import '../../domain/auth/account_deletion_exception.dart';
import '../auth/auth_error_messages.dart';

/// Mensaje para un fallo del borrado de cuenta. Cuando la etapa es conocida,
/// dice qué ha quedado hecho para que el usuario sepa que puede reintentar.
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

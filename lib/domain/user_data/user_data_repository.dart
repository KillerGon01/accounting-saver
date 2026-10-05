/// Borra los datos del usuario en almacenamiento. No borra la cuenta de
/// autenticación: eso lo hace `AuthRepository.deleteAccount`.
abstract class UserDataRepository {
  /// Idempotente: si se interrumpe, volver a llamarlo termina el borrado.
  Future<void> deleteAllForUser({required String userId});
}

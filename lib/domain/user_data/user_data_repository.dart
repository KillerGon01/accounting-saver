/// Deletes the user's data in storage. Doesn't delete the
/// authentication account: `AuthRepository.deleteAccount` does that.
abstract class UserDataRepository {
  /// Idempotent: if interrupted, calling it again finishes the
  /// deletion.
  Future<void> deleteAllForUser({required String userId});
}

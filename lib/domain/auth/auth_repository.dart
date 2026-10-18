import 'app_user.dart';

abstract class AuthRepository {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<AppUser> signInWithGoogle();

  Future<void> sendPasswordResetEmail({required String email});

  /// Sends the verification email to the currently signed-in user.
  Future<void> sendEmailVerification();

  /// Reloads the user from the provider to check whether the email has
  /// been verified yet.
  Future<AppUser> reloadUser();

  /// Re-checks the user's identity with their password. Required before
  /// sensitive operations such as deleting the account.
  Future<void> reauthenticateWithPassword({required String password});

  /// Re-checks the user's identity with Google (popup or native flow).
  Future<void> reauthenticateWithGoogle();

  /// Deletes the current user's authentication account. Requires a
  /// recent reauthentication.
  Future<void> deleteAccount();

  Future<void> signOut();
}

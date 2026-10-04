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

  Future<void> signOut();
}

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

  /// Envía el correo de verificación al usuario de la sesión actual.
  Future<void> sendEmailVerification();

  /// Recarga el usuario desde el proveedor para ver si ya verificó el correo.
  Future<AppUser> reloadUser();

  Future<void> signOut();
}

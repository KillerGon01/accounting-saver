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

  /// Vuelve a comprobar la identidad del usuario con su contraseña. Necesario
  /// antes de operaciones sensibles como borrar la cuenta.
  Future<void> reauthenticateWithPassword({required String password});

  /// Vuelve a comprobar la identidad del usuario con Google (popup o flujo nativo).
  Future<void> reauthenticateWithGoogle();

  /// Borra la cuenta de autenticación del usuario actual. Exige una
  /// reautenticación reciente.
  Future<void> deleteAccount();

  Future<void> signOut();
}

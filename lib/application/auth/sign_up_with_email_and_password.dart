import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_exception.dart';
import '../../domain/auth/auth_repository.dart';

class SignUpWithEmailAndPassword {
  SignUpWithEmailAndPassword(this._authRepository);

  final AuthRepository _authRepository;

  /// Crea la cuenta y envía el correo de verificación. Si el envío falla, la
  /// cuenta ya existe y la pantalla de verificación permite reenviarlo, así
  /// que el error no se propaga.
  Future<AppUser> call({required String email, required String password}) async {
    final user = await _authRepository.signUpWithEmailAndPassword(
      email: email,
      password: password,
    );
    try {
      await _authRepository.sendEmailVerification();
    } on AuthException {
      // Se ignora a propósito: VerifyEmailScreen ofrece reenviar el correo.
    }
    return user;
  }
}

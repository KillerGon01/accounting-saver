import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_exception.dart';
import '../../domain/auth/auth_repository.dart';

class SignUpWithEmailAndPassword {
  SignUpWithEmailAndPassword(this._authRepository);

  final AuthRepository _authRepository;

  /// Creates the account and sends the verification email. If sending
  /// it fails, the account already exists and the verification screen
  /// lets it be resent, so the error isn't propagated.
  Future<AppUser> call({required String email, required String password}) async {
    final user = await _authRepository.signUpWithEmailAndPassword(
      email: email,
      password: password,
    );
    try {
      await _authRepository.sendEmailVerification();
    } on AuthException {
      // Ignored on purpose: VerifyEmailScreen offers to resend the email.
    }
    return user;
  }
}

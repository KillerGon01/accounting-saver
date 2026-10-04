import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_repository.dart';

class SignUpWithEmailAndPassword {
  SignUpWithEmailAndPassword(this._authRepository);

  final AuthRepository _authRepository;

  Future<AppUser> call({required String email, required String password}) {
    return _authRepository.signUpWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}

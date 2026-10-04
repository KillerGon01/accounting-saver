import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_repository.dart';

class SignInWithGoogle {
  SignInWithGoogle(this._authRepository);

  final AuthRepository _authRepository;

  Future<AppUser> call() {
    return _authRepository.signInWithGoogle();
  }
}

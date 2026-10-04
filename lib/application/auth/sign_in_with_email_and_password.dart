import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_repository.dart';

class SignInWithEmailAndPassword {
  SignInWithEmailAndPassword(this._authRepository);

  final AuthRepository _authRepository;

  Future<AppUser> call({required String email, required String password}) {
    return _authRepository.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}

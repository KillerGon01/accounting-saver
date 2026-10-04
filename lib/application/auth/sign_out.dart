import '../../domain/auth/auth_repository.dart';

class SignOut {
  SignOut(this._authRepository);

  final AuthRepository _authRepository;

  Future<void> call() {
    return _authRepository.signOut();
  }
}

import '../../domain/auth/auth_repository.dart';

class SendPasswordResetEmail {
  SendPasswordResetEmail(this._authRepository);

  final AuthRepository _authRepository;

  Future<void> call({required String email}) {
    return _authRepository.sendPasswordResetEmail(email: email);
  }
}

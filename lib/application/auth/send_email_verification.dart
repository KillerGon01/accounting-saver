import '../../domain/auth/auth_repository.dart';

class SendEmailVerification {
  SendEmailVerification(this._authRepository);

  final AuthRepository _authRepository;

  Future<void> call() {
    return _authRepository.sendEmailVerification();
  }
}

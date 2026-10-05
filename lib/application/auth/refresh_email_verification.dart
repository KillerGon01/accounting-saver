import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_repository.dart';

class RefreshEmailVerification {
  RefreshEmailVerification(this._authRepository);

  final AuthRepository _authRepository;

  Future<AppUser> call() {
    return _authRepository.reloadUser();
  }
}

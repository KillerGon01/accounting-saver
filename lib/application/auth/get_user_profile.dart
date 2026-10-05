import '../../domain/auth/auth_repository.dart';
import '../../domain/auth/user_profile.dart';

class GetUserProfile {
  GetUserProfile(this._authRepository);

  final AuthRepository _authRepository;

  /// Null si no hay sesión iniciada.
  UserProfile? call() {
    final user = _authRepository.currentUser;
    return user == null ? null : UserProfile.fromAppUser(user);
  }
}

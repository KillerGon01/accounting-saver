import '../../domain/auth/account_deletion_exception.dart';
import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_exception.dart';
import '../../domain/auth/auth_repository.dart';
import '../../domain/auth/user_profile.dart';
import '../../domain/common/transactions_change_notifier.dart';
import '../../domain/user_data/user_data_repository.dart';

class DeleteAccount {
  DeleteAccount(this._authRepository, this._userDataRepository, [this._changeNotifier]);

  final AuthRepository _authRepository;
  final UserDataRepository _userDataRepository;
  final TransactionsChangeNotifier? _changeNotifier;

  /// Fixed order: (1) reauthenticate, (2) delete the transactions, (3)
  /// delete the Auth account. If reauthentication fails, nothing is
  /// deleted. If step 2 or 3 fails, [AccountDeletionException] is
  /// thrown stating the stage, and calling this use case again
  /// completes the deletion.
  ///
  /// [password] is only used with email and password; with Google, the
  /// reauthentication popup opens.
  Future<void> call({String? password}) async {
    final user = _authRepository.currentUser;
    if (user == null) throw const AuthException('no-current-user');

    await _reauthenticate(user, password);

    try {
      await _userDataRepository.deleteAllForUser(userId: user.uid);
    } catch (error) {
      throw AccountDeletionException(AccountDeletionStage.userData, error);
    }
    _changeNotifier?.notifyChanged();

    try {
      await _authRepository.deleteAccount();
    } catch (error) {
      throw AccountDeletionException(AccountDeletionStage.account, error);
    }
  }

  Future<void> _reauthenticate(AppUser user, String? password) async {
    final provider = UserProfile.fromAppUser(user).provider;
    switch (provider) {
      case SignInProvider.google:
        await _authRepository.reauthenticateWithGoogle();
      case SignInProvider.password:
        if (password == null || password.isEmpty) {
          throw const AuthException('password-required');
        }
        await _authRepository.reauthenticateWithPassword(password: password);
    }
  }
}

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

  /// Orden fijo: (1) reautenticar, (2) borrar los movimientos, (3) borrar la
  /// cuenta de Auth. Si la reautenticación falla, no se borra nada. Si falla
  /// el paso 2 o el 3, se lanza [AccountDeletionException] indicando la etapa,
  /// y volver a llamar a este caso de uso completa el borrado.
  ///
  /// [password] solo se usa con correo y contraseña; con Google se abre el
  /// popup de reautenticación.
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

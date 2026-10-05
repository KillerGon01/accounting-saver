import 'package:accounting_saver/domain/auth/app_user.dart';
import 'package:accounting_saver/domain/auth/auth_exception.dart';
import 'package:accounting_saver/domain/auth/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    AppUser? initialUser,
    this.signInError,
    this.signUpError,
    this.resetPasswordError,
    this.sendVerificationError,
    this.reloadError,
    this.reauthError,
    this.deleteAccountError,
  }) : currentUser = initialUser;

  /// Si se asigna, la operación correspondiente lanza este error.
  Object? signInError;
  Object? signUpError;
  Object? resetPasswordError;
  Object? sendVerificationError;
  Object? reloadError;
  Object? reauthError;
  Object? deleteAccountError;

  /// Si se asigna, cada operación espera a que se complete antes de responder
  /// (permite probar el estado de carga).
  Future<void>? responseGate;

  /// Simula que el usuario ya pulsó el enlace del correo: la siguiente recarga
  /// devuelve el usuario con `emailVerified` a true.
  bool emailVerifiedOnReload = false;

  final List<({String email, String password})> signInCalls = [];
  final List<({String email, String password})> signUpCalls = [];
  final List<String> resetPasswordCalls = [];
  final List<String> reauthMethods = [];
  int verificationEmailsSent = 0;
  int reloadCount = 0;
  bool accountDeleted = false;

  @override
  AppUser? currentUser;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<AppUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCalls.add((email: email, password: password));
    await responseGate;
    if (signInError != null) throw signInError!;
    return currentUser = _passwordUser(email);
  }

  @override
  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signUpCalls.add((email: email, password: password));
    await responseGate;
    if (signUpError != null) throw signUpError!;
    return currentUser = _passwordUser(email);
  }

  @override
  Future<AppUser> signInWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    resetPasswordCalls.add(email);
    await responseGate;
    if (resetPasswordError != null) throw resetPasswordError!;
  }

  @override
  Future<void> sendEmailVerification() async {
    await responseGate;
    if (sendVerificationError != null) throw sendVerificationError!;
    verificationEmailsSent++;
  }

  @override
  Future<AppUser> reloadUser() async {
    reloadCount++;
    await responseGate;
    if (reloadError != null) throw reloadError!;
    final user = currentUser;
    if (user == null) throw const AuthException('no-current-user');
    if (emailVerifiedOnReload) {
      return currentUser = AppUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        emailVerified: true,
        providerIds: user.providerIds,
        createdAt: user.createdAt,
        lastSignInAt: user.lastSignInAt,
      );
    }
    return user;
  }

  @override
  Future<void> reauthenticateWithPassword({required String password}) async {
    reauthMethods.add('password');
    await responseGate;
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    reauthMethods.add('google');
    await responseGate;
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> deleteAccount() async {
    await responseGate;
    if (deleteAccountError != null) throw deleteAccountError!;
    accountDeleted = true;
    currentUser = null;
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
  }

  AppUser _passwordUser(String email) => AppUser(
    uid: 'fake-uid',
    email: email,
    emailVerified: false,
    providerIds: const [passwordProviderId],
  );
}

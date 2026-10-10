import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_exception.dart';
import '../../domain/auth/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({firebase_auth.FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance;

  final firebase_auth.FirebaseAuth _firebaseAuth;

  @override
  Stream<AppUser?> authStateChanges() {
    return _firebaseAuth.authStateChanges().map(_toAppUser);
  }

  @override
  AppUser? get currentUser => _toAppUser(_firebaseAuth.currentUser);

  @override
  Future<AppUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _mapErrors(() async {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return _requireAppUser(credential.user);
    });
  }

  @override
  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _mapErrors(() async {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return _requireAppUser(credential.user);
    });
  }

  @override
  Future<AppUser> signInWithGoogle() {
    return _mapErrors(() async {
      final provider = firebase_auth.GoogleAuthProvider();
      final userCredential = kIsWeb
          ? await _firebaseAuth.signInWithPopup(provider)
          : await _firebaseAuth.signInWithProvider(provider);
      return _requireAppUser(userCredential.user);
    });
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    return _mapErrors(() => _firebaseAuth.sendPasswordResetEmail(email: email));
  }

  @override
  Future<void> sendEmailVerification() {
    return _mapErrors(() => _currentUserOrThrow().sendEmailVerification());
  }

  @override
  Future<AppUser> reloadUser() {
    return _mapErrors(() async {
      final user = _currentUserOrThrow();
      await user.reload();
      // Las reglas de Firestore leen `email_verified` del token, no del
      // perfil recargado por `reload()`: sin forzar un token nuevo aquí,
      // el cambio seguiría sin verse en Firestore hasta que el token
      // expirase solo (hasta 1 h) o se cerrara y abriera sesión de nuevo.
      // Va después de `reload()` y antes de devolver el usuario, para que
      // quien llama (`VerifyEmailScreen`, vía `RefreshEmailVerification`)
      // no pase a una pantalla que use Firestore con un token todavía
      // antiguo.
      await user.getIdToken(true);
      return _requireAppUser(_firebaseAuth.currentUser);
    });
  }

  @override
  Future<void> reauthenticateWithPassword({required String password}) {
    return _mapErrors(() async {
      final user = _currentUserOrThrow();
      await user.reauthenticateWithCredential(
        firebase_auth.EmailAuthProvider.credential(
          email: user.email ?? '',
          password: password,
        ),
      );
    });
  }

  @override
  Future<void> reauthenticateWithGoogle() {
    return _mapErrors(() async {
      final user = _currentUserOrThrow();
      final provider = firebase_auth.GoogleAuthProvider();
      if (kIsWeb) {
        await user.reauthenticateWithPopup(provider);
      } else {
        await user.reauthenticateWithProvider(provider);
      }
    });
  }

  @override
  Future<void> deleteAccount() {
    return _mapErrors(() => _currentUserOrThrow().delete());
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  Future<T> _mapErrors<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw AuthException(error.code, message: error.message);
    }
  }

  firebase_auth.User _currentUserOrThrow() {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw firebase_auth.FirebaseAuthException(
        code: 'no-current-user',
        message: 'No hay ningún usuario con sesión iniciada.',
      );
    }
    return user;
  }

  AppUser _requireAppUser(firebase_auth.User? user) {
    final appUser = _toAppUser(user);
    if (appUser == null) {
      throw firebase_auth.FirebaseAuthException(
        code: 'null-user',
        message: 'Firebase no devolvió un usuario autenticado.',
      );
    }
    return appUser;
  }

  AppUser? _toAppUser(firebase_auth.User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      email: user.email,
      emailVerified: user.emailVerified,
      providerIds: user.providerData.map((info) => info.providerId).toList(),
      displayName: user.displayName,
      createdAt: user.metadata.creationTime,
      lastSignInAt: user.metadata.lastSignInTime,
    );
  }
}

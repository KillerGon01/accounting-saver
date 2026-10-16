import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_exception.dart';
import '../../domain/auth/auth_repository.dart';
import 'native_google_credential.dart';

/// Único punto de la app que importa `google_sign_in` (a través de
/// `NativeGoogleCredential`): ni el dominio ni la presentación lo
/// conocen (ver docs/design.md, "Inicio de sesión con Google en
/// Android"). [googleSignIn] es inyectable solo para los tests (un
/// `GoogleSignIn` de verdad por defecto), igual que [firebaseAuth].
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    firebase_auth.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
       _nativeGoogle = NativeGoogleCredential(googleSignIn ?? GoogleSignIn());

  final firebase_auth.FirebaseAuth _firebaseAuth;
  final NativeGoogleCredential _nativeGoogle;

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
      if (kIsWeb) {
        final userCredential = await _firebaseAuth.signInWithPopup(firebase_auth.GoogleAuthProvider());
        return _requireAppUser(userCredential.user);
      }
      // Android (y el resto de plataformas nativas): el SDK nativo de
      // Google, no `signInWithProvider` (el flujo por pestaña de Chrome
      // que `identitytoolkit` bloquea con 403 "Requests from this
      // Android client application <empty> are blocked" — ver
      // docs/security.md).
      final credential = await _nativeGoogle();
      final userCredential = await _firebaseAuth.signInWithCredential(credential);
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
      if (kIsWeb) {
        await user.reauthenticateWithPopup(firebase_auth.GoogleAuthProvider());
        return;
      }
      // Mismo motivo que `signInWithGoogle`: sin esto, borrar la cuenta
      // de un usuario que entró con Google seguiría fallando en Android
      // (la reautenticación es obligatoria antes del borrado — ver
      // `DeleteAccount`).
      final credential = await _nativeGoogle();
      await user.reauthenticateWithCredential(credential);
    });
  }

  @override
  Future<void> deleteAccount() {
    return _mapErrors(() => _currentUserOrThrow().delete());
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    if (!kIsWeb) {
      try {
        // Sin esto, el selector nativo de Google (`NativeGoogleCredential`)
        // podría recordar la cuenta y no volver a mostrar el selector en
        // el siguiente inicio de sesión. Un fallo aquí no deshace el
        // `signOut` de Firebase de arriba — la sesión de la app ya ha
        // terminado igualmente.
        await _nativeGoogle.signOut();
      } catch (_) {
        // Ignorado a propósito: ver el comentario de arriba.
      }
    }
  }

  Future<T> _mapErrors<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw AuthException(error.code, message: error.message);
    } on PlatformException catch (error) {
      // `google_sign_in` lanza esto para sus propios errores nativos
      // (no es un `FirebaseAuthException`): mismo tipo de traducción,
      // para que nunca llegue a la interfaz un error sin pasar por
      // `authErrorMessage`.
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

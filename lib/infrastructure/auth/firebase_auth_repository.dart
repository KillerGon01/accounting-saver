import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_exception.dart';
import '../../domain/auth/auth_repository.dart';
import 'native_google_credential.dart';

/// The app's only point that imports `google_sign_in` (through
/// `NativeGoogleCredential`): neither the domain layer nor the
/// presentation layer know about it (see docs/design.md, "Inicio de
/// sesión con Google en Android"). [googleSignIn] is injectable only
/// for tests (a real `GoogleSignIn` by default), same as
/// [firebaseAuth].
///
/// On web, [_nativeGoogle] is always `null` (see
/// `createNativeGoogleCredential`): `GoogleSignIn` is never
/// instantiated on that platform, not even though it's never going to
/// be used — see docs/design.md, "Bug: `GoogleSignIn` se instanciaba
/// también en web". [isWeb] is injectable only for tests, for the
/// same reason as in `createNativeGoogleCredential`.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    firebase_auth.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    bool? isWeb,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
       _isWeb = isWeb ?? kIsWeb,
       _nativeGoogle = createNativeGoogleCredential(isWeb: isWeb ?? kIsWeb, googleSignIn: googleSignIn);

  final firebase_auth.FirebaseAuth _firebaseAuth;
  final bool _isWeb;

  /// Always non-null when [_isWeb] is `false` (see
  /// `createNativeGoogleCredential`): only used in the branches that
  /// already check `!_isWeb` first.
  final NativeGoogleCredential? _nativeGoogle;

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
      if (_isWeb) {
        final userCredential = await _firebaseAuth.signInWithPopup(firebase_auth.GoogleAuthProvider());
        return _requireAppUser(userCredential.user);
      }
      // Android (and the rest of native platforms): Google's native
      // SDK, not `signInWithProvider` (the Chrome-tab flow that
      // `identitytoolkit` blocks with a 403 "Requests from this
      // Android client application <empty> are blocked" — see
      // docs/security.md).
      final credential = await _nativeGoogle!();
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
      // Firestore's rules read `email_verified` from the token, not
      // from the profile reloaded by `reload()`: without forcing a
      // new token here, the change would still be invisible to
      // Firestore until the token expired on its own (up to 1 h) or
      // the session was closed and reopened. It goes after `reload()`
      // and before returning the user, so the caller
      // (`VerifyEmailScreen`, via `RefreshEmailVerification`) doesn't
      // move on to a screen that uses Firestore with a still-old
      // token.
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
      if (_isWeb) {
        await user.reauthenticateWithPopup(firebase_auth.GoogleAuthProvider());
        return;
      }
      // Same reason as `signInWithGoogle`: without this, deleting the
      // account of a user who signed in with Google would keep
      // failing on Android (reauthentication is required before
      // deletion — see `DeleteAccount`).
      final credential = await _nativeGoogle!();
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
    if (!_isWeb) {
      try {
        // Without this, Google's native selector
        // (`NativeGoogleCredential`) could remember the account and
        // not show the selector again on the next sign-in. A failure
        // here doesn't undo Firebase's `signOut` above — the app's
        // session has ended either way.
        await _nativeGoogle!.signOut();
      } catch (_) {
        // Ignored on purpose: see the comment above.
      }
    }
  }

  Future<T> _mapErrors<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw AuthException(error.code, message: error.message);
    } on PlatformException catch (error) {
      // `google_sign_in` throws this for its own native errors (it's
      // not a `FirebaseAuthException`): same kind of translation, so
      // an error never reaches the UI without going through
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

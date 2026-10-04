import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../domain/auth/app_user.dart';
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
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _requireAppUser(credential.user);
  }

  @override
  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _requireAppUser(credential.user);
  }

  @override
  Future<AppUser> signInWithGoogle() async {
    final provider = firebase_auth.GoogleAuthProvider();
    final userCredential = kIsWeb
        ? await _firebaseAuth.signInWithPopup(provider)
        : await _firebaseAuth.signInWithProvider(provider);
    return _requireAppUser(userCredential.user);
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
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
      displayName: user.displayName,
    );
  }
}

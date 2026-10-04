import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth/sign_in_with_email_and_password.dart';
import '../../application/auth/sign_in_with_google.dart';
import '../../application/auth/sign_out.dart';
import '../../application/auth/sign_up_with_email_and_password.dart';
import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_repository.dart';
import '../../infrastructure/auth/firebase_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository();
});

final authStateChangesProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final signInWithEmailAndPasswordProvider = Provider<SignInWithEmailAndPassword>(
  (ref) => SignInWithEmailAndPassword(ref.watch(authRepositoryProvider)),
);

final signUpWithEmailAndPasswordProvider = Provider<SignUpWithEmailAndPassword>(
  (ref) => SignUpWithEmailAndPassword(ref.watch(authRepositoryProvider)),
);

final signInWithGoogleProvider = Provider<SignInWithGoogle>(
  (ref) => SignInWithGoogle(ref.watch(authRepositoryProvider)),
);

final signOutProvider = Provider<SignOut>(
  (ref) => SignOut(ref.watch(authRepositoryProvider)),
);

// See the comment in `fake_google_sign_in_platform.dart` about
// `google_sign_in_platform_interface` (transitive dependency).
// ignore_for_file: depend_on_referenced_packages
import 'package:accounting_saver/infrastructure/auth/native_google_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import '../../fakes/fake_google_sign_in_platform.dart';

/// Covers the decision that caused the bug (see docs/design.md, "Bug:
/// `GoogleSignIn` se instanciaba también en web"): on web,
/// `FirebaseAuthRepository` must never construct a `GoogleSignIn` at
/// any point, because `GoogleSignIn()`'s own constructor triggers its
/// async initialization against `google_sign_in_web` right there, which
/// fails if there's no client ID configured (this app doesn't need one:
/// it uses `signInWithPopup` instead of the native selector).
///
/// `createNativeGoogleCredential` (in `native_google_credential.dart`) is
/// the exact function that used to always call `GoogleSignIn()`: now it
/// receives `isWeb` as a parameter instead of reading `kIsWeb`, so the
/// decision can be tested without depending on the real platform the
/// test runs on (`flutter test` always runs on the VM, where `kIsWeb` is
/// `false` — the real `isWeb == true` could never be reproduced without this).
///
/// This tests the decision itself, in isolation; testing
/// `FirebaseAuthRepository`'s full constructor isn't viable without
/// expressly modifying it: it would need a real
/// `firebase_auth.FirebaseAuth` instance (`FirebaseAuth.instance` calls
/// `Firebase.app()`, which throws "[core/no-app]" without
/// `Firebase.initializeApp()`), and this project has no Firebase mocks
/// package nor initializes it in tests — the same limitation already
/// documented for `FirebaseAuthRepository` in
/// `native_google_credential_test.dart` and in `CLAUDE.md`. Verified
/// manually instead: `flutter run -d chrome` (the app starts and both
/// Google and email login work) and `flutter build web --release` /
/// `flutter build apk --debug` with no errors.
void main() {
  test('en web, no se crea ningún NativeGoogleCredential (y por tanto, ningún GoogleSignIn)', () {
    final result = createNativeGoogleCredential(isWeb: true);

    expect(result, isNull);
  });

  test('fuera de web, sí se crea, con el GoogleSignIn inyectado si se da uno', () {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
    final injected = GoogleSignIn();

    final result = createNativeGoogleCredential(isWeb: false, googleSignIn: injected);

    expect(result, isNotNull);
  });

  test('fuera de web, sin inyectar ninguno, crea su propio GoogleSignIn por defecto', () {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();

    final result = createNativeGoogleCredential(isWeb: false);

    expect(result, isNotNull);
  });
}

// See the comment in `fake_google_sign_in_platform.dart` about
// `google_sign_in_platform_interface` (transitive dependency).
// ignore_for_file: depend_on_referenced_packages
import 'package:accounting_saver/infrastructure/auth/native_google_credential.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import '../../fakes/fake_google_sign_in_platform.dart';

/// `NativeGoogleCredential` is the app's only point of contact with
/// `google_sign_in` (see `docs/design.md`, "Inicio de sesión con Google
/// en Android"). It's tested here with the package's own fake backend
/// (`GoogleSignInPlatform.instance`), without touching the real plugin or
/// `FirebaseAuth` — `FirebaseAuthRepository` itself (how it connects
/// this credential with `signInWithCredential`/`reauthenticateWithCredential`)
/// still has no automated tests, same as the rest of that file
/// (it would need a real `FirebaseAuth` instance; it's been verified by
/// hand and with `flutter build apk --debug`).
void main() {
  late FakeGoogleSignInPlatform fakePlatform;
  late NativeGoogleCredential nativeGoogle;

  setUp(() {
    fakePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = fakePlatform;
    nativeGoogle = NativeGoogleCredential(GoogleSignIn());
  });

  test('éxito: construye la credencial de Firebase con el idToken del selector', () async {
    fakePlatform.userToReturn = GoogleSignInUserData(
      id: 'google-uid-1',
      email: 'ana@example.com',
    );
    fakePlatform.tokenDataToReturn = GoogleSignInTokenData(
      idToken: 'un-id-token',
      accessToken: 'un-access-token',
    );

    final credential = await nativeGoogle();

    expect(credential.idToken, 'un-id-token');
    expect(credential.accessToken, 'un-access-token');
    expect(credential.providerId, 'google.com');
  });

  test('cancelación: el selector devuelve null, no es un error sin traducir', () async {
    fakePlatform.userToReturn = null; // cancelled, same as the real GoogleSignIn already does

    await expectLater(
      nativeGoogle(),
      throwsA(
        isA<FirebaseAuthException>().having((e) => e.code, 'code', 'sign_in_canceled'),
      ),
    );
  });

  test('error: un fallo real del selector se propaga tal cual (lo traduce _mapErrors)', () async {
    fakePlatform.signInError = PlatformException(code: 'network_error', message: 'sin red');

    await expectLater(
      nativeGoogle(),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'network_error')),
    );
  });

  test('signOut: delega en GoogleSignIn.signOut()', () async {
    await nativeGoogle.signOut();

    expect(fakePlatform.signOutCalls, 1);
  });
}

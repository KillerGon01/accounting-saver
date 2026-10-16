// `google_sign_in_platform_interface` es una dependencia transitiva (de
// `google_sign_in`, el único paquete nuevo autorizado en pubspec.yaml):
// usarla aquí directamente, solo en tests, es el mecanismo oficial del
// propio paquete para fakear `GoogleSignIn` sin el plugin real. Se
// silencia el aviso en vez de declararla aparte en pubspec.yaml.
// ignore_for_file: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

/// Backend falso de `google_sign_in`, mediante el mecanismo oficial del
/// propio paquete (`GoogleSignInPlatform.instance`) — nunca se invoca el
/// plugin real ni ningún canal de plataforma. Ver
/// `test/infrastructure/auth/native_google_credential_test.dart`.
class FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  /// Si se asigna, `signIn()` lo devuelve (éxito). `null` (el valor por
  /// defecto) simula que el usuario canceló el selector de cuenta, igual
  /// que ya hace el `GoogleSignIn` real.
  GoogleSignInUserData? userToReturn;

  /// Si se asigna, `signIn()` lo lanza en vez de devolver [userToReturn].
  Object? signInError;

  /// Token devuelto por `getTokens()` (la llamada que hace
  /// `GoogleSignInAccount.authentication`).
  GoogleSignInTokenData tokenDataToReturn = GoogleSignInTokenData(idToken: 'fake-id-token');

  int signOutCalls = 0;

  @override
  Future<void> initWithParams(SignInInitParameters params) async {}

  @override
  Future<GoogleSignInUserData?> signIn() async {
    final error = signInError;
    if (error != null) throw error;
    return userToReturn;
  }

  @override
  Future<GoogleSignInTokenData> getTokens({required String email, bool? shouldRecoverAuth}) async {
    return tokenDataToReturn;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

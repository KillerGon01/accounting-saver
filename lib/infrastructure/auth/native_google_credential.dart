import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';

/// Selector de cuenta nativo de Google → credencial de Firebase, para
/// Android (y el resto de plataformas nativas) — nunca para web, que
/// sigue usando `signInWithPopup`/`reauthenticateWithPopup` sin cambios.
/// Aislado de `FirebaseAuthRepository` en su propia clase, con un único
/// método público (`call`), para poder probarlo con un `GoogleSignIn`
/// falso (`GoogleSignInPlatform.instance`, el mecanismo oficial del
/// propio paquete) sin necesitar ninguna instancia real de `FirebaseAuth`
/// — ver `docs/design.md`, "Inicio de sesión con Google en Android".
class NativeGoogleCredential {
  NativeGoogleCredential(this._googleSignIn);

  final GoogleSignIn _googleSignIn;

  /// Abre el selector de cuenta nativo y devuelve la credencial de
  /// Firebase correspondiente.
  ///
  /// `GoogleSignIn.signIn()` ya convierte la cancelación del selector en
  /// `null` (no lanza): aquí se traduce a una `FirebaseAuthException`
  /// propia (`sign_in_canceled`), con el mismo patrón que
  /// `FirebaseAuthRepository._currentUserOrThrow`, para que quien llame
  /// la pase por `_mapErrors` y salga como un `AuthException` neutro,
  /// nunca como un error sin traducir. Un error real del selector (p. ej.
  /// de red) llega como `PlatformException`, sin modificar.
  Future<firebase_auth.OAuthCredential> call() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw firebase_auth.FirebaseAuthException(
        code: 'sign_in_canceled',
        message: 'El usuario canceló el selector de cuenta de Google.',
      );
    }
    final authentication = await account.authentication;
    return firebase_auth.GoogleAuthProvider.credential(
      idToken: authentication.idToken,
      accessToken: authentication.accessToken,
    );
  }

  /// Cierra la sesión de Google guardada por el selector nativo. Sin
  /// esto, `GoogleSignIn.signIn()` podría devolver la misma cuenta
  /// cacheada en el siguiente inicio de sesión, sin mostrar el selector.
  Future<void> signOut() => _googleSignIn.signOut();
}

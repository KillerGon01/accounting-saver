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
/// Crea el `NativeGoogleCredential` de [FirebaseAuthRepository] para esta
/// plataforma, o `null` en web.
///
/// **Nunca** en web: el propio constructor de `GoogleSignIn()` (del
/// paquete `google_sign_in`, no de esta app) dispara su inicialización
/// asíncrona en cuanto se crea la instancia si `kIsWeb` es cierto —  antes
/// incluso de llamar a ningún método — y esa inicialización falla con
/// "ClientID not set" porque la app no configura ningún client ID de
/// Google Sign-In para la web (no lo necesita: usa
/// `signInWithPopup`/`reauthenticateWithPopup`, nunca este selector
/// nativo). El fallo ocurría antes con solo construir `FirebaseAuthRepository`
/// (en el arranque de la app), dejando la web en blanco — ver
/// `docs/design.md`, "Bug: `GoogleSignIn` se instanciaba también en web".
///
/// [isWeb] es un parámetro aparte (no se lee `kIsWeb` aquí dentro) para
/// que se pueda probar esta decisión sin depender de la plataforma real
/// en la que corren los tests (`flutter test` corre siempre en la VM,
/// donde `kIsWeb` es `false`).
NativeGoogleCredential? createNativeGoogleCredential({
  required bool isWeb,
  GoogleSignIn? googleSignIn,
}) {
  if (isWeb) return null;
  return NativeGoogleCredential(googleSignIn ?? GoogleSignIn());
}

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

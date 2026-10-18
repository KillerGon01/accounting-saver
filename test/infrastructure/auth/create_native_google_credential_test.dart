// Ver el comentario de `fake_google_sign_in_platform.dart` sobre
// `google_sign_in_platform_interface` (dependencia transitiva).
// ignore_for_file: depend_on_referenced_packages
import 'package:accounting_saver/infrastructure/auth/native_google_credential.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import '../../fakes/fake_google_sign_in_platform.dart';

/// Cubre la decisión que provocaba el bug (ver docs/design.md, "Bug:
/// `GoogleSignIn` se instanciaba también en web"): en web,
/// `FirebaseAuthRepository` no debe construir ningún `GoogleSignIn` en
/// ningún momento, porque el propio constructor de `GoogleSignIn()`
/// dispara ahí su inicialización asíncrona contra `google_sign_in_web`,
/// que falla si no hay un client ID configurado (esta app no lo
/// necesita: usa `signInWithPopup` en vez del selector nativo).
///
/// `createNativeGoogleCredential` (en `native_google_credential.dart`) es
/// la función exacta que antes llamaba siempre a `GoogleSignIn()`: ahora
/// recibe `isWeb` como parámetro en vez de leer `kIsWeb`, para poder
/// probar la decisión sin depender de la plataforma real en la que corre
/// el test (`flutter test` corre siempre en la VM, donde `kIsWeb` es
/// `false` — nunca se podría reproducir el `isWeb == true` real sin esto).
///
/// Esto prueba la decisión en sí, aislada; probar el constructor completo
/// de `FirebaseAuthRepository` no es viable sin tocarlo expresamente:
/// necesitaría una instancia real de `firebase_auth.FirebaseAuth`
/// (`FirebaseAuth.instance` llama a `Firebase.app()`, que lanza
/// "[core/no-app]" sin `Firebase.initializeApp()`), y este proyecto no
/// tiene ningún paquete de mocks de Firebase ni lo inicializa en los
/// tests — mismo límite ya documentado para `FirebaseAuthRepository` en
/// `native_google_credential_test.dart` y en `CLAUDE.md`. Verificado en
/// su lugar a mano: `flutter run -d chrome` (la app arranca y el login
/// con Google y con correo funcionan) y `flutter build web --release` /
/// `flutter build apk --debug` sin errores.
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

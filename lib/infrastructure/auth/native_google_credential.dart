import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';

/// Google's native account selector → Firebase credential, for
/// Android (and the rest of native platforms) — never for web, which
/// keeps using `signInWithPopup`/`reauthenticateWithPopup` unchanged.
/// Isolated from `FirebaseAuthRepository` in its own class, with a
/// single public method (`call`), so it can be tested with a fake
/// `GoogleSignIn` (`GoogleSignInPlatform.instance`, the package's own
/// official mechanism) without needing any real `FirebaseAuth`
/// instance — see `docs/design.md`, "Inicio de sesión con Google en
/// Android".
/// Creates [FirebaseAuthRepository]'s `NativeGoogleCredential` for
/// this platform, or `null` on web.
///
/// **Never** on web: `GoogleSignIn()`'s own constructor (from the
/// `google_sign_in` package, not from this app) triggers its async
/// initialization as soon as the instance is created if `kIsWeb` is
/// true — even before calling any method — and that initialization
/// fails with "ClientID not set" because the app configures no Google
/// Sign-In client ID for the web (it doesn't need one: it uses
/// `signInWithPopup`/`reauthenticateWithPopup`, never this native
/// selector). The failure used to happen just by constructing
/// `FirebaseAuthRepository` (at app startup), leaving the web blank —
/// see `docs/design.md`, "Bug: `GoogleSignIn` se instanciaba también
/// en web".
///
/// [isWeb] is a separate parameter (`kIsWeb` isn't read in here) so
/// this decision can be tested without depending on the real platform
/// the tests run on (`flutter test` always runs on the VM, where
/// `kIsWeb` is `false`).
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

  /// Opens the native account selector and returns the matching
  /// Firebase credential.
  ///
  /// `GoogleSignIn.signIn()` already turns the selector's
  /// cancellation into `null` (it doesn't throw): here it's translated
  /// into a `FirebaseAuthException` of its own (`sign_in_canceled`),
  /// with the same pattern as
  /// `FirebaseAuthRepository._currentUserOrThrow`, so the caller runs
  /// it through `_mapErrors` and it comes out as a neutral
  /// `AuthException`, never as an untranslated error. A real error
  /// from the selector (e.g. network) arrives as a `PlatformException`,
  /// unmodified.
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

  /// Signs out of the Google session saved by the native selector.
  /// Without this, `GoogleSignIn.signIn()` could return the same
  /// cached account on the next sign-in, without showing the selector.
  Future<void> signOut() => _googleSignIn.signOut();
}

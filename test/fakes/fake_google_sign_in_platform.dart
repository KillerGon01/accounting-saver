// `google_sign_in_platform_interface` is a transitive dependency (of
// `google_sign_in`, the only new package authorized in pubspec.yaml):
// using it directly here, only in tests, is the package's own
// official mechanism to fake `GoogleSignIn` without the real plugin.
// The warning is silenced instead of declaring it separately in
// pubspec.yaml.
// ignore_for_file: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

/// Fake `google_sign_in` backend, through the package's own official
/// mechanism (`GoogleSignInPlatform.instance`) — never invokes the
/// real plugin nor any platform channel. See
/// `test/infrastructure/auth/native_google_credential_test.dart`.
class FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  /// If set, `signIn()` returns it (success). `null` (the default
  /// value) simulates the user cancelling the account selector, same
  /// as the real `GoogleSignIn` already does.
  GoogleSignInUserData? userToReturn;

  /// If set, `signIn()` throws it instead of returning [userToReturn].
  Object? signInError;

  /// Token returned by `getTokens()` (the call
  /// `GoogleSignInAccount.authentication` makes).
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

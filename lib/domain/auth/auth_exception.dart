/// Provider-independent authentication error. The infrastructure layer
/// translates its own errors (e.g. FirebaseAuthException) into this
/// type, and the presentation layer decides the message to show based
/// on [code].
class AuthException implements Exception {
  const AuthException(this.code, {this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'AuthException($code)';
}

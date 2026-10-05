/// Error de autenticación independiente del proveedor. La infraestructura
/// traduce sus errores (p. ej. FirebaseAuthException) a este tipo, y la
/// presentación decide el mensaje a mostrar a partir de [code].
class AuthException implements Exception {
  const AuthException(this.code, {this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'AuthException($code)';
}

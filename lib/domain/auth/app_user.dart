/// Identificadores de proveedor de Firebase Auth usados por la aplicación.
const passwordProviderId = 'password';
const googleProviderId = 'google.com';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.providerIds,
    this.displayName,
    this.createdAt,
    this.lastSignInAt,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final List<String> providerIds;
  final String? displayName;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;

  /// Las cuentas creadas con correo y contraseña deben verificar su correo
  /// antes de usar la app. Los usuarios de Google ya vienen verificados.
  bool get needsEmailVerification =>
      !emailVerified && providerIds.contains(passwordProviderId);
}
